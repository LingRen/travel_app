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
