import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cycling_app/data/db/database.dart';
import 'package:cycling_app/data/db/ride_dao.dart';
import 'package:cycling_app/data/db/track_point_dao.dart';
import 'package:cycling_app/data/export/backup.dart';
import 'package:cycling_app/domain/models/ride.dart';
import 'package:cycling_app/domain/models/ride_status.dart';
import 'package:cycling_app/domain/models/ride_summary.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const Ride _finished = Ride(
  id: 1,
  startedAtMs: 1000,
  endedAtMs: 3601000,
  status: RideStatus.finished,
  title: '周末环湖',
  hrDeviceName: 'FIT 3',
  summary: RideSummary(
    distanceM: 25000,
    durationS: 3600,
    movingS: 3400,
    avgSpeedMps: 6.94,
    movingAvgSpeedMps: 7.35,
    maxSpeedMps: 12.5,
    elevationGainM: 180,
    avgHr: 142,
    maxHr: 176,
    avgCadence: 78,
    calories: 900,
    pointCount: 3,
  ),
);

const List<TrackPoint> _points = <TrackPoint>[
  TrackPoint(id: 1, rideId: 1, tMs: 1000, lat: 31.0, lon: 121.0, altitudeM: 10, speedMps: 5, hr: 140, cadence: 80),
  TrackPoint(id: 2, rideId: 1, tMs: 2000, lat: 31.0001, lon: 121.0, hr: 145),
  TrackPoint(id: 3, rideId: 1, tMs: 3000), // GPS 丢失，只有传感器
];

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openAppDatabase(path: inMemoryDatabasePath);
  });

  tearDown(() => db.close());

  group('buildBackupArchive', () {
    test('归档里恰好有 manifest / rides / track_points 三个条目', () {
      final Uint8List bytes = buildBackupArchive(
        rides: const <Ride>[_finished],
        points: _points,
        exportedAtMs: 1758384000000,
      );

      final Archive archive = ZipDecoder().decodeBytes(bytes);
      expect(
        archive.files.map((ArchiveFile f) => f.name).toSet(),
        <String>{'manifest.json', 'rides.json', 'track_points.jsonl'},
      );
    });

    test('manifest 写出 schema 版本、导出时间与条数', () {
      final Uint8List bytes = buildBackupArchive(
        rides: const <Ride>[_finished],
        points: _points,
        exportedAtMs: 1758384000000,
      );

      final Archive archive = ZipDecoder().decodeBytes(bytes);
      final Map<String, Object?> manifest = jsonDecode(
        utf8.decode(archive.findFile('manifest.json')!.content),
      ) as Map<String, Object?>;

      expect(manifest['schema_version'], kBackupSchemaVersion);
      expect(manifest['exported_at'], 1758384000000);
      expect(manifest['ride_count'], 1);
      expect(manifest['point_count'], 3);
    });

    test('track_points.jsonl 每行一个 JSON 对象', () {
      final Uint8List bytes = buildBackupArchive(
        rides: const <Ride>[_finished],
        points: _points,
        exportedAtMs: 0,
      );

      final Archive archive = ZipDecoder().decodeBytes(bytes);
      final String text = utf8.decode(archive.findFile('track_points.jsonl')!.content);
      final List<String> lines = text.split('\n').where((String l) => l.isNotEmpty).toList();

      expect(lines.length, 3);
      for (final String line in lines) {
        expect(jsonDecode(line), isA<Map<String, Object?>>());
      }
    });
  });

  group('parseBackupArchive', () {
    test('打包再解包，骑行与轨迹点字段完全一致', () {
      final Uint8List bytes = buildBackupArchive(
        rides: const <Ride>[_finished],
        points: _points,
        exportedAtMs: 1758384000000,
      );

      final BackupPayload payload = parseBackupArchive(bytes);

      final Ride ride = payload.rides.single;
      expect(ride.id, 1);
      expect(ride.title, '周末环湖');
      expect(ride.hrDeviceName, 'FIT 3');
      expect(ride.summary!.distanceM, 25000);
      expect(ride.summary!.calories, 900);

      expect(payload.points.length, 3);
      expect(payload.points[0].lat, 31.0);
      expect(payload.points[0].hr, 140);
      expect(payload.points[2].hasPosition, isFalse);
    });

    test('manifest 内容被解析出来', () {
      final BackupPayload payload = parseBackupArchive(buildBackupArchive(
        rides: const <Ride>[_finished],
        points: _points,
        exportedAtMs: 1758384000000,
      ));

      expect(payload.manifest.schemaVersion, kBackupSchemaVersion);
      expect(payload.manifest.rideCount, 1);
      expect(payload.manifest.pointCount, 3);
      expect(payload.manifest.exportedAtMs, 1758384000000);
    });

    test('schema 版本更高时明确拒绝', () {
      final Uint8List bytes = buildBackupArchive(
        rides: const <Ride>[],
        points: const <TrackPoint>[],
        exportedAtMs: 0,
        schemaVersion: kBackupSchemaVersion + 1,
      );

      expect(
        () => parseBackupArchive(bytes),
        throwsA(isA<BackupVersionException>()),
      );
    });

    test('schema 版本更低时同样拒绝（只接受完全相等）', () {
      // 计划书只写了「更高时拒绝」。但 `!=` 改成 `>` 后，更高版本照样被拒、
      // 这条用例照样绿——所以必须补一条更低版本的：只有 `!=` 才会拒它。
      final Uint8List bytes = buildBackupArchive(
        rides: const <Ride>[_finished],
        points: _points,
        exportedAtMs: 0,
        schemaVersion: kBackupSchemaVersion - 1,
      );

      expect(
        () => parseBackupArchive(bytes),
        throwsA(isA<BackupVersionException>()),
      );
    });

    test('拒绝时异常里带上实际版本与期望版本', () {
      final Uint8List bytes = buildBackupArchive(
        rides: const <Ride>[],
        points: const <TrackPoint>[],
        exportedAtMs: 0,
        schemaVersion: 99,
      );

      try {
        parseBackupArchive(bytes);
        fail('应当抛 BackupVersionException');
      } on BackupVersionException catch (e) {
        expect(e.found, 99);
        expect(e.expected, kBackupSchemaVersion);
        expect(e.toString(), contains('99'));
      }
    });

    test('归档里没有 manifest.json 时抛格式异常', () {
      final Archive archive = Archive()
        ..add(ArchiveFile.string('rides.json', '[]'));
      final Uint8List bytes = Uint8List.fromList(ZipEncoder().encode(archive));

      expect(
        () => parseBackupArchive(bytes),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('空数据也能打包与解包', () {
      final BackupPayload payload = parseBackupArchive(buildBackupArchive(
        rides: const <Ride>[],
        points: const <TrackPoint>[],
        exportedAtMs: 0,
      ));

      expect(payload.rides, isEmpty);
      expect(payload.points, isEmpty);
    });
  });

  group('applyBackup', () {
    test('replaceExisting 为真时先清空再写入', () async {
      // 先塞一条「旧数据」，恢复后应当消失。
      await RideDao(db).insert(const Ride(
        id: null,
        startedAtMs: 999,
        status: RideStatus.finished,
        title: '旧数据',
      ));

      await applyBackup(
        parseBackupArchive(buildBackupArchive(
          rides: const <Ride>[_finished],
          points: _points,
          exportedAtMs: 0,
        )),
        db: db,
      );

      final List<Ride> all = await RideDao(db).listFinished();
      expect(all.length, 1);
      expect(all.single.title, '周末环湖');
      expect(all.single.id, 1);
    });

    test('replaceExisting 为假时保留已有数据', () async {
      // 显式给 id：备份里的骑行 id 是 1，若让旧数据自增拿到 1 会先撞主键，
      // 那测的就不是「保留已有数据」而是「主键冲突」了。
      await RideDao(db).insertWithId(const Ride(
        id: 100,
        startedAtMs: 999,
        status: RideStatus.finished,
        title: '旧数据',
      ));

      await applyBackup(
        parseBackupArchive(buildBackupArchive(
          rides: const <Ride>[_finished],
          points: _points,
          exportedAtMs: 0,
        )),
        db: db,
        replaceExisting: false,
      );

      expect((await RideDao(db).listFinished()).length, 2);
    });

    test('恢复后轨迹点挂回原来的 ride id', () async {
      await applyBackup(
        parseBackupArchive(buildBackupArchive(
          rides: const <Ride>[_finished],
          points: _points,
          exportedAtMs: 0,
        )),
        db: db,
      );

      final List<TrackPoint> points = await TrackPointDao(db).listByRide(1);
      expect(points.length, 3);
      expect(points[0].tMs, 1000);
      expect(points[2].hasPosition, isFalse);
    });

    test('恢复后再导出，内容与首次导出一致（幂等）', () async {
      final Uint8List first = buildBackupArchive(
        rides: const <Ride>[_finished],
        points: _points,
        exportedAtMs: 0,
      );
      await applyBackup(parseBackupArchive(first), db: db);

      final Uint8List second = buildBackupArchive(
        rides: await RideDao(db).listFinished(),
        points: await TrackPointDao(db).listAll(),
        exportedAtMs: 0,
      );

      final BackupPayload a = parseBackupArchive(first);
      final BackupPayload b = parseBackupArchive(second);
      expect(b.rides.single.toDbMap(), a.rides.single.toDbMap());
      expect(
        b.points.map((TrackPoint p) => p.toDbMap()).toList(),
        a.points.map((TrackPoint p) => p.toDbMap()).toList(),
      );
    });

    test('恢复失败时不留半份数据（事务）', () async {
      // 造一个 ride 指向不存在的 ride_id 的点：外键会拒绝，整个事务应回滚。
      // 旧数据用 id=100 而不是自增的 1，否则备份里 id=1 的骑行会先撞主键，
      // 失败原因就变成主键冲突、根本走不到外键这一层。
      await RideDao(db).insertWithId(const Ride(
        id: 100,
        startedAtMs: 999,
        status: RideStatus.finished,
        title: '旧数据',
      ));

      final BackupPayload broken = BackupPayload(
        manifest: const BackupManifest(
          schemaVersion: kBackupSchemaVersion,
          exportedAtMs: 0,
          rideCount: 1,
          pointCount: 1,
        ),
        rides: const <Ride>[_finished],
        points: const <TrackPoint>[
          TrackPoint(rideId: 424242, tMs: 1000, lat: 1.0, lon: 1.0),
        ],
      );

      await expectLater(
        applyBackup(broken, db: db, replaceExisting: false),
        throwsA(
          // 必须是外键拒绝（787），不能是别的原因顺带抛错把这条用例混绿。
          isA<DatabaseException>().having(
            (DatabaseException e) => e.toString(),
            'message',
            contains('FOREIGN KEY'),
          ),
        ),
      );

      // 旧数据还在，说明事务回滚了。
      final List<Ride> all = await RideDao(db).listFinished();
      expect(all.single.title, '旧数据');
    });
  });
}
