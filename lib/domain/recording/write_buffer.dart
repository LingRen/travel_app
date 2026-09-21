import '../analysis/constants.dart';
import '../models/track_point.dart';

/// 设计文档 6.3 规则 2：攒够 [capacity] 个点提交一个事务。
///
/// 本类只管攒与取，不做任何 IO，因此可以脱离 Flutter 与数据库单独测试。
class WriteBuffer {
  WriteBuffer({this.capacity = kSensorBatchSize});

  /// 触发提交的点数阈值。
  final int capacity;

  final List<TrackPoint> _pending = <TrackPoint>[];

  int get length => _pending.length;

  bool get isEmpty => _pending.isEmpty;

  /// 是否已达提交阈值。调用方据此决定何时 [drain]。
  bool get isFull => _pending.length >= capacity;

  void add(TrackPoint point) {
    _pending.add(point);
  }

  /// 取出并清空全部待写点。返回的列表不可修改。
  List<TrackPoint> drain() {
    if (_pending.isEmpty) return const <TrackPoint>[];
    final List<TrackPoint> batch = List<TrackPoint>.unmodifiable(_pending);
    _pending.clear();
    return batch;
  }
}
