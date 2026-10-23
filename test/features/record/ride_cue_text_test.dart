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
}
