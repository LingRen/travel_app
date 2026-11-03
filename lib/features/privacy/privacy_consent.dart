import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';

/// 高德开放平台隐私政策地址。弹窗里的入口与文案集中在这里，便于审查。
const String kAmapPrivacyPolicyUrl = 'https://lbs.amap.com/pages/privacy/';

/// 地图隐私同意网关。
///
/// 高德 SDK 要求 `hasContains` / `hasShow` / `hasAgree` 全为 true 才能正常出图。
/// 未同意前这里**不创建** [child]（原生地图平台视图），只显示 [fallback]
/// （legacy 栅格或纸色占位），记录功能照常可用。
///
/// 同意状态写入设置库；选择「暂不使用」只在本次运行内不再弹窗，不落库。
class AmapPrivacyGate extends ConsumerStatefulWidget {
  const AmapPrivacyGate({
    required this.child,
    required this.fallback,
    super.key,
  });

  /// 同意后展示的原生地图体。
  final Widget child;

  /// 未同意 / 读取中使用的回落内容。应当是一张可用的 legacy 地图。
  final Widget fallback;

  @override
  ConsumerState<AmapPrivacyGate> createState() => _AmapPrivacyGateState();
}

class _AmapPrivacyGateState extends ConsumerState<AmapPrivacyGate> {
  /// 本会话已拒绝，不再重复弹窗。下次冷启动会重新询问。
  bool _declinedThisSession = false;

  /// 防止同一帧重复安排弹窗。
  bool _prompting = false;

  /// 本次会话已点「同意」。数据库写入与 provider 刷新有时间差，用这个标记
  /// 立即切到原生底图，避免刷新期间被当成「未同意」再弹一次。
  bool _agreedThisSession = false;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<bool> agreed = ref.watch(mapPrivacyConsentProvider);
    if (agreed.value == true || _agreedThisSession) return widget.child;

    // 读取完成且明确未同意时才询问；加载中先保持回落底图。
    if (agreed.hasValue && !_declinedThisSession && !_prompting) {
      _prompting = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _askConsent());
    }
    return widget.fallback;
  }

  Future<void> _askConsent() async {
    if (!mounted) {
      _prompting = false;
      return;
    }
    final bool? agreed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => const _AmapPrivacyDialog(),
    );
    _prompting = false;
    if (!mounted) return;
    if (agreed ?? false) {
      setState(() => _agreedThisSession = true);
      await ref.read(settingsRepositoryProvider).grantAmapPrivacyConsent();
      ref.invalidate(mapPrivacyConsentProvider);
    } else {
      setState(() => _declinedThisSession = true);
    }
  }
}

class _AmapPrivacyDialog extends StatelessWidget {
  const _AmapPrivacyDialog();

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return AlertDialog(
      key: const Key('amap-privacy-dialog'),
      title: const Text('地图服务说明'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              '纸本骑行使用高德地图 SDK 显示底图。使用期间会向高德服务器请求地图数据，'
              '可能产生网络流量；你的骑行轨迹与记录仍只保存在本机，不会上传。',
            ),
            const SizedBox(height: kSpaceS),
            const Text(
              '同意后才能加载原生底图；选择「暂不使用」会继续使用内置栅格地图，'
              '记录、统计与导出都不受影响。',
            ),
            const SizedBox(height: kSpaceS),
            TextButton(
              key: const Key('amap-privacy-policy'),
              onPressed: () => launchUrl(
                Uri.parse(kAmapPrivacyPolicyUrl),
                mode: LaunchMode.externalApplication,
              ),
              child: Text(
                '查看《高德隐私政策》',
                style: TextStyle(color: palette.accentInk),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('amap-privacy-decline'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('暂不使用'),
        ),
        FilledButton(
          key: const Key('amap-privacy-agree'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('同意'),
        ),
      ],
    );
  }
}
