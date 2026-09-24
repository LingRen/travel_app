import 'package:sqflite/sqflite.dart';

/// 当前 schema 版本。备份文件的 manifest.json 会带上这个数字。
///
/// v2 引入功率：`track_points.power_w`、`rides.avg_power_w` / `max_power_w` /
/// `power_device_name`。老库由 [_onUpgrade] 就地补列，不重建表。
const int kSchemaVersion = 2;

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
      onUpgrade: _onUpgrade,
    ),
  );
}

Future<void> _onConfigure(Database db) async {
  await db.execute('PRAGMA foreign_keys = ON');
}

/// v1 → v2：补齐功率相关的列。
///
/// 用 `ADD COLUMN` 而不是建新表搬数据：真机上已经有真实骑行记录，重建表要
/// 先把几千个轨迹点读出来再写回去，中途失败就是一个半截的库。加列是原子的、
/// 不需要重写任何一行数据，老记录的新列自然是 null——正好表示「那次没有功率计」。
Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
  if (oldVersion < 2) {
    await db.execute('ALTER TABLE track_points ADD COLUMN power_w INTEGER');
    await db.execute('ALTER TABLE rides ADD COLUMN avg_power_w REAL');
    await db.execute('ALTER TABLE rides ADD COLUMN max_power_w INTEGER');
    await db.execute('ALTER TABLE rides ADD COLUMN power_device_name TEXT');
  }
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
      avg_power_w          REAL,
      max_power_w          INTEGER,
      calories             REAL,
      hr_device_name       TEXT,
      cadence_device_name  TEXT,
      power_device_name    TEXT,
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
      cadence    INTEGER,
      power_w    INTEGER
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
