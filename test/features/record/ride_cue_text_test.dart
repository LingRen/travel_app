import 'package:cycling_app/data/settings_repository.dart';
import 'package:cycling_app/domain/models/activity_type.dart';
import 'package:cycling_app/domain/recording/ride_cue.dart';
import 'package:cycling_app/features/record/ride_cue_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('rideCueBannerText 距离里程碑', () {
    test('四种运动类型的动词正确', () {
      expect(
        rideCueBannerText(
          const DistanceCue(10),
          DistanceUnit.kilometer,
          ActivityType.cycling,
        ),
        '已骑行 10 公里',
      );
      expect(
        rideCueBannerText(
          const DistanceCue(10),
          DistanceUnit.kilometer,
          ActivityType.running,
        ),
        '已跑 10 公里',
      );
      expect(
        rideCueBannerText(
          const DistanceCue(10),
          DistanceUnit.kilometer,
          ActivityType.walking,
        ),
        '已走 10 公里',
      );
      expect(
        rideCueBannerText(
          const DistanceCue(10),
          DistanceUnit.kilometer,
          ActivityType.hiking,
        ),
        '已徒步 10 公里',
      );
    });
  });

  group('rideCueSpeechText 距离里程碑', () {
    test('四种运动类型的动词正确', () {
      expect(
        rideCueSpeechText(
          const DistanceCue(10),
          DistanceUnit.kilometer,
          ActivityType.cycling,
        ),
        '已骑行 10 公里',
      );
      expect(
        rideCueSpeechText(
          const DistanceCue(10),
          DistanceUnit.kilometer,
          ActivityType.running,
        ),
        '已跑 10 公里',
      );
      expect(
        rideCueSpeechText(
          const DistanceCue(10),
          DistanceUnit.kilometer,
          ActivityType.walking,
        ),
        '已走 10 公里',
      );
      expect(
        rideCueSpeechText(
          const DistanceCue(10),
          DistanceUnit.kilometer,
          ActivityType.hiking,
        ),
        '已徒步 10 公里',
      );
    });
  });

  group('每公里分段成绩', () {
    // 6 m/s = 21.6 km/h；3 m/s 折合配速 5'33"/km。
    const LapCue lap = LapCue(lapKm: 2, durationS: 167, avgSpeedMps: 6.0);
    const LapCue runLap = LapCue(lapKm: 2, durationS: 167, avgSpeedMps: 3.0);

    test('骑行报均速，与主读数同一口径', () {
      expect(
        rideCueBannerText(lap, DistanceUnit.kilometer, ActivityType.cycling),
        '第 2 公里 · 均速 21.6 km/h · 耗时 02:47',
      );
      expect(
        rideCueSpeechText(lap, DistanceUnit.kilometer, ActivityType.cycling),
        '第2公里，均速21.6公里每小时，耗时2分47秒',
      );
    });

    test('跑步/健走/徒步报配速，不再报 km/h', () {
      for (final ActivityType type in <ActivityType>[
        ActivityType.running,
        ActivityType.walking,
        ActivityType.hiking,
      ]) {
        expect(
          rideCueBannerText(runLap, DistanceUnit.kilometer, type),
          '第 2 公里 · 配速 5\'33" /km · 耗时 02:47',
          reason: '$type 的主读数是配速，横幅不能另报一套均速',
        );
      }
    });

    test('语音里的配速念成口语单位，不逐字符念引号', () {
      expect(
        rideCueSpeechText(runLap, DistanceUnit.kilometer, ActivityType.running),
        '第2公里，配速5分33秒每公里，耗时2分47秒',
      );
    });

    test('英里模式按每英里折算', () {
      expect(
        rideCueBannerText(runLap, DistanceUnit.mile, ActivityType.running),
        '第 2 公里 · 配速 8\'56" /mi · 耗时 02:47',
      );
      expect(
        rideCueSpeechText(runLap, DistanceUnit.mile, ActivityType.running),
        '第2公里，配速8分56秒每英里，耗时2分47秒',
      );
    });
  });

  group('信号提示文案', () {
    test('横幅用 GPS 缩写，语音念「卫星信号」避免逐字念字母', () {
      expect(
        rideCueBannerText(
          const GpsWeakCue(),
          DistanceUnit.kilometer,
          ActivityType.cycling,
        ),
        'GPS 信号弱',
      );
      expect(
        rideCueSpeechText(
          const GpsWeakCue(),
          DistanceUnit.kilometer,
          ActivityType.cycling,
        ),
        '卫星信号弱',
      );
    });

    test('定位恢复两种出口文案一致', () {
      expect(
        rideCueBannerText(
          const GpsRecoveredCue(),
          DistanceUnit.kilometer,
          ActivityType.running,
        ),
        '定位已恢复',
      );
      expect(
        rideCueSpeechText(
          const GpsRecoveredCue(),
          DistanceUnit.kilometer,
          ActivityType.running,
        ),
        '定位已恢复',
      );
    });
  });
}
