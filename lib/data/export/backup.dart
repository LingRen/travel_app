import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/models/ride.dart';
import '../../domain/models/track_point.dart';
import '../db/ride_dao.dart';
import '../db/track_point_dao.dart';

/// 备份文件的 schema 版本。见设计文档 12。
const int kBackupSchemaVersion = 1;

const String _manifestName = 'manifest.json';
const String _ridesName = 'rides.json';
const String _pointsName = 'track_points.jsonl';

/// 归档里的 manifest.json。
class BackupManifest {
  const BackupManifest({
    required this.schemaVersion,
    required this.exportedAtMs,
    required this.rideCount,
    required this.pointCount,
  });

  final int schemaVersion;
  final int exportedAtMs;
  final int rideCount;
  final int pointCount;

  Map<String, Object?> toJson() => <String, Object?>{
        'schema_version': schemaVersion,
        'exported_at': exportedAtMs,
        'ride_count': rideCount,
        'point_count': pointCount,
      };

  static BackupManifest fromJson(Map<String, Object?> json) => BackupManifest(
        schemaVersion: (json['schema_version'] as num?)?.toInt() ?? 0,
        exportedAtMs: (json['exported_at'] as num?)?.toInt() ?? 0,
        rideCount: (json['ride_count'] as num?)?.toInt() ?? 0,
        pointCount: (json['point_count'] as num?)?.toInt() ?? 0,
      );
}

/// 一份解开的备份。
class BackupPayload {
  const BackupPayload({
    required this.manifest,
    required this.rides,
    required this.points,
  });

  final BackupManifest manifest;
  final List<Ride> rides;
  final List<TrackPoint> points;
}

/// 归档结构不对（缺条目、JSON 坏了）。
class BackupFormatException implements Exception {
  BackupFormatException(this.message);

  final String message;

  @override
  String toString() => '备份文件格式不正确：$message';
}

/// 归档的 schema 版本不被支持。
class BackupVersionException implements Exception {
  BackupVersionException({required this.found, required this.expected});

  final int found;
  final int expected;

  @override
  String toString() =>
      '备份文件的 schema 版本是 $found，本应用只支持 $expected。'
      '请升级 App 后再恢复，避免数据被静默损坏。';
}

/// 打包成 ZIP。见设计文档 12。
///
/// [schemaVersion] 只给测试用来造出「版本不匹配」的归档，正常调用不要传。
Uint8List buildBackupArchive({
  required List<Ride> rides,
  required List<TrackPoint> points,
  required int exportedAtMs,
  int schemaVersion = kBackupSchemaVersion,
}) {
  final BackupManifest manifest = BackupManifest(
    schemaVersion: schemaVersion,
    exportedAtMs: exportedAtMs,
    rideCount: rides.length,
    pointCount: points.length,
  );

  final Archive archive = Archive()
    ..add(ArchiveFile.string(_manifestName, jsonEncode(manifest.toJson())))
    ..add(ArchiveFile.string(
      _ridesName,
      jsonEncode(<Map<String, Object?>>[
        for (final Ride r in rides) r.toDbMap(),
      ]),
    ))
    ..add(ArchiveFile.string(
      _pointsName,
      points.map((TrackPoint p) => jsonEncode(p.toDbMap())).join('\n'),
    ));

  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// 解开归档并校验版本。
///
/// 版本号必须**完全相等**：更高版本说明归档来自更新的 App，旧版代码不认识
/// 新增字段，写下去会静默丢数据，因此明确拒绝（设计文档 12）。
/// 目前只有 v1，不存在「更旧需要迁移」的情况——等真的出现 v2 再补迁移分支。
BackupPayload parseBackupArchive(Uint8List bytes) {
  final Archive archive = ZipDecoder().decodeBytes(bytes);

  final ArchiveFile? manifestFile = archive.findFile(_manifestName);
  if (manifestFile == null) {
    throw BackupFormatException('归档里没有 $_manifestName');
  }

  final BackupManifest manifest;
  try {
    manifest = BackupManifest.fromJson(
      jsonDecode(utf8.decode(manifestFile.content)) as Map<String, Object?>,
    );
  } catch (error) {
    throw BackupFormatException('$_manifestName 无法解析：$error');
  }

  if (manifest.schemaVersion != kBackupSchemaVersion) {
    throw BackupVersionException(
      found: manifest.schemaVersion,
      expected: kBackupSchemaVersion,
    );
  }

  return BackupPayload(
    manifest: manifest,
    rides: _decodeRides(archive),
    points: _decodePoints(archive),
  );
}

List<Ride> _decodeRides(Archive archive) {
  final ArchiveFile? file = archive.findFile(_ridesName);
  if (file == null) throw BackupFormatException('归档里没有 $_ridesName');
  try {
    final List<Object?> raw = jsonDecode(utf8.decode(file.content)) as List<Object?>;
    return <Ride>[
      for (final Object? row in raw)
        Ride.fromDbMap(row as Map<String, Object?>),
    ];
  } catch (error) {
    throw BackupFormatException('$_ridesName 无法解析：$error');
  }
}

List<TrackPoint> _decodePoints(Archive archive) {
  final ArchiveFile? file = archive.findFile(_pointsName);
  if (file == null) throw BackupFormatException('归档里没有 $_pointsName');
  try {
    final String text = utf8.decode(file.content);
    return <TrackPoint>[
      for (final String line in text.split('\n'))
        if (line.trim().isNotEmpty)
          TrackPoint.fromDbMap(jsonDecode(line) as Map<String, Object?>),
    ];
  } catch (error) {
    throw BackupFormatException('$_pointsName 无法解析：$error');
  }
}

/// 把备份写回数据库。
///
/// [replaceExisting] 为真时先清空两张表，语义是「把数据库恢复成备份那一刻的
/// 状态」——设置页调用前必须弹确认框告知用户会丢掉现有记录。
///
/// 整个过程在一个事务里：中途失败（例如外键不满足）时回滚，不会留下半份数据。
Future<void> applyBackup(
  BackupPayload payload, {
  required Database db,
  bool replaceExisting = true,
}) async {
  await db.transaction((Transaction txn) async {
    final RideDao rides = RideDao(txn);
    final TrackPointDao points = TrackPointDao(txn);

    if (replaceExisting) {
      // 先删点再删骑行：track_points.ride_id 有外键约束。
      await points.deleteAll();
      await rides.deleteAll();
    }

    for (final Ride ride in payload.rides) {
      await rides.insertWithId(ride);
    }
    await points.insertBatch(payload.points);
  });
}
