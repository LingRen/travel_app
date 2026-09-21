import 'dart:typed_data';

import 'package:cycling_app/app/providers.dart';
import 'package:cycling_app/data/ble/sensor_monitor.dart';
import 'package:cycling_app/data/export/backup.dart';
import 'package:cycling_app/data/export/backup_io.dart';
import 'package:cycling_app/data/export/backup_store.dart';
import 'package:cycling_app/data/sensor_pairing.dart';
import 'package:cycling_app/data/settings_repository.dart';
import 'package:cycling_app/domain/models/ride.dart';
import 'package:cycling_app/domain/models/ride_status.dart';
import 'package:cycling_app/domain/models/track_point.dart';
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

/// 内存版设置仓储：记录最后一次 save 的内容。
class _FakeSettingsRepository implements SettingsRepository {
  AppSettings saved = _settings;
  int saveCalls = 0;

  @override
  Future<AppSettings> load() async => saved;

  @override
  Future<void> save(AppSettings settings) async {
    saved = settings;
    saveCalls++;
  }
}

/// 内存版配对仓储。
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

/// 内存版备份数据源。
class _FakeBackupStore implements BackupStore {
  _FakeBackupStore({this.rides = const <Ride>[]});

  List<Ride> rides;
  List<TrackPoint> points = const <TrackPoint>[];
  BackupPayload? applied;
  bool? appliedReplaceExisting;
  int listRidesCalls = 0;
  int listPointsCalls = 0;

  @override
  Future<List<Ride>> listRides() async {
    listRidesCalls++;
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

/// 内存版文件 IO：导出只记录字节，选文件返回预设内容。
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
      rides: const <Ride>[],
      points: const <TrackPoint>[],
      exportedAtMs: 0,
    );

Uint8List wrongVersionArchive() => buildBackupArchive(
      rides: const <Ride>[],
      points: const <TrackPoint>[],
      exportedAtMs: 0,
      schemaVersion: kBackupSchemaVersion + 1,
    );

/// 备份区当前渲染出的全部文本，用来断言「有没有多出一条提示」。
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
      rides: const <Ride>[
        Ride(id: 1, startedAtMs: 1000, status: RideStatus.finished, title: '晨骑'),
      ],
    );
    io = _FakeBackupIo();
  });

  Widget wrap({AppSettings current = _settings}) => ProviderScope(
        overrides: <Override>[
          settingsRepositoryProvider.overrideWithValue(settings),
          sensorPairingProvider.overrideWithValue(pairing),
          backupStoreProvider.overrideWithValue(store),
          backupIoProvider.overrideWithValue(io),
          appSettingsProvider
              .overrideWithValue(AsyncValue<AppSettings>.data(current)),
        ],
        child: const MaterialApp(home: SettingsPage()),
      );

  /// 设置页是全项目最长的 `ListView`：个人参数 4 个控件 + 保存按钮 + 传感器配对区
  /// + 备份区，默认 800x600 的测试视口只构建前几屏，页面下半部分的「保存」「解除」
  /// 「导出备份」「恢复备份」根本不会被 build，`find.text` 会假失败。参考
  /// `pumpStats` 的做法把视口调高。
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

  testWidgets('显示当前设置值', (WidgetTester tester) async {
    await pumpSettings(tester);

    expect(find.text('190'), findsOneWidget);
    expect(find.text('70.0'), findsOneWidget);
    expect(find.text('公里'), findsOneWidget);
    expect(find.text(kDefaultMapTileUrlTemplate), findsOneWidget);
  });

  testWidgets('改最大心率后保存写回仓储', (WidgetTester tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('190'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '175');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(settings.saveCalls, 1);
    expect(settings.saved.maxHeartRate, 175);
    // `_save` 末尾会 `ref.invalidate(appSettingsProvider)`，而本测试里该 provider
    // 被 `overrideWithValue` 覆盖。riverpod 3 允许这样 invalidate，不该抛异常。
    expect(tester.takeException(), isNull);
  });

  testWidgets('越界的最大心率不保存，给出提示', (WidgetTester tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('190'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '999');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(settings.saveCalls, 0);
    expect(find.textContaining('最大心率'), findsWidgets);
  });

  testWidgets('没有配对传感器时显示未配对，并提供连接入口', (WidgetTester tester) async {
    await pumpSettings(tester);

    expect(find.textContaining('未配对'), findsNWidgets(2)); // 心率 + 踏频
  });

  testWidgets('已配对的传感器显示名字与解除按钮', (WidgetTester tester) async {
    pairing.stored[SensorKind.heartRate] =
        const PairedSensor(id: 'AA:01', name: 'FIT 3');

    await pumpSettings(tester);

    expect(find.textContaining('FIT 3'), findsOneWidget);
    expect(find.text('解除'), findsOneWidget);
  });

  testWidgets('点解除后清掉配对并刷新界面', (WidgetTester tester) async {
    pairing.stored[SensorKind.heartRate] =
        const PairedSensor(id: 'AA:01', name: 'FIT 3');

    await pumpSettings(tester);
    expect(find.textContaining('FIT 3'), findsOneWidget);

    await tester.tap(find.text('解除'));
    await tester.pumpAndSettle();

    expect(pairing.stored.containsKey(SensorKind.heartRate), isFalse);
    expect(find.textContaining('FIT 3'), findsNothing);
  });

  testWidgets('点导出备份会把归档交给 IO 层', (WidgetTester tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('导出备份'));
    await tester.pumpAndSettle();

    expect(io.exportCalls, 1);
    expect(io.exported, isNotNull);
    expect(io.exportedFileName, endsWith('.zip'));
    // 归档能被解回来，说明内容是真的。
    final BackupPayload payload = parseBackupArchive(io.exported!);
    expect(payload.rides.single.title, '晨骑');
  });

  testWidgets('导出的归档包含轨迹点', (WidgetTester tester) async {
    store.points = const <TrackPoint>[
      TrackPoint(rideId: 1, tMs: 1000, lat: 31.0, lon: 121.0, speedMps: 4.0),
      TrackPoint(rideId: 1, tMs: 2000, lat: 31.001, lon: 121.0, speedMps: 5.0),
    ];

    await pumpSettings(tester);

    await tester.tap(find.text('导出备份'));
    await tester.pumpAndSettle();

    // 只断言「rides 在里面」杀不掉「导出时漏掉 listPoints」这种数据完整性变异：
    // 必须真的把轨迹点读回来核对内容与条数。
    expect(store.listPointsCalls, 1);
    final BackupPayload payload = parseBackupArchive(io.exported!);
    expect(payload.points, hasLength(2));
    expect(payload.points.first.lat, 31.0);
    expect(payload.points.last.tMs, 2000);
    expect(payload.manifest.pointCount, 2);
    expect(payload.manifest.rideCount, 1);
  });

  testWidgets('导出失败时显示提示而不是崩溃', (WidgetTester tester) async {
    io.exportError = StateError('磁盘满了');

    await pumpSettings(tester);

    await tester.tap(find.text('导出备份'));
    await tester.pumpAndSettle();

    expect(find.textContaining('导出失败'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('用户取消选文件时不弹确认框也不写库', (WidgetTester tester) async {
    io.pickResult = null;

    await pumpSettings(tester);

    await tester.tap(find.text('恢复备份'));
    await tester.pumpAndSettle();

    expect(io.pickCalls, 1);
    expect(find.text('确认恢复？'), findsNothing);
    expect(store.applied, isNull);
    // 取消必须是「什么都不做」：若把 `bytes == null` 的 return 去掉，空字节会走进
    // `parseBackupArchive`，抛出的 `BackupFormatException`（「归档里没有 manifest.json」）
    // 会被 `on BackupFormatException` 接住并渲染成提示。只断言「不弹框、不写库」
    // 杀不掉这个变异，所以这里直接钉死备份区渲染出的全部文本。
    expect(backupSectionTexts(tester), <String>['备份与恢复', '导出备份', '恢复备份']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('归档版本不匹配时说明原因，且不写库', (WidgetTester tester) async {
    io.pickResult = wrongVersionArchive();

    await pumpSettings(tester);

    await tester.tap(find.text('恢复备份'));
    await tester.pumpAndSettle();

    expect(find.textContaining('schema 版本'), findsOneWidget);
    expect(find.text('确认恢复？'), findsNothing);
    expect(store.applied, isNull);
  });

  testWidgets('确认框里取消则不写库', (WidgetTester tester) async {
    io.pickResult = emptyArchive();

    await pumpSettings(tester);

    await tester.tap(find.text('恢复备份'));
    await tester.pumpAndSettle();

    expect(find.text('确认恢复？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(store.applied, isNull);
  });

  testWidgets('点确认框外面关掉不写库', (WidgetTester tester) async {
    io.pickResult = emptyArchive();

    await pumpSettings(tester);

    await tester.tap(find.text('恢复备份'));
    await tester.pumpAndSettle();
    expect(find.text('确认恢复？'), findsOneWidget);

    // 点对话框外的遮罩：`showDialog` 返回 null，而不是 true/false。这是唯一能区分
    // `_confirm(payload) ?? false` 与 `?? true` 的路径——点「取消」返回的是 false，
    // `false ?? true` 仍然是 false，杀不掉这个变异。
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    expect(find.text('确认恢复？'), findsNothing);
    expect(store.applied, isNull);
  });

  testWidgets('确认后按替换语义写回备份', (WidgetTester tester) async {
    io.pickResult = emptyArchive();

    await pumpSettings(tester);

    await tester.tap(find.text('恢复备份'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();

    expect(store.applied, isNotNull);
    expect(store.appliedReplaceExisting, isTrue);
    expect(find.textContaining('恢复完成'), findsOneWidget);
  });
}
