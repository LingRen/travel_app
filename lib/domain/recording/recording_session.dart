import '../analysis/constants.dart';
import '../analysis/geo.dart';
import '../models/location_fix.dart';
import '../models/track_point.dart';
import 'track_point_filter.dart';
import 'write_buffer.dart';

/// 记录会话的阶段。
///
/// 设计文档 6.1 中的 `idle` 与 `preparing`（申请权限、连接传感器）由控制器与
/// UI 承担，本对象只在真正开始记录时创建，因此内部阶段只有三个。
enum RecordingPhase { recording, paused, finished }

/// 实时快照，供 UI 每秒渲染一次。
class RecordingSnapshot {
  const RecordingSnapshot({
    required this.phase,
    required this.elapsedMs,
    required this.distanceM,
    required this.currentSpeedMps,
    required this.hr,
    required this.cadence,
    required this.pointCount,
  });

  final RecordingPhase phase;

  /// 有效记录时长（毫秒），暂停期间不增长。
  final int elapsedMs;

  final double distanceM;
  final double currentSpeedMps;
  final int? hr;
  final int? cadence;

  /// 已写入的点数（含仍在缓冲中、尚未提交事务的点）。
  final int pointCount;

  int get elapsedSeconds => elapsedMs ~/ 1000;
}

/// 记录引擎的状态机与实时指标。
///
/// 所有时间都由外部注入（`nowMs`），因此不依赖真实时钟，测试完全确定。
/// 落盘由调用方负责：每次 [ingestFix] / [tick] 之后检查 [shouldFlush]，
/// 需要时调用 [takePendingPoints] 取走一批点写库；结束前必须调用 [finish]
/// 取走缓冲中剩余的点。
class RecordingSession {
  RecordingSession({required this.rideId, required this.startedAtMs})
      : _lastTickMs = startedAtMs,
        _lastWrittenMs = startedAtMs;

  final int rideId;
  final int startedAtMs;

  final WriteBuffer _buffer = WriteBuffer();

  RecordingPhase _phase = RecordingPhase.recording;
  int _elapsedMs = 0;
  int _lastTickMs;
  int _lastWrittenMs;
  double _distanceM = 0;
  double _currentSpeedMps = 0;
  int? _hr;
  double? _cadence;
  LocationFix? _lastFix;
  TrackPoint? _lastWritten;
  int _pointCount = 0;

  RecordingPhase get phase => _phase;

  /// 是否已攒够 [kSensorBatchSize] 个点，可以提交一个事务。
  bool get shouldFlush => _buffer.isFull;

  RecordingSnapshot get snapshot => RecordingSnapshot(
        phase: _phase,
        elapsedMs: _elapsedMs,
        distanceM: _distanceM,
        currentSpeedMps: _currentSpeedMps,
        hr: _hr,
        cadence: _cadence?.round(),
        pointCount: _pointCount,
      );

  /// 取出并清空待落盘的点。返回非空列表时调用方应写库。
  List<TrackPoint> takePendingPoints() => _buffer.drain();

  /// 接收一次定位结果。暂停或已结束时直接忽略。
  void ingestFix(LocationFix fix) {
    if (_phase != RecordingPhase.recording || !fix.hasPosition) return;

    final LocationFix? prev = _lastFix;
    double segmentM = 0;
    if (prev != null && prev.hasPosition) {
      segmentM = segmentDistanceMeters(_toPoint(prev), _toPoint(fix));
      _distanceM += segmentM;
    }

    final double? reported = fix.speedMps;
    if (reported != null && reported >= 0 && reported <= kMaxPlausibleSpeedMps) {
      _currentSpeedMps = reported;
    } else {
      // GPS 没给速度，或给的数值不合理，就用位移除以时间推算。
      final int dtMs = prev == null ? 0 : fix.tMs - prev.tMs;
      _currentSpeedMps = dtMs > 0 ? segmentM / (dtMs / 1000.0) : 0;
    }

    _lastFix = fix;

    if (shouldWriteTrackPoint(lastWritten: _lastWritten, fix: fix)) {
      _write(_toPoint(fix));
    }
  }

  /// 接收一次心率采样（bpm）。
  void ingestHeartRate(int bpm) => _hr = bpm;

  /// 接收一次踏频采样（RPM）。
  void ingestCadence(double rpm) => _cadence = rpm;

  /// 由控制器以 1Hz 调用，推进时长、衰减速度、补写纯传感器点。
  void tick(int nowMs) {
    if (_phase == RecordingPhase.finished) return;
    _advanceElapsed(nowMs);
    _decaySpeed(nowMs);
    _writeSensorOnlyPointIfNeeded(nowMs);
  }

  /// 暂停采样。暂停期间不产生轨迹点，时长也不增长。
  void pause(int nowMs) {
    if (_phase != RecordingPhase.recording) return;
    _advanceElapsed(nowMs);
    _phase = RecordingPhase.paused;
    _currentSpeedMps = 0;
  }

  /// 恢复采样。暂停期间的位移不属于骑行，因此断开与暂停前状态的关联。
  void resume(int nowMs) {
    if (_phase != RecordingPhase.paused) return;
    _phase = RecordingPhase.recording;
    _lastTickMs = nowMs;
    _lastFix = null;
    _lastWritten = null;
    _lastWrittenMs = nowMs;
  }

  /// 结束记录，返回缓冲中剩余待落盘的点（未满一批不会自动提交）。
  ///
  /// 结束后的有效时长从 `snapshot.elapsedSeconds` 读取。
  List<TrackPoint> finish(int nowMs) {
    if (_phase != RecordingPhase.finished) {
      _advanceElapsed(nowMs);
      _phase = RecordingPhase.finished;
      _currentSpeedMps = 0;
    }
    return _buffer.drain();
  }

  void _advanceElapsed(int nowMs) {
    final int dt = nowMs - _lastTickMs;
    if (dt > 0 && _phase == RecordingPhase.recording) {
      _elapsedMs += dt;
    }
    _lastTickMs = nowMs;
  }

  void _decaySpeed(int nowMs) {
    final LocationFix? last = _lastFix;
    if (_phase == RecordingPhase.recording &&
        (last == null || nowMs - last.tMs > kGpsGapMs)) {
      _currentSpeedMps = 0;
    }
  }

  /// GPS 长时间没有更新时，仍按 2 秒节拍写纯传感器点，
  /// 使心率与踏频曲线不断（这类点只有时间与传感器值，不上地图）。
  void _writeSensorOnlyPointIfNeeded(int nowMs) {
    if (_phase != RecordingPhase.recording) return;
    if (_hr == null && _cadence == null) return;

    final LocationFix? last = _lastFix;
    final bool gpsLost = last == null || nowMs - last.tMs >= kGpsGapMs;
    if (!gpsLost || nowMs - _lastWrittenMs < kMaxWriteIntervalMs) return;

    _write(TrackPoint(
      rideId: rideId,
      tMs: nowMs,
      hr: _hr,
      cadence: _cadence?.round(),
    ));
  }

  void _write(TrackPoint point) {
    _lastWritten = point;
    _lastWrittenMs = point.tMs;
    _pointCount++;
    _buffer.add(point);
  }

  TrackPoint _toPoint(LocationFix fix) => TrackPoint(
        rideId: rideId,
        tMs: fix.tMs,
        lat: fix.lat,
        lon: fix.lon,
        altitudeM: fix.altitudeM,
        speedMps: fix.speedMps,
        accuracyM: fix.accuracyM,
        hr: _hr,
        cadence: _cadence?.round(),
      );
}
