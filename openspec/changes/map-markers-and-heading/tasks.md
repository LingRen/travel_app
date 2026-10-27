# Tasks

## 1. 朝向计算

- [x] 1.1 新增 `lib/domain/analysis/heading.dart`：角度归一、最短弧差、朝向更新判定（采用 / 冻结 / 保持）
- [x] 1.2 为新函数补单测，覆盖 ±170°、180°、0/360 与三档速度

## 2. 数据流

- [x] 2.1 `LocationFix` 增加内存字段 `headingDeg`
- [x] 2.2 `LocationService` 从 `Position.heading` 填充该字段
- [x] 2.3 `RecordingSession` 维护当前朝向，并按 30 m / 30 s 判定起点
- [x] 2.4 `RecordState` 暴露 `headingDeg` 与 `startPoint`
- [x] 2.5 补会话单测：首个达标点落起点、30 秒兜底、无坐标不落位、低速冻结朝向

## 3. 记录页地图

- [x] 3.1 `LiveRouteMap` 增加起点参数，按「粗略定位 / 起点 + 箭头」三态画标记
- [x] 3.2 箭头组件：22 dp 实心三角、墨色填充 + 纸色描边、最短弧 200 ms 补间
- [x] 3.3 `handlebar_view` 把起点与朝向传进地图

## 4. 详情页地图

- [x] 4.1 `RouteMap` 从首段首点与末段末点画「起」「终」标记
- [x] 4.2 断口端点改为警告色空心环，去掉实心填充

## 5. 验证

- [x] 5.1 `flutter analyze`、`flutter test`、`dart format --set-exit-if-changed` 全绿
- [ ] 5.2 K40 真机目视：起步起点落位、静止箭头不抖、掉头走最短弧、详情页起终点与断口可区分
