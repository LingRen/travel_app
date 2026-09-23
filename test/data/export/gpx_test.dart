import 'package:cycling_app/data/export/gpx.dart';
import 'package:cycling_app/domain/analysis/constants.dart';
import 'package:cycling_app/domain/models/ride.dart';
import 'package:cycling_app/domain/models/ride_status.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

/// 按 local name 取元素，避免在测试里跟命名空间前缀纠缠。
Iterable<XmlElement> named(XmlNode node, String local) =>
    node.descendantElements.where((XmlElement e) => e.name.local == local);

/// 无标题时的轨迹名用的是**本地**日期（用户看到的日历日），所以期望值必须按
/// 本机时区现算：写死字符串会让 CI（UTC）与开发机（UTC+8）差一天。
String localDateName(int startedAtMs) {
  final DateTime start = DateTime.fromMillisecondsSinceEpoch(startedAtMs);
  String two(int value) => value.toString().padLeft(2, '0');
  return '骑行 ${start.year}-${two(start.month)}-${two(start.day)}';
}

const Ride _ride = Ride(
  id: 1,
  // 1758384000000 == 2025-09-20T16:00:00Z：UTC 下是 09-20，UTC+8 下是 09-21。
  // 轨迹名取本地日期，因此这里只断言 UTC 时刻，不断言当地日历日。
  startedAtMs: 1758384000000,
  endedAtMs: 1758387600000,
  status: RideStatus.finished,
);

TrackPoint pt(
  int tMs, {
  double? lat = 31.0,
  double? lon = 121.0,
  double? alt,
  int? hr,
  int? cadence,
}) =>
    TrackPoint(
      rideId: 1,
      tMs: tMs,
      lat: lat,
      lon: lon,
      altitudeM: alt,
      hr: hr,
      cadence: cadence,
    );

void main() {
  group('GPX 结构与命名空间', () {
    test('输出是合法 XML，根元素是 gpx 且 version 为 1.1', () {
      final XmlDocument doc =
          XmlDocument.parse(buildGpx(ride: _ride, points: <TrackPoint>[pt(0)]));

      expect(doc.rootElement.name.local, 'gpx');
      expect(doc.rootElement.getAttribute('version'), '1.1');
      expect(doc.rootElement.getAttribute('creator'), kGpxCreator);
    });

    test('声明了 GPX 1.1 与 gpxtpx 两个命名空间', () {
      final XmlDocument doc =
          XmlDocument.parse(buildGpx(ride: _ride, points: <TrackPoint>[pt(0)]));

      expect(doc.rootElement.getAttribute('xmlns'), kGpxNamespace);
      expect(doc.rootElement.getAttribute('xmlns:gpxtpx'), kGpxTpxNamespace);
    });

    test('trk 带 type 为 cycling', () {
      final XmlDocument doc =
          XmlDocument.parse(buildGpx(ride: _ride, points: <TrackPoint>[pt(0)]));

      expect(named(doc, 'type').single.innerText, 'cycling');
    });
  });

  group('GPX 轨迹点', () {
    test('只输出有坐标的点', () {
      final XmlDocument doc = XmlDocument.parse(buildGpx(
        ride: _ride,
        points: <TrackPoint>[
          pt(0),
          const TrackPoint(rideId: 1, tMs: 1000, hr: 140), // 无坐标
          pt(2000),
        ],
      ));

      expect(named(doc, 'trkpt').length, 2);
    });

    test('只有纬度没有经度时同样跳过', () {
      final XmlDocument doc = XmlDocument.parse(buildGpx(
        ride: _ride,
        points: <TrackPoint>[
          pt(0),
          const TrackPoint(rideId: 1, tMs: 1000, lat: 31.0), // 缺经度
          pt(2000),
        ],
      ));

      expect(named(doc, 'trkpt').length, 2);
    });

    test('经纬度写到小数点后 6 位', () {
      final XmlDocument doc = XmlDocument.parse(buildGpx(
        ride: _ride,
        points: <TrackPoint>[pt(0, lat: 31.230416, lon: 121.473701)],
      ));

      final XmlElement trkpt = named(doc, 'trkpt').single;
      expect(trkpt.getAttribute('lat'), '31.230416');
      expect(trkpt.getAttribute('lon'), '121.473701');
    });

    test('缺高程时不输出 ele 元素', () {
      final XmlDocument doc =
          XmlDocument.parse(buildGpx(ride: _ride, points: <TrackPoint>[pt(0)]));

      expect(named(doc, 'ele'), isEmpty);
    });

    test('有高程时输出 ele，保留两位小数', () {
      final XmlDocument doc = XmlDocument.parse(
        buildGpx(ride: _ride, points: <TrackPoint>[pt(0, alt: 12.3456)]),
      );

      expect(named(doc, 'ele').single.innerText, '12.35');
    });

    test('时间写成 UTC 的 ISO8601，带 Z 结尾', () {
      final XmlDocument doc = XmlDocument.parse(
        buildGpx(ride: _ride, points: <TrackPoint>[pt(1758384000000)]),
      );

      final String time = named(doc, 'time').last.innerText;
      expect(time, '2025-09-20T16:00:00.000Z');
      expect(time.endsWith('Z'), isTrue);
    });
  });

  group('GPX 传感器扩展', () {
    test('心率与踏频写进 gpxtpx 扩展', () {
      final XmlDocument doc = XmlDocument.parse(
        buildGpx(ride: _ride, points: <TrackPoint>[pt(0, hr: 142, cadence: 78)]),
      );

      expect(named(doc, 'TrackPointExtension').length, 1);
      expect(named(doc, 'hr').single.innerText, '142');
      expect(named(doc, 'cad').single.innerText, '78');
    });

    test('只有心率时不写 cad', () {
      final XmlDocument doc = XmlDocument.parse(
        buildGpx(ride: _ride, points: <TrackPoint>[pt(0, hr: 142)]),
      );

      expect(named(doc, 'hr').single.innerText, '142');
      expect(named(doc, 'cad'), isEmpty);
    });

    test('只有踏频时不写 hr', () {
      final XmlDocument doc = XmlDocument.parse(
        buildGpx(ride: _ride, points: <TrackPoint>[pt(0, cadence: 78)]),
      );

      expect(named(doc, 'cad').single.innerText, '78');
      expect(named(doc, 'hr'), isEmpty);
    });

    test('两者都没有时不输出 extensions 元素', () {
      final XmlDocument doc =
          XmlDocument.parse(buildGpx(ride: _ride, points: <TrackPoint>[pt(0)]));

      expect(named(doc, 'extensions'), isEmpty);
      expect(named(doc, 'TrackPointExtension'), isEmpty);
    });
  });

  group('GPX 断点分段', () {
    test('时间间隔超过 kGpsGapMs 时拆成两个 trkseg', () {
      final XmlDocument doc = XmlDocument.parse(buildGpx(
        ride: _ride,
        points: <TrackPoint>[
          pt(0),
          pt(1000),
          pt(1000 + kGpsGapMs + 1),
          pt(2000 + kGpsGapMs + 1),
        ],
      ));

      final List<XmlElement> segs = named(doc, 'trkseg').toList();
      expect(segs.length, 2);
      expect(named(segs[0], 'trkpt').length, 2);
      expect(named(segs[1], 'trkpt').length, 2);
    });

    test('恰好等于 kGpsGapMs 不拆段', () {
      final XmlDocument doc = XmlDocument.parse(buildGpx(
        ride: _ride,
        points: <TrackPoint>[pt(0), pt(kGpsGapMs)],
      ));

      expect(named(doc, 'trkseg').length, 1);
    });

    test('时间不前进时也拆段', () {
      final XmlDocument doc = XmlDocument.parse(buildGpx(
        ride: _ride,
        points: <TrackPoint>[pt(1000), pt(500)],
      ));

      expect(named(doc, 'trkseg').length, 2);
    });

    test('没有可用点时仍生成合法 GPX，只含一个空 trkseg', () {
      final XmlDocument doc = XmlDocument.parse(
        buildGpx(ride: _ride, points: const <TrackPoint>[]),
      );

      expect(doc.rootElement.name.local, 'gpx');
      expect(named(doc, 'trkseg').length, 1);
      expect(named(doc, 'trkpt'), isEmpty);
    });
  });

  group('GPX 名称', () {
    test('有标题时用标题', () {
      final XmlDocument doc = XmlDocument.parse(buildGpx(
        ride: const Ride(
          id: 1,
          startedAtMs: 1758384000000,
          status: RideStatus.finished,
          title: '周末环湖',
        ),
        points: <TrackPoint>[pt(0)],
      ));

      expect(named(doc, 'name').first.innerText, '周末环湖');
    });

    test('没有标题时用开始日期', () {
      final XmlDocument doc =
          XmlDocument.parse(buildGpx(ride: _ride, points: <TrackPoint>[pt(0)]));

      expect(named(doc, 'name').first.innerText, localDateName(_ride.startedAtMs));
    });

    test('标题只有空白时视为没有标题，回退到开始日期', () {
      const Ride blankTitle = Ride(
        id: 1,
        startedAtMs: 1758384000000,
        status: RideStatus.finished,
        title: '   ',
      );
      final XmlDocument doc = XmlDocument.parse(
        buildGpx(ride: blankTitle, points: <TrackPoint>[pt(0)]),
      );

      expect(named(doc, 'name').first.innerText, localDateName(1758384000000));
    });

    // 上两条的期望值是按本机时区现算的，因此必须再钉一条与时区无关的断言，
    // 否则实现里换成别的日期来源（比如用 endedAtMs）也照样会绿。
    test('回退的日期跟着 startedAtMs 走', () {
      const Ride later = Ride(
        id: 1,
        startedAtMs: 1758384000000 + 24 * 3600 * 1000,
        status: RideStatus.finished,
      );

      final String name =
          named(XmlDocument.parse(buildGpx(ride: later, points: <TrackPoint>[pt(0)])), 'name')
              .first
              .innerText;

      expect(name, localDateName(later.startedAtMs));
      expect(name, isNot(localDateName(_ride.startedAtMs)));
    });

    test('标题里的特殊字符被正确转义', () {
      final String gpx = buildGpx(
        ride: const Ride(
          id: 1,
          startedAtMs: 1758384000000,
          status: RideStatus.finished,
          title: 'A & B <c>',
        ),
        points: <TrackPoint>[pt(0)],
      );
      // 不抛异常即说明转义正确；再确认原文没有裸露的裸 & 或 <。
      final XmlDocument doc = XmlDocument.parse(gpx);
      expect(named(doc, 'name').first.innerText, 'A & B <c>');
      expect(gpx.contains('A & B <c>'), isFalse);
    });
  });
}
