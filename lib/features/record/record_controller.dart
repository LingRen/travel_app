import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/ble/ble_platform.dart';
import '../../data/ble/sensor_monitor.dart';
import '../../data/location/location_service.dart';
import '../../data/ride_repository.dart';
import '../../domain/analysis/constants.dart';
import '../../domain/analysis/geo.dart';
import '../../domain/models/location_fix.dart';
import '../../domain/models/ride.dart';
import '../../domain/models/ride_status.dart';
import '../../domain/models/track_point.dart';
import '../../domain/recording/recording_session.dart';

/// 记录页的界面模式。见设计文档 10.1。
enum RecordViewMode { handlebar, pocket }

/// 记录页的界面状态。
class RecordState {
  const RecordState({
    this.rideId,
    this.phase,
    this.mode = RecordViewMode.handlebar,
    this.elapsedMs = 0,
    this.distanceM = 0,
    this.currentSpeedMps = 0,
    this.hr,
    this.cadence,
    this.hrConnected = false,
    this.cadenceConnected = false,
    this.gpsWeak = false,
    this.errorMessage,
  });

  final int? rideId;

  /// null 表示尚未开始记录。
  final RecordingPhase? phase;

  final RecordViewMode mode;
  final int elapsedMs;
  final double distanceM;
  final double currentSpeedMps;
  final int? hr;
  final int? cadence;
  final bool hrConnected;
  final bool cadenceConnected;

  /// GPS 超过 10 秒没有新点。见设计文档 11.2 的「信号弱」。
  final bool gpsWeak;

  /// 阻断类错误（定位权限 / 定位服务）或写入连续失败提示，非空时界面需展示。
  final String? errorMessage;

  bool get isActive =>
      phase == RecordingPhase.recording || phase == RecordingPhase.paused;

  bool get isPaused => phase == RecordingPhase.paused;

  bool get isFinished => phase == RecordingPhase.finished;

  int get elapsedSeconds => elapsedMs ~/ 1000;
}

final NotifierProvider<RecordController, RecordState> recordControllerProvider =
    NotifierProvider<RecordController, RecordState>(RecordController.new);

/// 记录会话的编排层：把定位流、传感器流、1Hz 节拍与批量落盘串起来。
class RecordController extends Notifier<RecordState> {
  /// 时钟与定位服务都从 provider 取，测试里可换成假实现。
  LocationService get _location => ref.read(locationServiceProvider);

  RecordingSession? _session;
  Timer? _ticker;
  StreamSubscription<LocationFix>? _fixSub;
  SensorMonitor? _hrMonitor;
  SensorMonitor? _cadenceMonitor;

  int? _rideId;
  RecordViewMode _mode = RecordViewMode.handlebar;
  bool _hrConnected = false;
  bool _cadenceConnected = false;
  bool _finished = false;
  int _lastFixMs = 0;
  int _writeFailures = 0;
  String? _error;
  Future<void>? _pendingWrite;

  @override
  RecordState build() {
    ref.onDispose(_teardown);
    return const RecordState();
  }

  /// 切换界面模式。只影响渲染，不触碰记录逻辑。见设计文档 10.1。
  void setMode(RecordViewMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    _publish();
  }

  /// 开始一次新记录。定位权限或定位服务不满足时直接返回并给出提示。
  Future<void> start() async {
    if (_session != null) return;
    _error = null;

    final LocationReadiness readiness = await _location.checkReadiness();
    if (readiness != LocationReadiness.ready) {
      _error = switch (readiness) {
        LocationReadiness.serviceDisabled => '系统定位服务未开启，请先打开定位',
        LocationReadiness.permissionDenied => '未获得定位权限，无法记录骑行',
        LocationReadiness.permissionDeniedForever => '定位权限已被永久拒绝，请到系统设置中开启',
        LocationReadiness.ready => null,
      };
      _publish();
      return;
    }

    final Ride ride = await ref.read(rideRepositoryProvider).startRide(
          startedAtMs: _now(),
          hrDeviceName: _hrMonitor?.deviceName,
          cadenceDeviceName: _cadenceMonitor?.deviceName,
        );
    _rideId = ride.id;
    _session = RecordingSession(rideId: ride.id!, startedAtMs: ride.startedAtMs);
    _startStreams();
    _publish();
  }

  /// 崩溃恢复：接着写已有的会话。见设计文档 6.4。
  ///
  /// 已落盘的那段时长与距离不在内存里，这里按「相邻点间隔之和」补算，
  /// 让界面从正确的基数继续显示；最终汇总仍由 computeSummary 从全部点算出。
  Future<void> resumeExisting(int rideId) async {
    if (_session != null) return;

    final RideRepository repo = ref.read(rideRepositoryProvider);
    final Ride? ride = await repo.getRide(rideId);
    if (ride == null) return;
    final List<TrackPoint> points = await repo.getPoints(rideId);

    int elapsedMs = 0;
    double distanceM = 0;
    for (int i = 1; i < points.length; i++) {
      final int dt = points[i].tMs - points[i - 1].tMs;
      if (dt <= 0 || dt > kGpsGapMs) continue;
      elapsedMs += dt;
      distanceM += segmentDistanceMeters(points[i - 1], points[i]);
    }

    _rideId = rideId;
    _session = RecordingSession(
      rideId: rideId,
      startedAtMs: ride.startedAtMs,
      initialElapsedMs: elapsedMs,
      initialDistanceM: distanceM,
      lastWritten: points.isEmpty ? null : points.last,
      // 计时从「恢复这一刻」继续：startedAtMs 可能在几小时前，而崩溃到重启
      // 之间的空档不是骑行时间，不能计入时长。
      resumedAtMs: _now(),
    );
    _startStreams();
    _publish();
  }

  void pause() {
    final RecordingSession? session = _session;
    if (session == null || _finished) return;
    session.pause(_now());
    unawaited(_flush(force: true));
    unawaited(ref.read(rideRepositoryProvider).setStatus(_rideId!, RideStatus.paused));
    _publish();
  }

  void resume() {
    final RecordingSession? session = _session;
    if (session == null || _finished) return;
    session.resume(_now());
    unawaited(ref.read(rideRepositoryProvider).setStatus(_rideId!, RideStatus.recording));
    _publish();
  }

  /// 结束记录并结算汇总。结束后状态保留在 [RecordState] 里供界面展示。
  Future<void> finish() async {
    final RecordingSession? session = _session;
    if (session == null || _finished) return;
    _finished = true;

    _ticker?.cancel();
    _ticker = null;
    // 不 await：广播流的 cancel() 返回的是 root zone 里已完成的 future，
    // 在 FakeAsync 下它的续延永远不会被 flush，await 会把测试挂死；
    // 而广播流本身取消是立即生效的，等它没有任何收益。
    unawaited(_fixSub?.cancel());
    _fixSub = null;
    await _hrMonitor?.dispose();
    await _cadenceMonitor?.dispose();
    _hrMonitor = null;
    _cadenceMonitor = null;
    _hrConnected = false;
    _cadenceConnected = false;

    final int now = _now();
    final List<TrackPoint> remaining = session.finish(now);
    await _persist(remaining);
    await _flush(force: true);

    await ref.read(rideRepositoryProvider).finishRide(
          _rideId!,
          endedAtMs: now,
          durationS: session.snapshot.elapsedSeconds,
        );
    _publish();
  }

  /// 回到「未开始」状态，供用户开始下一次记录。
  void reset() {
    _session = null;
    _rideId = null;
    _finished = false;
    _error = null;
    _writeFailures = 0;
    _lastFixMs = 0;
    state = const RecordState();
  }

  /// 连接一个传感器。失败不阻断骑行，[SensorMonitor] 会自动退避重连。
  Future<void> connectSensor(SensorKind kind, BleDeviceHandle device) async {
    if (kind == SensorKind.heartRate) {
      await _hrMonitor?.dispose();
      _hrMonitor = SensorMonitor(
        device: device,
        kind: kind,
        onReading: _onSensorReading,
        onConnectionChanged: _onSensorConnection,
      );
      await _hrMonitor!.start();
      return;
    }

    await _cadenceMonitor?.dispose();
    _cadenceMonitor = SensorMonitor(
      device: device,
      kind: kind,
      onReading: _onSensorReading,
      onConnectionChanged: _onSensorConnection,
    );
    await _cadenceMonitor!.start();
  }

  /// App 退到后台时强制落盘一次，缩小崩溃丢数据的窗口。见设计文档 6.3。
  void handleLifecycle(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      unawaited(_flush(force: true));
    }
  }

  void _startStreams() {
    _fixSub = _location.fixes().listen(_onFix, onError: (Object _) {});
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void _onFix(LocationFix fix) {
    final RecordingSession? session = _session;
    if (session == null) return;
    _lastFixMs = fix.tMs;
    session.ingestFix(fix);
    // 实时 UI 按 1Hz 刷新（见设计文档 6.2），因此这里不 publish，
    // 由 _onTick 统一推送，避免每秒几十次重建。
    unawaited(_flush());
  }

  void _onTick() {
    final RecordingSession? session = _session;
    if (session == null || _finished) return;
    session.tick(_now());
    _publish();
    unawaited(_flush());
  }

  void _onSensorReading(SensorKind kind, num value) {
    final RecordingSession? session = _session;
    if (session == null) return;
    if (kind == SensorKind.heartRate) {
      session.ingestHeartRate(value.round());
    } else {
      session.ingestCadence(value.toDouble());
    }
  }

  void _onSensorConnection(SensorKind kind, bool connected) {
    if (kind == SensorKind.heartRate) {
      _hrConnected = connected;
    } else {
      _cadenceConnected = connected;
    }
    _publish();
  }

  /// 攒够一批就提交一个事务；[force] 为真时无条件提交（暂停、结束、退后台）。
  Future<void> _flush({bool force = false}) async {
    final RecordingSession? session = _session;
    if (session == null) return;

    // 等上一次写库结束，避免并发写同一张表。
    final Future<void>? inflight = _pendingWrite;
    if (inflight != null) await inflight;

    if (!force && !session.shouldFlush) return;
    final List<TrackPoint> batch = session.takePendingPoints();
    if (batch.isEmpty) return;

    final Future<void> write = _persist(batch);
    _pendingWrite = write;
    await write;
    if (identical(_pendingWrite, write)) _pendingWrite = null;
  }

  /// 写库失败先重试一次；连续三次失败才提示用户。见设计文档 11.2。
  Future<void> _persist(List<TrackPoint> points) async {
    if (points.isEmpty) return;
    final RideRepository repo = ref.read(rideRepositoryProvider);
    final int rideId = _rideId!;

    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        await repo.appendPoints(rideId, points);
        _writeFailures = 0;
        return;
      } catch (_) {
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      }
    }

    _writeFailures++;
    if (_writeFailures >= 3) {
      _error = '轨迹写入连续失败，请检查手机存储空间';
      _publish();
    }
  }

  void _publish() {
    final RecordingSnapshot? snap = _session?.snapshot;
    state = RecordState(
      rideId: _rideId,
      phase: snap?.phase,
      mode: _mode,
      elapsedMs: snap?.elapsedMs ?? 0,
      distanceM: snap?.distanceM ?? 0,
      currentSpeedMps: snap?.currentSpeedMps ?? 0,
      hr: snap?.hr,
      cadence: snap?.cadence,
      hrConnected: _hrConnected,
      cadenceConnected: _cadenceConnected,
      gpsWeak: _isGpsWeak(),
      errorMessage: _error,
    );
  }

  bool _isGpsWeak() {
    if (_session == null || _lastFixMs == 0) return false;
    return _now() - _lastFixMs > kGpsGapMs;
  }

  int _now() => ref.read(nowProvider)();

  void _teardown() {
    _ticker?.cancel();
    _fixSub?.cancel();
    _hrMonitor?.dispose();
    _cadenceMonitor?.dispose();
  }
}
