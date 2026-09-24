import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/ble/sensor_monitor.dart';
import '../../data/mock_ride_seeder.dart';
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
        padding: EdgeInsets.zero,
        children: <Widget>[
          const _SectionLabel('个人参数', leadingDivider: false),
          Padding(
            padding: const EdgeInsets.fromLTRB(kSpaceL, kSpaceM, kSpaceL, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextField(
                  controller: _maxHr,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '最大心率（bpm）',
                    helperText: '用于心率区间划分，可参考 220 − 年龄',
                  ),
                ),
                const SizedBox(height: kSpaceM),
                TextField(
                  controller: _weight,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: '体重（kg）',
                    helperText: '仅用于估算卡路里，结果仅供参考',
                  ),
                ),
                const SizedBox(height: kSpaceL),
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
                const SizedBox(height: kSpaceL),
                TextField(
                  controller: _tileUrl,
                  decoration: const InputDecoration(
                    labelText: '地图瓦片源',
                    helperText: '高德接口失效时可换成 OSM 或自建源，无需重新发版',
                  ),
                ),
                const SizedBox(height: kSpaceL),
                FilledButton(onPressed: _save, child: const Text('保存')),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: kSpaceM),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Icon(
                        Icons.error_outline,
                        size: 16,
                        color: kAppDanger,
                      ),
                      const SizedBox(width: kSpaceS),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            fontSize: 13,
                            color: kAppDanger,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: kSpaceXl),
          // 传感器与备份两块自带标题和分隔线（备份块的标题文本被测试依赖，
          // 必须留在 BackupSection 内部），这里不再套分组标签。
          const _SensorSection(),
          const SizedBox(height: kSpaceXl),
          const BackupSection(),
          const SizedBox(height: kSpaceXxl),
          if (kDebugMode) ...<Widget>[
            const _DebugSection(),
            const SizedBox(height: kSpaceXxl),
          ],
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

/// 分组标签。上方一条从边到边的细线把这一组和上一组分开——原来靠 40px 高的
/// Divider 撑开间距，三组之间只剩留白，扫一眼分不清哪几行是同属一组。
/// 第一组不画线：AppBar 自带一条底边线，再画一条就叠成两像素粗。
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.leadingDivider = true});

  final String text;
  final bool leadingDivider;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (leadingDivider) const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(kSpaceL, kSpaceL, kSpaceL, 0),
            child: Text(text, style: kSectionTextStyle),
          ),
        ],
      );
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Divider(height: 1),
        const Padding(
          padding: EdgeInsets.fromLTRB(kSpaceL, kSpaceL, kSpaceL, 0),
          child: Text('传感器配对', style: kSectionTextStyle),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(kSpaceL, kSpaceS, kSpaceL, 0),
          child: Text(
            '连接成功后会自动记住设备，下次开始记录时自动重连。',
            style: kMutedTextStyle.copyWith(fontSize: 12),
          ),
        ),
        const SizedBox(height: kSpaceM),
        if (!_loaded)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: kSpaceL),
            child: SizedBox(
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kSpaceL),
            child: Column(
              children: <Widget>[
                _row('心率', SensorKind.heartRate),
                const SizedBox(height: kSpaceS),
                _row('踏频', SensorKind.cadence),
                const SizedBox(height: kSpaceS),
                _row('功率', SensorKind.power),
              ],
            ),
          ),
      ],
    );
  }

  Widget _row(String label, SensorKind kind) {
    final PairedSensor? paired = _paired[kind];
    return Row(
      children: <Widget>[
        SizedBox(width: 56, child: Text(label, style: kLabelTextStyle)),
        Expanded(
          child: Text(
            paired == null
                ? '未配对'
                : (paired.name.isEmpty ? paired.id : paired.name),
            style: TextStyle(
              fontSize: 13,
              color: paired == null ? kAppTextMuted : kAppAccent,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (paired != null)
          TextButton(onPressed: () => _clear(kind), child: const Text('解除')),
      ],
    );
  }
}

/// 调试区块：只在 debug 构建里出现（见 `kDebugMode`），用来在真机上铺一批
/// 模拟骑行看排版，以及看够了之后一键清场。
///
/// 不放进 release：这不是用户功能，留着只会让人误以为 App 自带样例数据。
class _DebugSection extends ConsumerStatefulWidget {
  const _DebugSection();

  @override
  ConsumerState<_DebugSection> createState() => _DebugSectionState();
}

class _DebugSectionState extends ConsumerState<_DebugSection> {
  static const int _seedCount = 16;

  bool _busy = false;
  String? _message;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Divider(height: 1),
        const Padding(
          padding: EdgeInsets.fromLTRB(kSpaceL, kSpaceL, kSpaceL, 0),
          child: Text('调试（仅 debug 构建）', style: kSectionTextStyle),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(kSpaceL, kSpaceS, kSpaceL, 0),
          child: Text(
            '铺 $_seedCount 条模拟骑行，跨最近两个半月，'
            '用来检查历史页、统计页的排版与曲线。',
            style: kMutedTextStyle.copyWith(fontSize: 12),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(kSpaceL, kSpaceM, kSpaceL, 0),
          child: Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _seed,
                  child: const Text('生成模拟数据'),
                ),
              ),
              const SizedBox(width: kSpaceM),
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _clear,
                  style: OutlinedButton.styleFrom(foregroundColor: kAppDanger),
                  child: const Text('清空全部记录'),
                ),
              ),
            ],
          ),
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(kSpaceL, kSpaceM, kSpaceL, 0),
            child: Text(_message!, style: kMutedTextStyle.copyWith(fontSize: 13)),
          ),
      ],
    );
  }

  Future<void> _seed() async {
    final bool ok = await _confirm(
      title: '生成 $_seedCount 条模拟记录？',
      body: '会在最近两个半月里铺一批假骑行，走的是和真实记录一样的写入路径。'
          '上次生成的模拟记录会被覆盖成同一批（不会越点越多），真实记录不动。',
      action: '生成',
    );
    if (!ok) return;

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final int count = await seedMockRides(
        ref.read(rideRepositoryProvider),
        nowMs: ref.read(nowProvider)(),
      );
      _setMessage('已生成 $count 条模拟记录，切到历史页看看');
    } catch (error) {
      _setMessage('生成失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    final bool ok = await _confirm(
      title: '清空全部记录？',
      body: '会删除全部骑行记录，包括真实记录和模拟记录。这一步无法撤销。',
      action: '清空',
    );
    if (!ok) return;

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final int count =
          await deleteAllRides(ref.read(rideRepositoryProvider));
      _setMessage('已删除 $count 条记录');
    } catch (error) {
      _setMessage('删除失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: <Widget>[
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  void _setMessage(String message) {
    if (!mounted) return;
    setState(() => _message = message);
  }
}
