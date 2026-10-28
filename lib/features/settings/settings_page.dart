import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../app/ui/page_header.dart';
import '../../app/ui/paper_sheet.dart';
import '../../core/format.dart';
import '../../data/ble/ble_scanner.dart';
import '../../data/ble/sensor_monitor.dart';
import '../../data/mock_ride_seeder.dart';
import '../../data/sensor_pairing.dart';
import '../../data/settings_repository.dart';
import '../record/device_picker_sheet.dart';
import 'backup_section.dart';
import 'settings_providers.dart';

/// 设置页。见设计文档 10.5。
///
/// 页眉 + 五组「行」：身体、传感器、地图与外观、数据、关于。没有卡片、没有
/// 全局保存按钮——每一行点开底部面板，确认后立即写库；主题色与距离单位点选即存。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppSettings? settings = ref.watch(appSettingsProvider).value;
    if (settings == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final AppPalette palette = context.palette;
    final DateTime now = DateTime.fromMillisecondsSinceEpoch(
      ref.read(nowProvider)(),
    );
    final int? lastBackup = ref.watch(lastBackupAtProvider).value;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            PageHeader(
              eyebrow: '本 机 设 置',
              date: formatChineseYearMonth(now),
              title: '设置',
              subtitle: '身体、传感器与这一册的样貌',
            ),
            Divider(height: 1, color: palette.hairline),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: <Widget>[
                  const _GroupHeader('身 体', hint: '用于心率区间与功率估算'),
                  _SettingsRow(
                    key: const Key('settings-max-hr'),
                    label: '最大心率',
                    value: '${settings.maxHeartRate} bpm',
                    onTap: () => _editHeartRate(context, ref, settings),
                  ),
                  _SettingsRow(
                    key: const Key('settings-weight'),
                    label: '体重',
                    value: '${settings.weightKg.toStringAsFixed(1)} kg',
                    onTap: () => _editWeight(context, ref, settings),
                  ),
                  _SettingsRow(
                    key: const Key('settings-unit'),
                    label: '距离单位',
                    value: _unitLabel(settings.distanceUnit),
                    onTap: () => _editUnit(context, ref, settings),
                    showDivider: false,
                  ),
                  const _GroupHeader('传 感 器', hint: '点击配对'),
                  const _SensorSection(),
                  const _GroupHeader('地 图 与 外 观', hint: '点选即生效'),
                  _SettingsRow(
                    key: const Key('settings-tile'),
                    label: '地图瓦片',
                    value: _tileLabel(settings.mapTileUrlTemplate),
                    onTap: () => _editTileUrl(context, ref, settings),
                  ),
                  _ThemeSection(settings: settings),
                  const _GroupHeader('数 据', hint: '仅存本机'),
                  _SettingsRow(
                    key: const Key('settings-backup'),
                    label: '备份与恢复',
                    value: lastBackup == null
                        ? '导出 / 恢复'
                        : '上次 ${formatMonthDayDot(lastBackup)}',
                    onTap: () => _openBackup(context),
                    showDivider: false,
                  ),
                  const _GroupHeader('关 于'),
                  const _AboutRow(),
                  if (kDebugMode) ...<Widget>[
                    const SizedBox(height: kSpaceXl),
                    const _DebugSection(),
                  ],
                  const SizedBox(height: kSpaceXxl),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editHeartRate(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) async {
    final String? value = await _showTextSheet(
      context,
      title: '最大心率',
      helper: '用于心率区间划分，可参考 220 − 年龄',
      initial: '${settings.maxHeartRate}',
      label: '最大心率（bpm）',
      keyboardType: TextInputType.number,
      validate: (String text) {
        final int? hr = int.tryParse(text);
        if (hr == null ||
            hr < kMinPlausibleMaxHeartRate ||
            hr > kMaxPlausibleMaxHeartRate) {
          return '需要是 $kMinPlausibleMaxHeartRate~$kMaxPlausibleMaxHeartRate 之间的整数';
        }
        return null;
      },
    );
    if (value == null) return;
    await _save(ref, settings.copyWith(maxHeartRate: int.parse(value)));
  }

  Future<void> _editWeight(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) async {
    final String? value = await _showTextSheet(
      context,
      title: '体重',
      helper: '仅用于估算卡路里与功率，结果仅供参考',
      initial: settings.weightKg.toStringAsFixed(1),
      label: '体重（kg）',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validate: (String text) {
        final double? weight = double.tryParse(text);
        if (weight == null || weight <= 0) return '需要是大于 0 的数字';
        return null;
      },
    );
    if (value == null) return;
    await _save(ref, settings.copyWith(weightKg: double.parse(value)));
  }

  Future<void> _editTileUrl(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) async {
    final String? value = await _showTextSheet(
      context,
      title: '地图瓦片源',
      helper: '高德接口失效时可换成 OSM 或自建源，无需重新发版',
      initial: settings.mapTileUrlTemplate,
      label: '瓦片地址',
      keyboardType: TextInputType.url,
      validate: (String text) {
        if (text.isEmpty) return '瓦片源不能为空';
        final Uri? uri = Uri.tryParse(text);
        if (uri == null ||
            (uri.scheme != 'http' && uri.scheme != 'https') ||
            uri.host.isEmpty) {
          return '需要是 http(s) 地址';
        }
        return null;
      },
    );
    if (value == null) return;
    await _save(ref, settings.copyWith(mapTileUrlTemplate: value));
  }

  Future<void> _editUnit(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) async {
    final DistanceUnit? unit = await showPaperSheet<DistanceUnit>(
      context: context,
      builder: (BuildContext sheetContext) => PaperSheet(
        title: '距离单位',
        subtitle: '影响记录、历史与统计的读数',
        onClose: () => Navigator.of(sheetContext).pop(),
        child: Column(
          children: <Widget>[
            for (final DistanceUnit value in DistanceUnit.values)
              _ChoiceRow(
                key: Key('unit-${value.name}'),
                label: _unitLabel(value),
                selected: value == settings.distanceUnit,
                onTap: () => Navigator.of(sheetContext).pop(value),
              ),
          ],
        ),
      ),
    );
    if (unit == null || unit == settings.distanceUnit) return;
    await _save(ref, settings.copyWith(distanceUnit: unit));
  }

  Future<void> _openBackup(BuildContext context) => showPaperSheet<void>(
    context: context,
    builder: (BuildContext sheetContext) => PaperSheet(
      title: '备份与恢复',
      subtitle: '导出一份归档，或从归档恢复全部记录',
      onClose: () => Navigator.of(sheetContext).pop(),
      child: const BackupSection(showHeader: false),
    ),
  );

  Future<void> _save(WidgetRef ref, AppSettings settings) async {
    await ref.read(settingsRepositoryProvider).save(settings);
    ref.invalidate(appSettingsProvider);
  }

  static Future<String?> _showTextSheet(
    BuildContext context, {
    required String title,
    required String helper,
    required String initial,
    required String label,
    required TextInputType keyboardType,
    required String? Function(String) validate,
  }) => showPaperSheet<String>(
    context: context,
    builder: (BuildContext sheetContext) => PaperSheet(
      title: title,
      subtitle: helper,
      onClose: () => Navigator.of(sheetContext).pop(),
      child: _TextEditForm(
        initial: initial,
        label: label,
        keyboardType: keyboardType,
        validate: validate,
      ),
    ),
  );

  static String _unitLabel(DistanceUnit unit) =>
      unit == DistanceUnit.mile ? '英里' : '公里';

  static String _tileLabel(String url) {
    if (url == kDefaultMapTileUrlTemplate) return '高德 · 宣纸';
    final Uri? uri = Uri.tryParse(url);
    return uri != null && uri.host.isNotEmpty ? uri.host : '自定义源';
  }
}

/// 分组标题：疏排小标题 + 右侧说明。上方不需要线——上一行的底边线已经分隔。
class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.title, {this.hint});

  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kSpaceL, kSpaceXl, kSpaceL, kSpaceS),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: kLabelTextStyle.copyWith(
                color: palette.muted,
                letterSpacing: 2,
              ),
            ),
          ),
          if (hint != null)
            Text(
              hint!,
              style: kLabelTextStyle.copyWith(
                color: palette.muted,
                letterSpacing: 0,
              ),
            ),
        ],
      ),
    );
  }
}

/// 一行「标签 + 当前值 + 尖括号」。点开底部编辑面板。
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.label,
    required this.value,
    required this.onTap,
    this.showDivider = true,
    super.key,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Column(
      children: <Widget>[
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: kSpaceL,
              vertical: kSpaceM,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: kFontSubtitle,
                      color: palette.ink,
                    ),
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: kFontMeta,
                    color: palette.muted,
                    fontFeatures: kTabularFigures,
                  ),
                ),
                const SizedBox(width: kSpaceS),
                Icon(Icons.chevron_right, size: 18, color: palette.muted),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: kSpaceL,
            endIndent: kSpaceL,
            color: palette.hairline,
          ),
      ],
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow();

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kSpaceL, kSpaceM, kSpaceL, kSpaceM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '行迹 XINGJI · 1.0.0',
                  style: TextStyle(
                    fontSize: 12,
                    color: palette.muted,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              Text(
                '记录仅存本机',
                style: TextStyle(fontSize: 12, color: palette.muted),
              ),
            ],
          ),
          const SizedBox(height: kSpaceXs),
          Text(
            '地点与天气随记录保存在本机；查询会联网，不额外保存坐标。',
            key: const Key('settings-about-network'),
            style: TextStyle(fontSize: 12, color: palette.muted),
          ),
        ],
      ),
    );
  }
}

/// 主题色：四颗颜料点 + 名称，选中项带对勾与「当前 {颜料}」。
class _ThemeSection extends ConsumerWidget {
  const _ThemeSection({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppPalette palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(kSpaceL, kSpaceM, kSpaceL, 0),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '主题色',
                  style: TextStyle(fontSize: kFontSubtitle, color: palette.ink),
                ),
              ),
              Text(
                '当前 ${settings.accent.label}',
                style: TextStyle(fontSize: kFontMeta, color: palette.muted),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            kSpaceL,
            kSpaceS,
            kSpaceL,
            kSpaceM,
          ),
          child: Row(
            children: <Widget>[
              for (final ThemeAccent accent in ThemeAccent.values)
                Expanded(
                  child: _AccentDot(
                    key: Key('accent-${accent.dbValue}'),
                    accent: accent,
                    selected: accent == settings.accent,
                    onTap: () => _pick(ref, accent),
                  ),
                ),
            ],
          ),
        ),
        Divider(
          height: 1,
          indent: kSpaceL,
          endIndent: kSpaceL,
          color: palette.hairline,
        ),
      ],
    );
  }

  Future<void> _pick(WidgetRef ref, ThemeAccent accent) async {
    final AppSettings? current = ref.read(appSettingsProvider).value;
    if (current == null || current.accent == accent) return;
    await ref
        .read(settingsRepositoryProvider)
        .save(current.copyWith(accent: accent));
    ref.invalidate(appSettingsProvider);
  }
}

class _AccentDot extends StatelessWidget {
  const _AccentDot({
    required this.accent,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final ThemeAccent accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Semantics(
      label: accent.label,
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(kRadiusControl)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(kSpaceXs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.color,
                  border: Border.all(
                    color: selected ? palette.ink : palette.hairline,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: selected
                    ? Icon(Icons.check, size: 20, color: palette.onAccent)
                    : null,
              ),
              const SizedBox(height: kSpaceXs),
              Text(
                accent.label,
                style: kLabelTextStyle.copyWith(
                  color: selected ? palette.ink : palette.muted,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 传感器配对管理。三行：已连接显示设备名与状态/断开，未连接显示「+ 未连接」。
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

  Future<void> _connect(SensorKind kind) async {
    final DiscoveredDevice? device =
        await showModalBottomSheet<DiscoveredDevice>(
          context: context,
          builder: (BuildContext context) => DevicePickerSheet(kind: kind),
        );
    if (device == null) return;
    await ref
        .read(sensorPairingProvider)
        .save(kind, PairedSensor(id: device.device.id, name: device.name));
    await _reload();
  }

  Future<void> _clear(SensorKind kind) async {
    await ref.read(sensorPairingProvider).clear(kind);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: kSpaceL),
        child: SizedBox(
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    const Map<SensorKind, String> labels = <SensorKind, String>{
      SensorKind.heartRate: '心率',
      SensorKind.cadence: '踏频',
      SensorKind.power: '功率',
    };
    return Column(
      children: <Widget>[
        for (final SensorKind kind in SensorKind.values)
          _SensorRow(
            key: Key('sensor-${kind.name}'),
            label: labels[kind]!,
            paired: _paired[kind],
            onTap: _paired[kind] == null ? () => _connect(kind) : null,
            onDisconnect: _paired[kind] == null ? null : () => _clear(kind),
            showDivider: kind != SensorKind.power,
          ),
      ],
    );
  }
}

class _SensorRow extends StatelessWidget {
  const _SensorRow({
    required this.label,
    required this.paired,
    required this.onTap,
    required this.onDisconnect,
    required this.showDivider,
    super.key,
  });

  final String label;
  final PairedSensor? paired;
  final VoidCallback? onTap;
  final VoidCallback? onDisconnect;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final bool connected = paired != null;
    return Column(
      children: <Widget>[
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: kSpaceL,
              vertical: kSpaceM,
            ),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 60,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: kFontSubtitle,
                      color: palette.ink,
                    ),
                  ),
                ),
                Expanded(
                  child: Row(
                    children: <Widget>[
                      if (connected)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: palette.accentInk,
                          ),
                        )
                      else
                        Icon(Icons.add, size: 16, color: palette.accentInk),
                      const SizedBox(width: kSpaceS),
                      if (connected)
                        Flexible(
                          child: Text(
                            paired!.name.isEmpty ? paired!.id : paired!.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: kFontMeta,
                              color: palette.ink,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (connected) ...<Widget>[
                  Text(
                    '已连接',
                    style: TextStyle(
                      fontSize: kFontMeta,
                      color: palette.accentInk,
                    ),
                  ),
                  TextButton(
                    onPressed: onDisconnect,
                    style: TextButton.styleFrom(
                      foregroundColor: palette.muted,
                      minimumSize: const Size(44, 44),
                      padding: const EdgeInsets.symmetric(horizontal: kSpaceS),
                    ),
                    child: const Text('断开'),
                  ),
                ] else ...<Widget>[
                  Text(
                    '未连接',
                    style: TextStyle(fontSize: kFontMeta, color: palette.muted),
                  ),
                  const SizedBox(width: kSpaceXs),
                  Icon(Icons.chevron_right, size: 18, color: palette.muted),
                ],
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: kSpaceL,
            endIndent: kSpaceL,
            color: palette.hairline,
          ),
      ],
    );
  }
}

/// 编辑面板里的输入 + 保存。校验失败时留在面板内显示错误。
class _TextEditForm extends StatefulWidget {
  const _TextEditForm({
    required this.initial,
    required this.label,
    required this.keyboardType,
    required this.validate,
  });

  final String initial;
  final String label;
  final TextInputType keyboardType;
  final String? Function(String) validate;

  @override
  State<_TextEditForm> createState() => _TextEditFormState();
}

class _TextEditFormState extends State<_TextEditForm> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final String text = _controller.text.trim();
    final String? error = widget.validate(text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: widget.keyboardType,
        decoration: InputDecoration(labelText: widget.label, errorText: _error),
        onSubmitted: (_) => _submit(),
      ),
      const SizedBox(height: kSpaceL),
      SizedBox(
        height: 52,
        child: FilledButton(onPressed: _submit, child: const Text('保存')),
      ),
    ],
  );
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: kSpaceM),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: kFontSubtitle, color: palette.ink),
              ),
            ),
            if (selected) Icon(Icons.check, size: 20, color: palette.accentInk),
          ],
        ),
      ),
    );
  }
}

/// 调试区块：只在 debug 构建里出现（见 `kDebugMode`）。
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
            '铺 $_seedCount 条模拟记录，跨最近两个半月，'
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
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.palette.danger,
                  ),
                  child: const Text('清空全部记录'),
                ),
              ),
            ],
          ),
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(kSpaceL, kSpaceM, kSpaceL, 0),
            child: Text(
              _message!,
              style: kMutedTextStyle.copyWith(fontSize: 13),
            ),
          ),
      ],
    );
  }

  Future<void> _seed() async {
    final bool ok = await _confirm(
      title: '生成 $_seedCount 条模拟记录？',
      body:
          '会在最近两个半月里铺一批假记录，走的是和真实记录一样的写入路径。'
          '上次生成的模拟记录会被覆盖成同一批（不会越点越多），真实记录不动。',
      action: '生成',
    );
    if (!ok) return;

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final int count = await seedMockWorkouts(
        ref.read(workoutRepositoryProvider),
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
      body: '会删除全部运动记录，包括真实记录和模拟记录。这一步无法撤销。',
      action: '清空',
    );
    if (!ok) return;

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final int count = await deleteAllWorkouts(
        ref.read(workoutRepositoryProvider),
      );
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
