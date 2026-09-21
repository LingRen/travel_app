import 'package:sqflite/sqflite.dart';

/// 当前 schema 版本。备份文件的 manifest.json 会带上这个数字。
const int kSchemaVersion = 1;

/// 打开（必要时创建）本地数据库。
///
/// 测试时传入 [inMemoryDatabasePath] 并事先把全局 `databaseFactory`
/// 设为 `databaseFactoryFfi`，即可在桌面环境跑真实 SQLite。
Future<Database> openAppDatabase({String? path}) async {
  final String dbPath =
      path ?? '${await databaseFactory.getDatabasesPath()}/cycling_app.db';
  return databaseFactory.openDatabase(
    dbPath,
    options: OpenDatabaseOptions(
      version: kSchemaVersion,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
    ),
  );
}

Future<void> _onConfigure(Database db) async {
  await db.execute('PRAGMA foreign_keys = ON');
}

Future<void> _onCreate(Database db, int version) async {
  await db.execute('''
    CREATE TABLE rides (
      id                   INTEGER PRIMARY KEY AUTOINCREMENT,
      started_at           INTEGER NOT NULL,
      ended_at             INTEGER,
      status               TEXT    NOT NULL,
      title                TEXT,
      distance_m           REAL,
      duration_s           INTEGER,
      moving_s             INTEGER,
      avg_speed_mps        REAL,
      moving_avg_speed_mps REAL,
      max_speed_mps        REAL,
      elevation_gain_m     REAL,
      avg_hr               REAL,
      max_hr               INTEGER,
      avg_cadence          REAL,
      calories             REAL,
      hr_device_name       TEXT,
      cadence_device_name  TEXT,
      point_count          INTEGER
    )
  ''');

  await db.execute('''
    CREATE TABLE track_points (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      ride_id    INTEGER NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
      t_ms       INTEGER NOT NULL,
      lat        REAL,
      lon        REAL,
      altitude_m REAL,
      speed_mps  REAL,
      accuracy_m REAL,
      hr         INTEGER,
      cadence    INTEGER
    )
  ''');

  await db.execute(
    'CREATE INDEX idx_track_points_ride_t ON track_points(ride_id, t_ms)',
  );

  await db.execute('''
    CREATE TABLE settings (
      key   TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
  ''');
}
