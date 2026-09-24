import '../analysis/constants.dart';
import '../analysis/geo.dart';
import '../analysis/power.dart';
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
    required this.power,
    required this.pointCount,
  });

  final RecordingPhase phase;

  /// 有效记录时长（毫秒），暂停期间不增长。
  final int elapsedMs;

  final double distanceM;
  final double currentSpeedMps;
  final int? hr;
  final int? cadence;

  /// 瞬时功率（瓦）。接了功率计就是实测值，否则是按速度、坡度与体重估算出来的；
  /// 起步前（还没有定位点）为 null。
  final int? power;

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
  /// [resumedAtMs] 是崩溃恢复时「重新开始计时」的时刻。恢复的会话
  /// [startedAtMs] 可能是几小时前，若不给出该时刻，恢复后的第一次 [tick] 会把
  /// 开始到现在整段（含 App 没运行的空档）都累加进 [snapshot] 的时长。
  RecordingSession({
    required this.rideId,
    required this.startedAtMs,
    int initialElapsedMs = 0,
    double initialDistanceM = 0,
    TrackPoint? lastWritten,
    int? resumedAtMs,
    this.weightKg = kDefaultRiderWeightKg,
    List<TrackPoint> recentTrack = const <TrackPoint>[],
  })  : _elapsedMs = initialElapsedMs,
        _distanceM = initialDistanceM,
        _lastWritten = lastWritten,
        _lastTickMs = resumedAtMs ?? startedAtMs,
        _lastWrittenMs = lastWritten?.tMs ?? startedAtMs {
    // 崩溃恢复时把已落盘的那段轨迹接上，否则恢复后缩略图是空的，
    // 要等新点攒够才慢慢长出来。走同一条抽稀路径，不另写一套。
    for (final TrackPoint p in recentTrack) {
      _appendToLiveTrack(p);
    }
  }

  final int rideId;
  final int startedAtMs;

  /// 估算功率用的体重（公斤，含车重）。调用方从设置里取。
  final double weightKg;

  final WriteBuffer _buffer = WriteBuffer();

  RecordingPhase _phase = RecordingPhase.recording;
  int _elapsedMs;
  int _lastTickMs;
  int _lastWrittenMs;
  double _distanceM;
  double _currentSpeedMps = 0;
  int? _hr;
  double? _cadence;
  int? _power;
  int? _estimatedPower;
  LocationFix? _lastFix;
  TrackPoint? _lastWritten;
  int _pointCount = 0;

  /// 实时轨迹，供骑行界面的缩略图使用。见设计文档 9.4。
  ///
  /// 与落盘那批点是两回事：落盘按 5m / 2s 记，一张 120pt 高的缩略图铺不下几千
  /// 个点，也不需要那么密。这里按 [kLiveTrackMinDistanceM] /
  /// [kLiveTrackMaxIntervalMs] 抽稀，超过 [kLiveTrackMaxPoints] 时折半压缩。
  ///
  /// **永不原地改动已经交出去的列表**：压缩时换一个新的列表对象，界面才能用
  /// `identical` 判断「轨迹到底变没变」，不必每秒重算折线（见 `LiveRouteMap`）。
  List<TrackPoint> _liveTrack = const <TrackPoint>[];

  /// 拟合坡度用的近期样点：(定位时间, 累计距离, 高程)。只保留窗口内的。
  final List<({int tMs, double distanceM, double altitudeM})> _gradeSamples =
      <({int tMs, double distanceM, double altitudeM})>[];

  RecordingPhase get phase => _phase;

  /// 本次骑行到此刻为止的轨迹（已抽稀）。见设计文档 9.4。
  List<TrackPoint> get liveTrack => _liveTrack;

  /// 落盘与读数共用的功率：接了功率计用实测值，否则用估算值。
  int? get _effectivePower => _power ?? _estimatedPower;

  /// 是否已攒够 [kSensorBatchSize] 个点，可以提交一个事务。
  bool get shouldFlush => _buffer.isFull;

  RecordingSnapshot get snapshot => RecordingSnapshot(
        phase: _phase,
        elapsedMs: _elapsedMs,
        distanceM: _distanceM,
        currentSpeedMps: _currentSpeedMps,
        hr: _hr,
        cadence: _cadence?.round(),
        power: _effectivePower,
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
    _trackGradeSample(fix);
    _estimatedPower = _estimatePower();

    if (shouldWriteTrackPoint(lastWritten: _lastWritten, fix: fix)) {
      _write(_toPoint(fix));
    }
  }

  /// 把本次定位压进坡度窗口，并丢掉窗口外的老样点。
  void _trackGradeSample(LocationFix fix) {
    final double? altitude = fix.altitudeM;
    if (altitude == null) return;

    _gradeSamples.add((
      tMs: fix.tMs,
      distanceM: _distanceM,
      altitudeM: altitude,
    ));
    // 至少留一个样点：窗口里一个都不剩时，下一点就没有基线可拟合了。
    while (_gradeSamples.length > 1 &&
        fix.tMs - _gradeSamples.first.tMs > kGradeWindowMs) {
      _gradeSamples.removeAt(0);
    }
  }

  /// 没接功率计时，按当前速度、窗口拟合出的坡度与体重估算瞬时功率。
  ///
  /// 接了功率计时不调用：实测值更准，没有理由用估算值覆盖它。
  int? _estimatePower() {
    if (_power != null) return null;

    final double? grade = fitGrade(
      distanceM: <double>[for (final s in _gradeSamples) s.distanceM],
      altitudeM: <double>[for (final s in _gradeSamples) s.altitudeM],
    );
    // 样点还不够长（刚起步、或一直在慢慢挪）时按平路算：这时候坡度本来也谈不上。
    return estimatePowerW(
      speedMps: _currentSpeedMps,
      grade: grade ?? 0,
      weightKg: weightKg,
    ).round();
  }

  /// 接收一次心率采样（bpm）。
  void ingestHeartRate(int bpm) => _hr = bpm;

  /// 接收一次踏频采样（RPM）。
  void ingestCadence(double rpm) => _cadence = rpm;

  /// 接收一次功率采样（瓦）。
  void ingestPower(int watts) => _power = watts;

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
    _estimatedPower = 0;
  }

  /// 恢复采样。暂停期间的位移不属于骑行，因此断开与暂停前状态的关联。
  void resume(int nowMs) {
    if (_phase != RecordingPhase.paused) return;
    _phase = RecordingPhase.recording;
    _lastTickMs = nowMs;
    _lastFix = null;
    _lastWritten = null;
    _lastWrittenMs = nowMs;
    // 坡度窗口横跨暂停段会把两段不同位置的样点连成一条假坡，一起清掉。
    _gradeSamples.clear();
  }

  /// 结束记录，返回缓冲中剩余待落盘的点（未满一批不会自动提交）。
  ///
  /// 结束后的有效时长从 `snapshot.elapsedSeconds` 读取。
  List<TrackPoint> finish(int nowMs) {
    if (_phase != RecordingPhase.finished) {
      _advanceElapsed(nowMs);
      _phase = RecordingPhase.finished;
      _currentSpeedMps = 0;
      _estimatedPower = 0;
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
      _estimatedPower = 0;
    }
  }

  /// GPS 长时间没有更新时，仍按 2 秒节拍写纯传感器点，
  /// 使心率、踏频与功率曲线不断（这类点只有时间与传感器值，不上地图）。
  ///
  /// 估算功率不写进这类点：没有定位就没有速度，估出来的只能是 0，白白把平均
  /// 功率拉低。这里只写传感器的实测值。
  void _writeSensorOnlyPointIfNeeded(int nowMs) {
    if (_phase != RecordingPhase.recording) return;
    if (_hr == null && _cadence == null && _power == null) return;

    final LocationFix? last = _lastFix;
    final bool gpsLost = last == null || nowMs - last.tMs >= kGpsGapMs;
    if (!gpsLost || nowMs - _lastWrittenMs < kMaxWriteIntervalMs) return;

    _write(TrackPoint(
      rideId: rideId,
      tMs: nowMs,
      hr: _hr,
      cadence: _cadence?.round(),
      powerW: _power,
    ));
  }

  void _write(TrackPoint point) {
    _lastWritten = point;
    _lastWrittenMs = point.tMs;
    _pointCount++;
    _buffer.add(point);
    _appendToLiveTrack(point);
  }

  /// 往实时轨迹里追加一个点，按距离或时间抽稀。只有带定位的点才进得来：
  /// 缩略图上画的是轨迹，隧道里那些纯传感器点没有坐标，接进去会变成假直线。
  void _appendToLiveTrack(TrackPoint point) {
    if (!point.hasPosition) return;

    if (_liveTrack.isNotEmpty) {
      final TrackPoint last = _liveTrack.last;
      final bool farEnough =
          segmentDistanceMeters(last, point) >= kLiveTrackMinDistanceM;
      final bool lateEnough = point.tMs - last.tMs >= kLiveTrackMaxIntervalMs;
      if (!farEnough && !lateEnough) return;
    }

    _liveTrack = <TrackPoint>[..._liveTrack, point];
    if (_liveTrack.length > kLiveTrackMaxPoints) _compactLiveTrack();
  }

  /// 折半压缩：隔一个取一个，并保证最新点留在里面（否则轨迹末端会缺一截）。
  void _compactLiveTrack() {
    final List<TrackPoint> kept = <TrackPoint>[
      for (int i = 0; i < _liveTrack.length; i += 2) _liveTrack[i],
    ];
    if (!identical(kept.last, _liveTrack.last)) kept.add(_liveTrack.last);
    _liveTrack = kept;
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
        powerW: _effectivePower,
      );
}
