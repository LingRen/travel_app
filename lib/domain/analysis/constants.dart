/// 全部数值阈值集中在此处，便于调整与测试。
library;

/// 高程中值滤波窗口（点数，必须为奇数）。见设计文档 8.1。
const int kElevationFilterWindow = 5;

/// 单次上升超过该值（米）才计入爬升。见设计文档 8.1。
const double kElevationGainThresholdM = 1.0;

/// 速度滑动平均窗口（点数，必须为奇数）。见设计文档 8.1。
const int kSpeedFilterWindow = 5;

/// 静止判定速度阈值（m/s），等于 1 km/h。见设计文档 8.2。
const double kStationarySpeedMps = 1.0 / 3.6;

/// 轨迹点写入：与上一点的最小距离（米）。见设计文档 6.3 规则 1。
const double kMinWriteDistanceM = 5.0;

/// 轨迹点写入：距上次写入的最大时间间隔（毫秒）。见设计文档 6.3 规则 1。
const int kMaxWriteIntervalMs = 2000;

/// GPS 断点判定：相邻点时间间隔超过该值视为信号丢失。见设计文档 9.3。
const int kGpsGapMs = 10000;

/// 传感器批量提交点数。见设计文档 6.3 规则 2。
const int kSensorBatchSize = 10;

/// 速度着色的归一化上限（m/s），约 54 km/h。见设计文档 8.2。
const double kColorScaleMaxSpeedMps = 15.0;

/// 物理合理速度上限（m/s），约 108 km/h。
///
/// 这是补充阈值（设计文档 8.1 只列了爬升与最高速两个陷阱）：相邻两点的
/// 隐含速度超过该值时判定为 GPS 跳变，不计入距离、也不计入移动/静止时长。
const double kMaxPlausibleSpeedMps = 30.0;
