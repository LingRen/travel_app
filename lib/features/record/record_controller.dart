import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/ble/ble_platform.dart';
import '../../data/ble/sensor_monitor.dart';
import '../../data/location/location_service.dart';
import '../../data/sensor_pairing.dart';
import '../../data/settings_repository.dart';
import '../../data/workout_repository.dart';
import '../../domain/analysis/constants.dart';
import '../../domain/analysis/elevation.dart';
import '../../domain/analysis/geo.dart';
import '../../domain/models/activity_type.dart';
import '../../domain/models/location_fix.dart';
import '../../domain/models/track_point.dart';
import '../../domain/models/workout.dart';
import '../../domain/models/workout_status.dart';
import '../../domain/recording/recording_session.dart';
import '../../domain/recording/ride_cue.dart';
import 'ride_cue_player.dart';

/// 记录页的界面状态。
class RecordState {
  const RecordState({
    this.rideId,
    this.phase,
    this.foreground = true,
    this.elapsedMs = 0,
    this.distanceM = 0,
    this.currentSpeedMps = 0,
    this.hr,
    this.cadence,
    this.power,
    this.hrConnected = false,
    this.cadenceConnected = false,
    this.powerConnected = false,
    this.gpsWeak = false,
    this.errorMessage,
    this.liveTrack = const <TrackPoint>[],
    this.liveTrackBreaks = const <int>{},
    this.previewFix,
    this.currentAltitudeM,
    this.elevationGainM = 0,
    this.lastCue,
    this.cueSeq = 0,
    this.selectedActivityType = ActivityType.cycling,
  });

  final int? rideId;

  /// null 表示尚未开始记录。
  final RecordingPhase? phase;

  /// App 是否在前台。熄屏与切到别的 App 在系统层是同一个事件，都算离开前台
  /// （见设计文档 10.1）：常亮与界面刷新都跟着它走，亮屏即回到读数界面。
  final bool foreground;

  final int elapsedMs;
  final double distanceM;
  final double currentSpeedMps;
  final int? hr;
  final int? cadence;
  final int? power;
  final bool hrConnected;
  final bool cadenceConnected;
  final bool powerConnected;

  /// GPS 超过 10 秒没有新点。见设计文档 11.2 的「信号弱」。
  final bool gpsWeak;

  /// 阻断类错误（定位权限 / 定位服务）或写入连续失败提示，非空时界面需展示。
  final String? errorMessage;

  /// 本次骑行已抽稀的轨迹，供缩略图绘制。见设计文档 9.4。
  ///
  /// 这里传的是 [RecordingSession] 内部那个列表的**引用**（每秒重建状态时不做
  /// 拷贝），而那个列表只在真正追加或压缩时换新对象——所以界面可以靠
  /// `identical` 判断轨迹有没有变，不必每秒重算折线。
  final List<TrackPoint> liveTrack;

  /// [liveTrack] 上真实 GPS 丢失造成的段首下标（和列表一样透传引用）。
  ///
  /// 缩略图**不能**自己按时间差判断点：抽稀后相邻两点本来就常常隔十几秒，
  /// 按 [kGpsGapMs] 卡会把连续轨迹切碎。真实丢失由采集侧标记后传下来。
  final Set<int> liveTrackBreaks;

  /// 开始记录时先拿到的一次粗略定位，用来在 GPS 锁星前点亮地图。
  ///
  /// 只进界面、不落盘：它不是轨迹点，第一个真实定位点到达时清空
  /// （见 [_loadPreviewFix] 与 [_onFix]）。
  final LocationFix? previewFix;

  /// 最近一次可信定位的海拔（米）。没有高程数据时为 null，界面显示 `--`。
  final double? currentAltitudeM;

  /// 本次骑行到此刻为止的累计爬升（米）。见设计文档 8.1 与 10.1。
  final double elevationGainM;

  /// 最近一条提示（每 1 公里 / 每 10 公里 / 速度跨档），供浮层横幅展示。
  ///
  /// 取走后不置空：横幅自己按 [cueSeq] 判断「来没来新的一条」。置空反而会让
  /// 横幅在消失时把已经建好的子树拆掉，闪一下。
  final RideCue? lastCue;

  /// 提示序号，每产生一条新提示 +1。同一句提示重复出现时靠它重新计时。
  final int cueSeq;

  /// 选中的运动类型。未开始时由 chip 行修改；开始记录时冻结落库。
  final ActivityType selectedActivityType;

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

  /// 每种传感器至多一个连接。用 Map 而不是三个字段：连接/断开/记配对/
  /// 取设备名这些地方是按「类型」做的同一件事，写三遍迟早会漏一个。
  final Map<SensorKind, SensorMonitor> _monitors = <SensorKind, SensorMonitor>{};

  /// 当前已连上的传感器类型。
  final Set<SensorKind> _connected = <SensorKind>{};

  /// 自动重连的整体时间预算。
  ///
  /// 传感器不在身边时 `connect` 要等满 10 秒超时，不能让「开始骑行」卡那么久。
  /// 超时后记录照常开始，[SensorMonitor] 的退避重连会继续在后台尝试。
  static const Duration _kAutoConnectBudget = Duration(seconds: 3);

  SensorPairingRepository get _pairing => ref.read(sensorPairingProvider);

  BlePlatform get _blePlatform => ref.read(blePlatformProvider);

  /// 提示播报出口。每次现取，测试里覆盖 provider 就能换成假实现。
  RideCuePlayer get _cuePlayer => ref.read(rideCuePlayerProvider);

  int? _rideId;
  bool _finished = false;
  int _lastFixMs = 0;

  /// 见 [RecordState.previewFix]。
  LocationFix? _previewFix;

  int _writeFailures = 0;
  String? _error;
  Future<void>? _pendingWrite;

  /// 最近一条提示与它的序号，见 [RecordState.lastCue] / [RecordState.cueSeq]。
  RideCue? _lastCue;
  int _cueSeq = 0;

  /// 选中的运动类型。未开始态由 chip 行修改；开始记录时冻结落库。
  ActivityType _selectedActivityType = ActivityType.cycling;

  /// 本次运行里用户是否亲手挑过类型。挑过之后设置再读出来也不覆盖他的选择。
  bool _typeTouched = false;

  /// App 是否在前台。见设计文档 10.1 的「熄屏与后台」。
  bool _foreground = true;

  /// 上一次节拍判定出的「信号弱」状态。只在翻转的那一刻播报一次，
  /// 否则每秒一条「GPS 信号弱」会把其它提示全淹掉。
  bool _wasGpsWeak = false;

  /// 后台期间上次强制落盘的时刻，用于把崩溃丢数据的窗口压到 3 秒内。
  int _lastBackgroundFlushMs = 0;

  static const int _kBackgroundFlushIntervalMs = 3000;

  @override
  RecordState build() {
    ref.onDispose(_teardown);

    // 冷启动沿用上次选中的类型。类型只活在内存里时，用户选好徒步、切走被系统
    // 回收、回来直接点开始，落库的就是默认的骑行——事后只能手改库。
    _selectedActivityType =
        ref.read(appSettingsProvider).value?.lastActivityType ??
            ActivityType.cycling;
    // 设置是异步读的：首帧可能还没到位，等它出来再补上（用户已亲手挑过则不动）。
    ref.listen<AsyncValue<AppSettings>>(
      appSettingsProvider,
      (AsyncValue<AppSettings>? _, AsyncValue<AppSettings> next) =>
          _restoreSelectedType(next.value),
    );

    return RecordState(selectedActivityType: _selectedActivityType);
  }

  /// 设置读出来之后，用上次保存的类型补齐当前选择。
  void _restoreSelectedType(AppSettings? settings) {
    if (settings == null || _session != null || _typeTouched) return;
    _selectedActivityType = settings.lastActivityType;
    _publish();
  }

  /// 开始一次新记录。定位权限或定位服务不满足时直接返回并给出提示。
  Future<void> start() async {
    if (_session != null) return;
    _error = null;
    _lastFixMs = 0;
    _wasGpsWeak = false;

    // 快照选中类型：start() 全程（等待权限/连传感器）都用这一刻的类型，
    // 期间用户点 chip 不再影响本次落库——「开始」按钮显示什么，落库就是什么。
    final ActivityType type = _selectedActivityType;

    final LocationReadiness readiness = await _location.checkReadiness();
    if (readiness != LocationReadiness.ready) {
      _error = switch (readiness) {
        LocationReadiness.serviceDisabled => '系统定位服务未开启，请先打开定位',
        LocationReadiness.permissionDenied => '未获得定位权限，无法开始记录',
        LocationReadiness.permissionDeniedForever => '定位权限已被永久拒绝，请到系统设置中开启',
        LocationReadiness.ready => null,
      };
      _publish();
      return;
    }

    // 不 await：粗略定位只是「先把地图点亮」，慢一点也不能拖住记录开始。
    unawaited(_loadPreviewFix());

    // 见设计文档 6.1：连接传感器属于 preparing 阶段，放在建记录之前，
    // 这样 workouts 的三个 *_device_name 才有值。
    await _autoConnectPairedSensors().timeout(_kAutoConnectBudget, onTimeout: () {});

    // 估算功率要用体重。只在这里取一次：骑行中途改设置不该让已经记下的读数变样。
    // 设置还没读出来时（首帧）退回默认体重，不影响记录本身。
    // riverpod 3 的 `AsyncValue` 没有 `valueOrNull`，用 `.value`（可为 null）。
    final double weightKg =
        ref.read(appSettingsProvider).value?.weightKg ?? kDefaultWeightKg;

    final Workout ride = await ref.read(workoutRepositoryProvider).startWorkout(
          startedAtMs: _now(),
          activityType: type,
          hrDeviceName: _monitors[SensorKind.heartRate]?.deviceName,
          cadenceDeviceName: _monitors[SensorKind.cadence]?.deviceName,
          powerDeviceName: _monitors[SensorKind.power]?.deviceName,
        );
    _rideId = ride.id;
    _session = RecordingSession(
      rideId: ride.id!,
      startedAtMs: ride.startedAtMs,
      activityType: type,
      weightKg: weightKg,
    );
    _startStreams();
    _publish();
  }

  /// 崩溃恢复：接着写已有的会话。见设计文档 6.4。
  ///
  /// 已落盘的那段时长与距离不在内存里，这里按「相邻点间隔之和」补算，
  /// 让界面从正确的基数继续显示；最终汇总仍由 computeSummary 从全部点算出。
  Future<void> resumeExisting(int rideId) async {
    if (_session != null) return;

    final WorkoutRepository repo = ref.read(workoutRepositoryProvider);
    final Workout? ride = await repo.getWorkout(rideId);
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
    // 恢复的会话按已落盘的类型渲染：横幅动词、配速主读数都跟着它走。
    _selectedActivityType = ride.activityType;
    _session = RecordingSession(
      rideId: rideId,
      startedAtMs: ride.startedAtMs,
      activityType: ride.activityType,
      weightKg:
          ref.read(appSettingsProvider).value?.weightKg ?? kDefaultWeightKg,
      initialElapsedMs: elapsedMs,
      initialDistanceM: distanceM,
      // 爬升也按已落盘的点补算，与结算走同一条口径。不补的话续写期间「爬升」
      // 会从 0 重新长起来，屏幕上直接掉一截。
      initialElevationGainM: elevationGainOf(points),
      lastWritten: points.isEmpty ? null : points.last,
      recentTrack: points,
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
    unawaited(ref.read(workoutRepositoryProvider).setStatus(_rideId!, WorkoutStatus.paused));
    _publish();
  }

  void resume() {
    final RecordingSession? session = _session;
    if (session == null || _finished) return;
    session.resume(_now());
    // 暂停期间没有定位是正常的：恢复后从头开始算「多久没拿到点」，
    // 否则一恢复就会先播一条「GPS 信号弱」，紧接着再播「定位已恢复」。
    _lastFixMs = _now();
    _wasGpsWeak = false;
    unawaited(ref.read(workoutRepositoryProvider).setStatus(_rideId!, WorkoutStatus.recording));
    _publish();
  }

  /// 结束记录并结算汇总。结束后状态保留在 [RecordState] 里供界面展示。
  Future<void> finish() async {
    final RecordingSession? session = _session;
    if (session == null || _finished) return;
    _finished = true;
    _previewFix = null;

    _ticker?.cancel();
    _ticker = null;
    // 不 await：广播流的 cancel() 返回的是 root zone 里已完成的 future，
    // 在 FakeAsync 下它的续延永远不会被 flush，await 会把测试挂死；
    // 而广播流本身取消是立即生效的，等它没有任何收益。
    unawaited(_fixSub?.cancel());
    _fixSub = null;
    await _disposeMonitors();

    final int now = _now();
    final List<TrackPoint> remaining = session.finish(now);
    await _persist(remaining);
    await _flush(force: true);

    await ref.read(workoutRepositoryProvider).finishRide(
          _rideId!,
          endedAtMs: now,
          durationS: session.snapshot.elapsedSeconds,
        );
    _publish();
  }

  /// 回到「未开始」状态，供用户开始下一次记录。
  ///
  /// 选中的运动类型**保留**：用户上一次选的是跑步，下一次进来还想跑，不用重选。
  void reset() {
    _session = null;
    _rideId = null;
    _finished = false;
    _error = null;
    _writeFailures = 0;
    _lastFixMs = 0;
    _previewFix = null;
    _lastBackgroundFlushMs = 0;
    _lastCue = null;
    _cueSeq = 0;
    _wasGpsWeak = false;
    state = RecordState(
      foreground: _foreground,
      selectedActivityType: _selectedActivityType,
    );
    // 结算页点「完成」回到待机：顺手重新预热定位，下一次开始前地图与精度
    // 不用再从空白开始。
    unawaited(loadIdlePreview());
  }

  /// 未开始时切换运动类型。记录中不可切换：类型在开始那一刻已经冻结落库。
  void selectActivityType(ActivityType type) {
    if (_session != null) return; // 记录中不可切换
    _typeTouched = true;
    if (_selectedActivityType == type) return;
    _selectedActivityType = type;
    _persistSelectedType(type);
    _publish();
  }

  /// 记住这次选择，下次冷启动沿用。
  ///
  /// 写库失败（磁盘满、库被占用）不该妨碍这次记录：吞掉异常，只是下次启动
  /// 回到默认类型，不会让用户点一下 chip 就报错。
  void _persistSelectedType(ActivityType type) {
    unawaited(() async {
      try {
        await ref.read(settingsRepositoryProvider).saveLastActivityType(type);
      } catch (_) {
        // 见方法注释。
      }
    }());
  }

  /// 连接一个传感器。失败不阻断骑行，[SensorMonitor] 会自动退避重连。
  ///
  /// 同一类型已有连接时先释放：换设备不应该留下一个还在后台重连的旧连接。
  /// 不支持的传感器类型（跑步时点踏频入口）直接忽略，不弹任何反馈——界面上
  /// 压根没有那个入口。
  Future<void> connectSensor(SensorKind kind, BleDeviceHandle device) async {
    if (!_sensorKindAllowed(kind)) return;
    await _monitors.remove(kind)?.dispose();

    final SensorMonitor monitor = SensorMonitor(
      device: device,
      kind: kind,
      onReading: _onSensorReading,
      onConnectionChanged: _onSensorConnection,
    );
    _monitors[kind] = monitor;
    await monitor.start();
  }

  Future<void> _disposeMonitors() async {
    for (final SensorMonitor monitor in _monitors.values) {
      await monitor.dispose();
    }
    _monitors.clear();
    _connected.clear();
  }

  /// App 进后台（熄屏、切走）或回到前台时调用。见设计文档 10.1 的「熄屏与后台」。
  ///
  /// 熄屏与切到别的 App 在系统层是同一个事件，这里不区分：都按「离开前台」
  /// 处理，亮屏回来就是同一个读数界面。后台做三件事：
  ///   - 立刻强制落盘一次，缩小崩溃丢数据的窗口；
  ///   - 之后每 [_kBackgroundFlushIntervalMs] 再强制落盘一次（此时界面看不见，
  ///     拿 CPU 换可靠性是划算的）；
  ///   - 停止每秒重建界面状态（`_onTick` 里判断），缩略图因此完全不重绘。
  ///
  /// **1Hz 节拍不停**：时长推进、超速衰减、纯传感器点补写、GPS 弱信号判定
  /// 都挂在它上面，停了这些就全错。
  void handleLifecycle(AppLifecycleState state) {
    final bool foreground = state == AppLifecycleState.resumed;
    if (foreground != _foreground) _foreground = foreground;
    if (!foreground) unawaited(_flush(force: true));
    _publish();
  }

  /// 待机页预热定位：已有权限时先拿一次粗略定位，点亮地图并给出精度。
  ///
  /// 只读权限、不主动申请——用户还没按「开始」，弹权限框太早。没有权限或
  /// 室外还没锁星时安静地停在「等待定位」，按下开始会走 [start] 的完整校验。
  Future<void> loadIdlePreview() async {
    // reset() 会 fire-and-forget 地调用它；测试或页面销毁可能赶在异步结果
    // 回来之前，读已释放的 Ref 会直接抛异常。
    if (!ref.mounted || _session != null || _finished) return;
    if (!await _location.hasPermission()) return;
    if (!ref.mounted) return;
    final LocationFix? fix = await _location.quickPreviewFix();
    if (!ref.mounted ||
        fix == null ||
        _session != null ||
        _finished ||
        _lastFixMs != 0) {
      return;
    }
    _previewFix = fix;
    _publish();
  }

  /// 请求一次粗略定位并推到界面，只为在 GPS 锁星前点亮地图。
  ///
  /// 真实定位点一到就作废：有真点之后粗略位置只会是干扰。
  Future<void> _loadPreviewFix() async {
    final LocationFix? fix = await _location.quickPreviewFix();
    if (fix == null || _lastFixMs != 0 || _finished) return;
    _previewFix = fix;
    _publish();
  }

  void _startStreams() {
    _fixSub = _location.fixes().listen(_onFix, onError: (Object _) {});
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void _onFix(LocationFix fix) {
    final RecordingSession? session = _session;
    if (session == null) return;
    _previewFix = null;
    _lastFixMs = fix.tMs;
    session.ingestFix(fix);
    // 定位点一到就把读数推上界面，而不是等下一个 1Hz 节拍。
    //
    // 原来这里只落盘不 publish，速度因此最多要晚 1 秒才显示——再加上定位本身
    // 的解算与上报延迟，主观上就是「速度慢半拍、不跟脚」。定位点通常本来就是
    // 1Hz，跟着数据推送带来的重建量几乎没变；后台照旧不推送（见 _onTick）。
    if (_foreground && !_finished) _publish();
    unawaited(_flush());
  }

  void _onTick() {
    final RecordingSession? session = _session;
    if (session == null || _finished) return;
    session.tick(_now());

    _drainCues(session);
    _collectGpsCues(session);

    if (_foreground) {
      _publish();
      unawaited(_flush());
      return;
    }

    // 后台不重建界面状态：界面看不见，重建纯属白烧 CPU（缩略图也跟着重绘）。
    // 回到前台时 handleLifecycle 会补一次 publish，读数不会停在旧值上。
    // 改成按固定节拍强制落盘，把崩溃丢数据的窗口从「攒满一批」压到 3 秒。
    if (_now() - _lastBackgroundFlushMs >= _kBackgroundFlushIntervalMs) {
      _lastBackgroundFlushMs = _now();
      unawaited(_flush(force: true));
    }
  }

  /// 取走这一拍判定出来的提示并播报。
  ///
  /// **刻意与前台判断解耦**：熄屏放口袋时界面不重建，但语音必须照常念出来——
  /// 选语音播报的全部理由就是这种场景。只在亮屏时播报等于这个功能没做。
  void _drainCues(RecordingSession session) => _emitCues(session.takeCues());

  /// 信号弱的进出各播报一次。见设计文档 11.2。
  ///
  /// 只在 recording 阶段判：暂停期间没有新定位是正常的，不该播「信号弱」。
  /// 恢复时的那一句同样重要——骑行中用户看不见屏幕，不知道刚才那段已经接上了。
  void _collectGpsCues(RecordingSession session) {
    if (session.phase != RecordingPhase.recording) return;
    final bool weak = _isGpsWeak();
    if (weak == _wasGpsWeak) return;
    _wasGpsWeak = weak;
    _emitCues(<RideCue>[weak ? const GpsWeakCue() : const GpsRecoveredCue()]);
  }

  /// 把一批提示交给播报出口，并更新横幅要展示的那一条。
  void _emitCues(List<RideCue> cues) {
    if (cues.isEmpty) return;
    _cueSeq++;
    _lastCue = cues.last;
    unawaited(
      _cuePlayer.speak(
        cues,
        _distanceUnit,
        _session?.activityType ?? ActivityType.cycling,
      ),
    );
  }

  /// 提示播报用的单位。设置读不出来时按公里（与界面同一套兜底）。
  DistanceUnit get _distanceUnit =>
      ref.read(appSettingsProvider).value?.distanceUnit ??
      DistanceUnit.kilometer;

  void _onSensorReading(SensorKind kind, num value) {
    final RecordingSession? session = _session;
    if (session == null) return;
    switch (kind) {
      case SensorKind.heartRate:
        session.ingestHeartRate(value.round());
      case SensorKind.cadence:
        session.ingestCadence(value.toDouble());
      case SensorKind.power:
        session.ingestPower(value.round());
    }
  }

  void _onSensorConnection(SensorKind kind, bool connected) {
    if (connected) {
      _connected.add(kind);
    } else {
      _connected.remove(kind);
    }
    // 只有真的连上了才记住：用户点错设备（那个设备不提供标准服务）时
    // 不该被写进配对，否则下次开记录会一直去连一个连不上的设备。
    if (connected) unawaited(_rememberSensor(kind));
    _publish();
  }

  Future<void> _rememberSensor(SensorKind kind) async {
    final SensorMonitor? monitor = _monitors[kind];
    if (monitor == null) return;
    await _pairing.save(
      kind,
      PairedSensor(id: monitor.device.id, name: monitor.deviceName),
    );
  }

  /// 自动重连上次配对成功的传感器。见设计文档 10.5 与 6.1。
  ///
  /// 任何一步失败都直接跳过：传感器连不上不阻断开始记录（设计文档 6.1）。
  /// 按当前选中的运动类型裁剪：跑步没有踏频/功率概念，即使配过对也不连。
  Future<void> _autoConnectPairedSensors() async {
    for (final SensorKind kind in SensorKind.values) {
      if (!_sensorKindAllowed(kind)) continue;
      final PairedSensor? paired = await _pairing.load(kind);
      if (paired == null) continue;
      final BleDeviceHandle? device = await _blePlatform.deviceById(paired.id);
      if (device == null) continue;
      await connectSensor(kind, device);
    }
  }

  /// 这个传感器类型在当前选中的运动类型下是否可用。
  bool _sensorKindAllowed(SensorKind kind) {
    if (kind == SensorKind.heartRate) return true;
    if (kind == SensorKind.cadence) {
      return _selectedActivityType.supportsCadence;
    }
    return _selectedActivityType.supportsPower;
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
    final WorkoutRepository repo = ref.read(workoutRepositoryProvider);
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
    final RecordingSession? session = _session;
    final RecordingSnapshot? snap = session?.snapshot;
    state = RecordState(
      rideId: _rideId,
      phase: snap?.phase,
      foreground: _foreground,
      elapsedMs: snap?.elapsedMs ?? 0,
      distanceM: snap?.distanceM ?? 0,
      currentSpeedMps: snap?.currentSpeedMps ?? 0,
      hr: snap?.hr,
      cadence: snap?.cadence,
      power: snap?.power,
      hrConnected: _connected.contains(SensorKind.heartRate),
      cadenceConnected: _connected.contains(SensorKind.cadence),
      powerConnected: _connected.contains(SensorKind.power),
      gpsWeak: _isGpsWeak(),
      errorMessage: _error,
      // 直接透传引用，不拷贝：见 RecordState.liveTrack 的说明。
      liveTrack: session?.liveTrack ?? const <TrackPoint>[],
      liveTrackBreaks: session?.liveBreakIndexes ?? const <int>{},
      previewFix: _previewFix,
      currentAltitudeM: snap?.currentAltitudeM,
      elevationGainM: snap?.elevationGainM ?? 0,
      lastCue: _lastCue,
      cueSeq: _cueSeq,
      selectedActivityType: _selectedActivityType,
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
    for (final SensorMonitor monitor in _monitors.values) {
      monitor.dispose();
    }
  }
}
