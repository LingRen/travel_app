/// 标准心率测量特征（0x2A37）的解析。
///
/// flags 字节的最低位表示心率值占用 1 字节还是 2 字节（小端）。
int? parseHeartRateMeasurement(List<int> data) {
  if (data.isEmpty) return null;
  final int flags = data[0];
  final bool isUint16 = (flags & 0x01) != 0;
  if (isUint16) {
    if (data.length < 3) return null;
    return data[1] | (data[2] << 8);
  }
  if (data.length < 2) return null;
  return data[1];
}

/// 骑行速度与踏频测量特征（0x2A2B）中的曲柄部分。
class CscMeasurement {
  const CscMeasurement({required this.crankRevolutions, required this.crankEventTime1024});

  /// 累计曲柄转数（16 位，会回绕）。
  final int crankRevolutions;

  /// 最后一次曲柄事件的时刻，单位 1/1024 秒（16 位，会回绕）。
  final int crankEventTime1024;
}

/// 解析 CSC 测量特征值。没有曲柄数据或长度不足时返回 null。
///
/// flags bit0 表示含车轮数据（6 字节），bit1 表示含曲柄数据（4 字节）。
CscMeasurement? parseCscMeasurement(List<int> data) {
  if (data.isEmpty) return null;
  final int flags = data[0];
  int offset = 1;
  if ((flags & 0x01) != 0) offset += 6;
  if ((flags & 0x02) == 0) return null;
  if (data.length < offset + 4) return null;
  final int revolutions = data[offset] | (data[offset + 1] << 8);
  final int eventTime = data[offset + 2] | (data[offset + 3] << 8);
  return CscMeasurement(crankRevolutions: revolutions, crankEventTime1024: eventTime);
}

/// 解析骑行功率测量特征值（0x2A63），返回瞬时功率（瓦）。长度不足时返回 null。
///
/// 前两字节是 flags（小端 uint16），紧随其后的 sint16 就是瞬时功率。flags 里
/// 的平衡、累积能量等位只影响后面的字段，这里不读功率以外的内容。
///
/// 标准允许瞬时功率为负（滑行时反拖），但负瓦数在码表上没有意义，夹到 0。
int? parseCyclingPowerMeasurement(List<int> data) {
  if (data.length < 4) return null;
  final int raw = data[2] | (data[3] << 8);
  final int signed = raw >= 0x8000 ? raw - 0x10000 : raw;
  return signed < 0 ? 0 : signed;
}

/// 由两次 CSC 测量计算踏频（RPM）。无法判定时返回 null。
///
/// 转数与事件时间都是 16 位会回绕的量，用按位与 0xFFFF 处理回绕。
double? cadenceRpm(CscMeasurement prev, CscMeasurement cur) {
  final int dRev = (cur.crankRevolutions - prev.crankRevolutions) & 0xFFFF;
  final int dTime = (cur.crankEventTime1024 - prev.crankEventTime1024) & 0xFFFF;
  if (dTime == 0) return null;
  final double seconds = dTime / 1024.0;
  if (seconds > 5) return null;
  final double rpm = dRev / seconds * 60.0;
  if (rpm > 250) return null;
  return rpm;
}
