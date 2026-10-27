import 'dart:typed_data';

import 'package:cycling_app/app/providers.dart';
import 'package:cycling_app/app/theme.dart';
import 'package:cycling_app/app/ui/paper_sheet.dart';
import 'package:cycling_app/data/ble/ble_platform.dart';
import 'package:cycling_app/data/ble/ble_scanner.dart';
import 'package:cycling_app/data/ble/sensor_monitor.dart';
import 'package:cycling_app/data/export/backup.dart';
import 'package:cycling_app/data/export/backup_io.dart';
import 'package:cycling_app/data/export/backup_store.dart';
import 'package:cycling_app/data/sensor_pairing.dart';
import 'package:cycling_app/data/settings_repository.dart';
import 'package:cycling_app/domain/models/activity_type.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:cycling_app/domain/models/workout.dart';
import 'package:cycling_app/domain/models/workout_status.dart';
import 'package:cycling_app/features/settings/backup_section.dart';
import 'package:cycling_app/features/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

const AppSettings _settings = AppSettings(
  maxHeartRate: 190,
  weightKg: 70,
  distanceUnit: DistanceUnit.kilometer,
  mapTileUrlTemplate: kDefaultMapTileUrlTemplate,
);

class _FakeSettingsRepository implements SettingsRepository {
  AppSettings saved = _settings;
  int saveCalls = 0;
  int? lastBackupAtMs;

  @override
  Future<AppSettings> load() async => saved;

  @override
  Future<void> save(AppSettings settings) async {
    saved = settings;
    saveCalls++;
  }

  @override
  Future<int?> lastBackupAt() async => lastBackupAtMs;

  @override
  Future<void> saveLastBackupAt(int epochMs) async {
    lastBackupAtMs = epochMs;
  }

  @override
  Future<void> saveLastActivityType(ActivityType type) async {
    saved = saved.copyWith(lastActivityType: type);
  }
}

class _FakeSensorPairing implements SensorPairingRepository {
  final Map<SensorKind, PairedSensor> stored = <SensorKind, PairedSensor>{};

  @override
  Future<PairedSensor?> load(SensorKind kind) async => stored[kind];

  @override
  Future<void> save(SensorKind kind, PairedSensor sensor) async {
    stored[kind] = sensor;
  }

  @override
  Future<void> clear(SensorKind kind) async {
    stored.remove(kind);
  }
}

class _FakeBleScanner implements BleScanner {
  @override
  Future<bool> isAdapterOn() async => true;

  @override
  Future<BleDeviceHandle?> deviceById(String id) async => null;

  @override
  Future<List<DiscoveredDevice>> scan({
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      const <DiscoveredDevice>[];
}

class _FakeBackupStore implements BackupStore {
  _FakeBackupStore({this.rides = const <Workout>[]});

  List<Workout> rides;
  List<TrackPoint> points = const <TrackPoint>[];
  BackupPayload? applied;
  bool? appliedReplaceExisting;
  int listWorkoutsCalls = 0;
  int listPointsCalls = 0;

  @override
  Future<List<Workout>> listWorkouts() async {
    listWorkoutsCalls++;
    return rides;
  }

  @override
  Future<List<TrackPoint>> listPoints() async {
    listPointsCalls++;
    return points;
  }

  @override
  Future<void> apply(
    BackupPayload payload, {
    required bool replaceExisting,
  }) async {
    applied = payload;
    appliedReplaceExisting = replaceExisting;
  }
}

class _FakeBackupIo implements BackupIo {
  Uint8List? pickResult;
  Uint8List? exported;
  String? exportedFileName;
  int exportCalls = 0;
  int pickCalls = 0;
  Object? exportError;

  @override
  Future<void> exportArchive(
    Uint8List bytes, {
    required String fileName,
  }) async {
    exportCalls++;
    if (exportError != null) throw exportError!;
    exported = bytes;
    exportedFileName = fileName;
  }

  @override
  Future<Uint8List?> pickArchive() async {
    pickCalls++;
    return pickResult;
  }
}

Uint8List emptyArchive() => buildBackupArchive(
      rides: const <Workout>[],
      points: const <TrackPoint>[],
      exportedAtMs: 0,
    );

Uint8List wrongVersionArchive() => buildBackupArchive(
      rides: const <Workout>[],
      points: const <TrackPoint>[],
      exportedAtMs: 0,
      schemaVersion: kBackupSchemaVersion + 1,
    );

List<String> backupSectionTexts(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byType(BackupSection),
        matching: find.byType(Text),
      ),
    )
    .map((Text text) => text.data ?? '')
    .toList();

void main() {
  late _FakeSettingsRepository settings;
  late _FakeSensorPairing pairing;
  late _FakeBackupStore store;
  late _FakeBackupIo io;

  setUp(() {
    settings = _FakeSettingsRepository();
    pairing = _FakeSensorPairing();
    store = _FakeBackupStore(
      rides: const <Workout>[
        Workout(
          id: 1,
          startedAtMs: 1000,
          status: WorkoutStatus.finished,
          title: '晨骑',
        ),
      ],
    );
    io = _FakeBackupIo();
  });

  Widget wrap({AppSettings current = _settings}) => ProviderScope(
        overrides: <Override>[
          settingsRepositoryProvider.overrideWithValue(settings),
          sensorPairingProvider.overrideWithValue(pairing),
          bleScannerProvider.overrideWithValue(_FakeBleScanner()),
          backupStoreProvider.overrideWithValue(store),
          backupIoProvider.overrideWithValue(io),
          appSettingsProvider
              .overrideWithValue(AsyncValue<AppSettings>.data(current)),
        ],
        child: MaterialApp(theme: buildAppTheme(), home: const SettingsPage()),
      );

  Future<void> pumpSettings(
    WidgetTester tester, {
    AppSettings current = _settings,
  }) async {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(current: current));
    await tester.pumpAndSettle();
  }

  Future<void> openRow(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  Finder sheetTextField() => find.descendant(
        of: find.byType(PaperSheet),
        matching: find.byType(TextField),
      );

  Future<void> saveSheet(WidgetTester tester) async {
    await tester.tap(
      find.descendant(
        of: find.byType(PaperSheet),
        matching: find.text('保存'),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> closeSheet(WidgetTester tester) async {
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
  }

  Future<void> openBackup(WidgetTester tester) async {
    await openRow(tester, 'settings-backup');
  }

  testWidgets('显示页眉、五个分组与当前设置值', (WidgetTester tester) async {
    await pumpSettings(tester);

    expect(find.text('本 机 设 置'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('身体、传感器与这一册的样貌'), findsOneWidget);
    // 五个分组按从上到下的顺序出现。
    final List<String> groups = <String>[
      '身 体',
      '传 感 器',
      '地 图 与 外 观',
      '数 据',
      '关 于',
    ];
    double previous = -1;
    for (final String group in groups) {
      final double y = tester.getTopLeft(find.text(group)).dy;
      expect(y, greaterThan(previous), reason: group);
      previous = y;
    }

    expect(find.text('最大心率'), findsOneWidget);
    expect(find.text('190 bpm'), findsOneWidget);
    expect(find.text('体重'), findsOneWidget);
    expect(find.text('70.0 kg'), findsOneWidget);
    expect(find.text('距离单位'), findsOneWidget);
    expect(find.text('公里'), findsOneWidget);
    expect(find.text('地图瓦片'), findsOneWidget);
    expect(find.text('高德 · 宣纸'), findsOneWidget);
    expect(find.text('行迹 XINGJI · 1.0.0'), findsOneWidget);
    expect(find.text('数据仅存本机'), findsOneWidget);
  });

  testWidgets('修改最大心率后立即保存', (WidgetTester tester) async {
    await pumpSettings(tester);

    await openRow(tester, 'settings-max-hr');
    expect(find.byType(PaperSheet), findsOneWidget);
    await tester.enterText(sheetTextField(), '175');
    await saveSheet(tester);

    expect(settings.saveCalls, 1);
    expect(settings.saved.maxHeartRate, 175);
    expect(find.byType(PaperSheet), findsNothing);
  });

  testWidgets('越界最大心率不关闭面板，给出提示', (WidgetTester tester) async {
    await pumpSettings(tester);

    await openRow(tester, 'settings-max-hr');
    await tester.enterText(sheetTextField(), '999');
    await saveSheet(tester);

    expect(settings.saveCalls, 0);
    expect(find.byType(PaperSheet), findsOneWidget);
    expect(find.textContaining('100~230'), findsOneWidget);
    await closeSheet(tester);
    expect(find.byType(PaperSheet), findsNothing);
  });

  testWidgets('体重与瓦片源校验，取消不写库', (WidgetTester tester) async {
    await pumpSettings(tester);

    await openRow(tester, 'settings-weight');
    await tester.enterText(sheetTextField(), '0');
    await saveSheet(tester);
    expect(settings.saveCalls, 0);
    expect(find.textContaining('大于 0'), findsOneWidget);
    await closeSheet(tester);

    await openRow(tester, 'settings-tile');
    await tester.enterText(sheetTextField(), 'not a url');
    await saveSheet(tester);
    expect(settings.saveCalls, 0);
    expect(find.textContaining('http(s)'), findsOneWidget);
    await closeSheet(tester);
  });

  testWidgets('修改体重与瓦片源后立即保存', (WidgetTester tester) async {
    await pumpSettings(tester);

    await openRow(tester, 'settings-weight');
    await tester.enterText(sheetTextField(), '68.5');
    await saveSheet(tester);
    expect(settings.saved.weightKg, 68.5);

    await openRow(tester, 'settings-tile');
    await tester.enterText(
      sheetTextField(),
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    );
    await saveSheet(tester);
    expect(
      settings.saved.mapTileUrlTemplate,
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    );
  });

  testWidgets('距离单位行内切换并立即保存', (WidgetTester tester) async {
    await pumpSettings(tester);

    await openRow(tester, 'settings-unit');
    await tester.tap(find.byKey(const Key('unit-mile')));
    await tester.pumpAndSettle();

    expect(settings.saveCalls, 1);
    expect(settings.saved.distanceUnit, DistanceUnit.mile);
  });

  testWidgets('未连接传感器行打开设备面板', (WidgetTester tester) async {
    await pumpSettings(tester);

    expect(find.text('未连接'), findsNWidgets(3));
    await openRow(tester, 'sensor-heartRate');

    expect(find.text('选择心率设备'), findsOneWidget);
    expect(find.text('没有发现设备'), findsOneWidget);
    // 关闭底部面板。
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.text('选择心率设备'), findsNothing);
  });

  testWidgets('已配对传感器显示设备名与已连接，断开后回到未连接',
      (WidgetTester tester) async {
    pairing.stored[SensorKind.heartRate] =
        const PairedSensor(id: 'AA:01', name: 'FIT 3');

    await pumpSettings(tester);

    expect(find.textContaining('FIT 3'), findsOneWidget);
    expect(find.text('已连接'), findsOneWidget);
    await tester.tap(find.text('断开'));
    await tester.pumpAndSettle();

    expect(pairing.stored.containsKey(SensorKind.heartRate), isFalse);
    expect(find.textContaining('FIT 3'), findsNothing);
    expect(find.text('未连接'), findsNWidgets(3));
  });

  testWidgets('四颗主题色带名称与当前标记，点选即保存', (WidgetTester tester) async {
    await pumpSettings(tester);

    for (final ThemeAccent accent in ThemeAccent.values) {
      expect(find.byKey(Key('accent-${accent.dbValue}')), findsOneWidget);
      expect(find.text(accent.label), findsOneWidget);
    }
    expect(find.text('当前 朱砂'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('accent-cinnabar')),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('accent-celadon')));
    await tester.pumpAndSettle();

    expect(settings.saveCalls, 1);
    expect(settings.saved.accent, ThemeAccent.celadon);
  });

  testWidgets('以青瓷启动时当前标记与对勾落在青瓷上', (WidgetTester tester) async {
    await pumpSettings(
      tester,
      current: _settings.copyWith(accent: ThemeAccent.celadon),
    );

    expect(find.text('当前 青瓷'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('accent-celadon')),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
  });

  testWidgets('导出备份写入文件并记录上次备份时间', (WidgetTester tester) async {
    await pumpSettings(tester);
    await openBackup(tester);

    await tester.tap(find.text('导出备份'));
    await tester.pumpAndSettle();

    expect(io.exportCalls, 1);
    expect(io.exported, isNotNull);
    expect(io.exportedFileName, endsWith('.zip'));
    expect(settings.lastBackupAtMs, isNotNull);
    final BackupPayload payload = parseBackupArchive(io.exported!);
    expect(payload.rides.single.title, '晨骑');
    expect(find.textContaining('已导出'), findsOneWidget);

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.textContaining('上次'), findsOneWidget);
  });

  testWidgets('导出的归档包含轨迹点', (WidgetTester tester) async {
    store.points = const <TrackPoint>[
      TrackPoint(rideId: 1, tMs: 1000, lat: 31.0, lon: 121.0, speedMps: 4.0),
      TrackPoint(rideId: 1, tMs: 2000, lat: 31.001, lon: 121.0, speedMps: 5.0),
    ];
    await pumpSettings(tester);
    await openBackup(tester);

    await tester.tap(find.text('导出备份'));
    await tester.pumpAndSettle();

    expect(store.listPointsCalls, 1);
    final BackupPayload payload = parseBackupArchive(io.exported!);
    expect(payload.points, hasLength(2));
    expect(payload.points.first.lat, 31.0);
    expect(payload.points.last.tMs, 2000);
    expect(payload.manifest.pointCount, 2);
    expect(payload.manifest.rideCount, 1);
  });

  testWidgets('导出失败时显示中文提示', (WidgetTester tester) async {
    io.exportError = StateError('磁盘满了');
    await pumpSettings(tester);
    await openBackup(tester);

    await tester.tap(find.text('导出备份'));
    await tester.pumpAndSettle();

    expect(find.textContaining('导出失败'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('恢复取消选文件时不弹确认框也不写库', (WidgetTester tester) async {
    io.pickResult = null;
    await pumpSettings(tester);
    await openBackup(tester);

    await tester.tap(find.text('恢复备份'));
    await tester.pumpAndSettle();

    expect(io.pickCalls, 1);
    expect(find.text('确认恢复？'), findsNothing);
    expect(store.applied, isNull);
    expect(backupSectionTexts(tester), <String>['导出备份', '恢复备份']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('归档版本不匹配时说明原因，且不写库', (WidgetTester tester) async {
    io.pickResult = wrongVersionArchive();
    await pumpSettings(tester);
    await openBackup(tester);

    await tester.tap(find.text('恢复备份'));
    await tester.pumpAndSettle();

    expect(find.textContaining('schema 版本'), findsOneWidget);
    expect(find.text('确认恢复？'), findsNothing);
    expect(store.applied, isNull);
  });

  testWidgets('确认框里取消则不写库', (WidgetTester tester) async {
    io.pickResult = emptyArchive();
    await pumpSettings(tester);
    await openBackup(tester);

    await tester.tap(find.text('恢复备份'));
    await tester.pumpAndSettle();
    expect(find.text('确认恢复？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(store.applied, isNull);
  });

  testWidgets('确认后按替换语义写回备份', (WidgetTester tester) async {
    io.pickResult = emptyArchive();
    await pumpSettings(tester);
    await openBackup(tester);

    await tester.tap(find.text('恢复备份'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();

    expect(store.applied, isNotNull);
    expect(store.appliedReplaceExisting, isTrue);
    expect(find.textContaining('恢复完成'), findsOneWidget);
  });

  testWidgets('关于区不出现账号、云同步或社交入口', (WidgetTester tester) async {
    await pumpSettings(tester);

    expect(find.text('行迹 XINGJI · 1.0.0'), findsOneWidget);
    expect(find.text('数据仅存本机'), findsOneWidget);
    for (final String word in <String>['账号', '云同步', '社交', '登录']) {
      expect(find.textContaining(word), findsNothing, reason: word);
    }
    // debug 构建下有调试工具；release 由 kDebugMode 门控（见源码）。
    expect(find.text('调试（仅 debug 构建）'), findsOneWidget);
  });
}
