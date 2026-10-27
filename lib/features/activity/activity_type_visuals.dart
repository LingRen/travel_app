import 'package:flutter/material.dart';

import '../../domain/models/activity_type.dart';

/// 运动类型的图标。图标只承担识别，不承诺该类型没有的能力。
IconData activityTypeIcon(ActivityType type) => switch (type) {
  ActivityType.cycling => Icons.directions_bike,
  ActivityType.running => Icons.directions_run,
  ActivityType.walking => Icons.directions_walk,
  ActivityType.hiking => Icons.hiking,
  ActivityType.mountaineering => Icons.terrain,
};

/// 类型印章里的单字。纸本界面用印章代替彩色图标块。
String activityTypeSeal(ActivityType type) => switch (type) {
  ActivityType.cycling => '骑',
  ActivityType.running => '跑',
  ActivityType.walking => '走',
  ActivityType.hiking => '徒',
  ActivityType.mountaineering => '登',
};

/// 类型说明。只写本机真实能记录的能力，不写步频、步数这类没有采集的指标。
String activityTypeDescription(ActivityType type) => switch (type) {
  ActivityType.cycling => '速度 · 踏频 · 功率',
  ActivityType.running || ActivityType.walking => '配速 · 心率',
  ActivityType.hiking => '配速 · 海拔 · 心率',
  ActivityType.mountaineering => '爬升 · 海拔 · 心率',
};
