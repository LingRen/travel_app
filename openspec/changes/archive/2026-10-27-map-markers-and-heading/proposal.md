# Proposal

## Why

记录页地图上只有一颗没有方向的圆点，用户看不出自己正朝哪边走，也看不出这一程是从哪里出发的；详情页的轨迹同样没有起终点，一条线画完却不知道哪头是开头。两者都让「我为什么走了这一程」这个最直接的问题失去视觉答案。

## What Changes

- 记录页的当前位置从圆点改为随朝向旋转的箭头；地图本身保持北向上，不旋转。
- 记录页在第一个通过精度门槛的定位点落一个起点标记，之后不再移动。
- 详情页地图标出起点与终点，断口端点改为空心小圆以示区别。
- 朝向只用于实时显示：读 `Position.heading`，不落库、不进 GPX、不参与统计。
- 粗略定位（按下开始时的一次单次定位）只用于点亮地图，不作为起点。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `recording`：新增实时地图的起点与朝向要求，明确朝向的可信判定与冻结口径。
- `activity-review`：详情地图新增起终点标记，断口端点的画法从实心改为空心。

## Impact

- `lib/features/record/live_route_map.dart`：当前位置标记、起点标记、朝向旋转。
- `lib/features/record/handlebar_view.dart`：把起点与朝向传给地图。
- `lib/features/record/record_controller.dart`：`RecordState` 暴露起点与朝向。
- `lib/domain/recording/recording_session.dart`：起点判定与朝向可信判定。
- `lib/domain/models/location_fix.dart`：增加仅供实时显示的内存字段 `headingDeg`。
- `lib/data/location/location_service.dart`：读取 `Position.heading`。
- `lib/domain/analysis/heading.dart`：新增朝向纯函数（最短弧、可信判定）。
- `lib/features/detail/route_map.dart`：起终点标记与断口端点的画法。
- 数据库、导出与统计不受影响。
