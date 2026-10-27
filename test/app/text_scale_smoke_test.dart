import 'package:cycling_app/app/cover_gate.dart';
import 'package:cycling_app/app/providers.dart';
import 'package:cycling_app/app/theme.dart';
import 'package:cycling_app/data/ble/sensor_monitor.dart';
import 'package:cycling_app/data/sensor_pairing.dart';
import 'package:cycling_app/data/settings_repository.dart';
import 'package:cycling_app/domain/models/activity_type.dart';
import 'package:cycling_app/domain/models/location_fix.dart';
import 'package:cycling_app/domain/models/track_point.dart';
import 'package:cycling_app/domain/models/workout.dart';
import 'package:cycling_app/domain/models/workout_status.dart';
import 'package:cycling_app/domain/models/workout_summary.dart';
import 'package:cycling_app/domain/recording/recording_session.dart';
import 'package:cycling_app/features/detail/detail_page.dart';
import 'package:cycling_app/features/detail/detail_providers.dart';
import 'package:cycling_app/features/history/history_page.dart';
import 'package:cycling_app/features/history/history_providers.dart';
import 'package:cycling_app/features/record/handlebar_view.dart';
import 'package:cycling_app/features/record/record_controller.dart';
import 'package:cycling_app/features/settings/settings_page.dart';
import 'package:cycling_app/features/stats/stats_page.dart';
import 'package:cycling_app/features/stats/stats_providers.dart';
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

Workout _ride(int id, DateTime date, {String? title}) => Workout(
      id: id,
      title: title,
      startedAtMs: date.millisecondsSinceEpoch,
      endedAtMs: date.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      status: WorkoutStatus.finished,
      activityType: ActivityType.cycling,
      summary: const WorkoutSummary(
        distanceM: 25300,
        durationS: 3600,
        movingS: 3400,
        avgSpeedMps: 7.03,
        movingAvgSpeedMps: 7.44,
        maxSpeedMps: 12.5,
        elevationGainM: 180,
        avgHr: 142,
        maxHr: 176,
        avgCadence: 78,
        avgPowerW: 187,
        maxPowerW: 230,
        pointCount: 4,
      ),
    );

List<Workout> _rides() => <Workout>[
      _ride(1, DateTime(2026, 10, 26, 6, 42), title: '龙泉山 · 晨骑'),
      _ride(2, DateTime(2026, 10, 22, 18, 20), title: '驿都大道 · 通勤'),
      _ride(3, DateTime(2026, 10, 18, 7, 5), title: '青龙湖 · 环湖'),
      _ride(4, DateTime(2026, 10, 12, 8, 10), title: '三圣乡 · 闲骑'),
    ];

List<TrackPoint> _points(int id) => <TrackPoint>[
      for (int i = 0; i < 30; i++)
        TrackPoint(
          rideId: id,
          tMs: 1000 + i * 1000,
          lat: 30.0 + i * 0.00003,
          lon: 120.0 + i * 0.00004,
          altitudeM: 480 + i * 0.7,
          speedMps: 5.0 + (i % 10) * 0.35,
          hr: 138 + (i % 7),
          cadence: 76 + (i % 5),
          powerW: 180 + (i % 9),
        ),
    ];

class _Pairing implements SensorPairingRepository {
  @override
  Future<PairedSensor?> load(SensorKind kind) async => null;
  @override
  Future<void> save(SensorKind kind, PairedSensor sensor) async {}
  @override
  Future<void> clear(SensorKind kind) async {}
}

Widget _scaled(Widget child) => MaterialApp(
      theme: buildAppTheme(),
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(1.3),
        ),
        child: child!,
      ),
      home: Scaffold(body: child),
    );

Widget _record(RecordState state) => HandlebarView(
      state: state,
      unit: DistanceUnit.kilometer,
      tileUrlTemplate: kDefaultMapTileUrlTemplate,
      selectedActivityType: state.selectedActivityType,
      now: DateTime(2026, 10, 27, 6, 42),
      onSelectActivityType: (_) {},
      onStart: () {},
      onPause: () {},
      onResume: () {},
      onFinish: () {},
      onPickDevice: (_) {},
      onFixError: () {},
    );

Widget _history() => ProviderScope(
      overrides: <Override>[
        historyRidesProvider.overrideWith((Ref ref) => _rides()),
        appSettingsProvider
            .overrideWithValue(AsyncValue<AppSettings>.data(_settings)),
        nowProvider.overrideWithValue(
          () => DateTime(2026, 10, 27, 9).millisecondsSinceEpoch,
        ),
        for (final Workout ride in _rides())
          ridePointsProvider(ride.id!).overrideWith(
            (Ref ref) => _points(ride.id!),
          ),
      ],
      child: const HistoryPage(),
    );

Widget _detail() => ProviderScope(
      overrides: <Override>[
        rideDetailProvider(1).overrideWith(
          (Ref ref) => WorkoutDetail(ride: _rides().first, points: _points(1)),
        ),
        appSettingsProvider
            .overrideWithValue(AsyncValue<AppSettings>.data(_settings)),
      ],
      child: const DetailPage(rideId: 1),
    );

Widget _stats() => ProviderScope(
      overrides: <Override>[
        finishedRidesProvider.overrideWith((Ref ref) => _rides()),
        appSettingsProvider
            .overrideWithValue(AsyncValue<AppSettings>.data(_settings)),
        nowProvider.overrideWithValue(
          () => DateTime(2026, 10, 27, 9).millisecondsSinceEpoch,
        ),
      ],
      child: const StatsPage(),
    );

Widget _settingsPage() => ProviderScope(
      overrides: <Override>[
        appSettingsProvider
            .overrideWithValue(AsyncValue<AppSettings>.data(_settings)),
        sensorPairingProvider.overrideWithValue(_Pairing()),
        nowProvider.overrideWithValue(
          () => DateTime(2026, 10, 27, 9).millisecondsSinceEpoch,
        ),
      ],
      child: const SettingsPage(),
    );

void main() {
  for (final Size size in <Size>[const Size(390, 844), const Size(360, 640)]) {
    group('${size.width.toInt()}x${size.height.toInt()} @1.3', () {
      Future<void> pump(WidgetTester tester, Widget child) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_scaled(child));
        await tester.pumpAndSettle();
      }

      testWidgets('cover', (WidgetTester tester) async {
        await pump(tester, const CoverGate(child: SizedBox.shrink()));
        expect(tester.takeException(), isNull);
      });

      testWidgets('record idle with error', (WidgetTester tester) async {
        await pump(
          tester,
          _record(
            const RecordState(
              errorMessage: '定位权限已被永久拒绝，请到系统设置中开启',
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('record active', (WidgetTester tester) async {
        await pump(
          tester,
          _record(
            RecordState(
              rideId: 1,
              phase: RecordingPhase.recording,
              elapsedMs: 90000,
              distanceM: 1234,
              currentSpeedMps: 6,
              hr: 132,
              cadence: 85,
              power: 210,
              hrConnected: true,
              cadenceConnected: true,
              powerConnected: true,
              currentAltitudeM: 128,
              elevationGainM: 342,
              previewFix: const LocationFix(
                tMs: 1000,
                lat: 30,
                lon: 120,
                accuracyM: 4,
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('history', (WidgetTester tester) async {
        await pump(tester, _history());
        expect(tester.takeException(), isNull);
      });

      testWidgets('detail', (WidgetTester tester) async {
        await pump(tester, _detail());
        expect(tester.takeException(), isNull);
      });

      testWidgets('stats', (WidgetTester tester) async {
        await pump(tester, _stats());
        expect(tester.takeException(), isNull);
      });

      testWidgets('settings', (WidgetTester tester) async {
        await pump(tester, _settingsPage());
        expect(tester.takeException(), isNull);
      });
    });
  }
}
