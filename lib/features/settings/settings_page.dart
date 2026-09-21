import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/ble/sensor_monitor.dart';
import '../../data/sensor_pairing.dart';
import '../../data/settings_repository.dart';
import 'backup_section.dart';

/// 设置页。见设计文档 10.5。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late final TextEditingController _maxHr;
  late final TextEditingController _weight;
  late final TextEditingController _tileUrl;

  DistanceUnit _unit = DistanceUnit.kilometer;
  String? _error;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _maxHr = TextEditingController();
    _weight = TextEditingController();
    _tileUrl = TextEditingController();
  }

  @override
  void dispose() {
    _maxHr.dispose();
    _weight.dispose();
    _tileUrl.dispose();
    super.dispose();
  }

  /// 只在第一次拿到设置时填进输入框，之后不覆盖用户正在输入的内容。
  void _fillOnce(AppSettings settings) {
    if (_loaded) return;
    _loaded = true;
    _maxHr.text = '${settings.maxHeartRate}';
    _weight.text = settings.weightKg.toStringAsFixed(1);
    _tileUrl.text = settings.mapTileUrlTemplate;
    _unit = settings.distanceUnit;
  }

  @override
  Widget build(BuildContext context) {
    // riverpod 3 的 `AsyncValue` 没有 `valueOrNull`，用 `.value`（可为 null）。
    final AppSettings? settings = ref.watch(appSettingsProvider).value;
    if (settings == null) {
      return const Scaffold(
        appBar: null,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    _fillOnce(settings);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text('个人参数', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          TextField(
            controller: _maxHr,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '最大心率（bpm）',
              helperText: '用于心率区间划分，可参考 220 − 年龄',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _weight,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '体重（kg）',
              helperText: '仅用于估算卡路里，结果仅供参考',
            ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<DistanceUnit>(
            segments: const <ButtonSegment<DistanceUnit>>[
              ButtonSegment<DistanceUnit>(
                value: DistanceUnit.kilometer,
                label: Text('公里'),
              ),
              ButtonSegment<DistanceUnit>(
                value: DistanceUnit.mile,
                label: Text('英里'),
              ),
            ],
            selected: <DistanceUnit>{_unit},
            onSelectionChanged: (Set<DistanceUnit> selected) =>
                setState(() => _unit = selected.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _tileUrl,
            decoration: const InputDecoration(
              labelText: '地图瓦片源',
              helperText: '高德接口失效时可换成 OSM 或自建源，无需重新发版',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('保存')),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const Divider(height: 40),
          const _SensorSection(),
          const Divider(height: 40),
          const BackupSection(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final int? hr = int.tryParse(_maxHr.text.trim());
    final double? weight = double.tryParse(_weight.text.trim());
    final String tileUrl = _tileUrl.text.trim();

    if (hr == null ||
        hr < kMinPlausibleMaxHeartRate ||
        hr > kMaxPlausibleMaxHeartRate) {
      setState(() => _error =
          '最大心率需要是 $kMinPlausibleMaxHeartRate~$kMaxPlausibleMaxHeartRate 之间的整数');
      return;
    }
    if (weight == null || weight <= 0) {
      setState(() => _error = '体重需要是大于 0 的数字');
      return;
    }
    if (tileUrl.isEmpty) {
      setState(() => _error = '地图瓦片源不能为空');
      return;
    }

    setState(() => _error = null);
    await ref.read(settingsRepositoryProvider).save(AppSettings(
          maxHeartRate: hr,
          weightKg: weight,
          distanceUnit: _unit,
          mapTileUrlTemplate: tileUrl,
        ));
    ref.invalidate(appSettingsProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('设置已保存')),
    );
  }
}

/// 传感器配对管理。见设计文档 10.5。
class _SensorSection extends ConsumerStatefulWidget {
  const _SensorSection();

  @override
  ConsumerState<_SensorSection> createState() => _SensorSectionState();
}

class _SensorSectionState extends ConsumerState<_SensorSection> {
  Map<SensorKind, PairedSensor?> _paired = <SensorKind, PairedSensor?>{};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    final SensorPairingRepository repo = ref.read(sensorPairingProvider);
    final Map<SensorKind, PairedSensor?> result = <SensorKind, PairedSensor?>{};
    for (final SensorKind kind in SensorKind.values) {
      result[kind] = await repo.load(kind);
    }
    if (!mounted) return;
    setState(() {
      _paired = result;
      _loaded = true;
    });
  }

  Future<void> _clear(SensorKind kind) async {
    await ref.read(sensorPairingProvider).clear(kind);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('传感器配对', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text(
          '连接成功后会自动记住设备，下次开始记录时自动重连。',
          style: TextStyle(fontSize: 12, color: Colors.white54),
        ),
        const SizedBox(height: 12),
        if (!_loaded)
          const SizedBox(
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else ...<Widget>[
          _row('心率', SensorKind.heartRate),
          const SizedBox(height: 8),
          _row('踏频', SensorKind.cadence),
        ],
      ],
    );
  }

  Widget _row(String label, SensorKind kind) {
    final PairedSensor? paired = _paired[kind];
    return Row(
      children: <Widget>[
        SizedBox(width: 56, child: Text(label)),
        Expanded(
          child: Text(
            paired == null
                ? '未配对'
                : (paired.name.isEmpty ? paired.id : paired.name),
            style: TextStyle(
              fontSize: 13,
              color: paired == null ? Colors.white54 : kAppAccent,
            ),
          ),
        ),
        if (paired != null)
          TextButton(onPressed: () => _clear(kind), child: const Text('解除')),
      ],
    );
  }
}
