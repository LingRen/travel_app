import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────
// 颜色
//
// 冷调沥青石墨。饱和度在这个 app 里是稀缺资源：屏幕上唯一允许带颜色的东西
// 是数据本身——速度色带（黄→橙→深红，见 domain/analysis/color_scale.dart）
// 与心率区间色（见 features/detail/hr_zone_bar.dart）。装饰一律不上色，
// 所以分区靠细线而不靠色块与阴影。
//
// 琥珀只承担一个语义：**正在发生**（记录中 / 可交互 / 已选中）。
// ─────────────────────────────────────────────────────────────────────────

/// 沥青底色。
const Color kAppBackground = Color(0xFF0B0E12);

/// 面板底色：卡片、输入框、底栏。
const Color kAppSurface = Color(0xFF141A21);

/// 抬高一层：嵌套面板、按压态、模态表面。
const Color kAppSurfaceRaised = Color(0xFF1D252E);

/// 结构细线。分区靠它，不靠阴影。
const Color kAppHairline = Color(0xFF2A343F);

/// 正文色。用冷白而不是纯白：纯白在户外强光下会晕开，笔画边界反而糊掉。
const Color kAppTextPrimary = Color(0xFFE8EDF2);

/// 次级文字与标签。
const Color kAppTextMuted = Color(0xFF8A97A6);

/// 琥珀：正在发生 / 可交互。与底色对比度约 10:1，强光下也站得住。
const Color kAppAccent = Color(0xFFFFA92B);

/// 琥珀上的墨色。
const Color kAppOnAccent = Color(0xFF0B0E12);

/// 淡金：降级提示（GPS 弱、传感器断开）。与琥珀的区别在于语义是「在提醒你」
/// 而不是「在等你操作」，同屏出现时靠明度差（13:1 vs 10:1）区分。
const Color kAppWarning = Color(0xFFFFD166);

/// 危险：结束记录、解除配对、清空数据。
const Color kAppDanger = Color(0xFFFF5A4E);

/// 危险色上的墨色。
const Color kAppOnDanger = Color(0xFF1A0806);

// ─────────────────────────────────────────────────────────────────────────
// 字体
//
// 数字一律等宽 + tabular figures。这不是审美取舍而是功能要求：码表上的速度
// 每 200ms 更新一次，比例数字的宽度随位数变化，读数会在横向抖动，瞄一眼反而
// 更费劲。等宽数字保证「2」跳成「18」时整数位不移动。
//
// 不打包自定义字体：这是个离线 app，用系统的等宽家族（Android 上是
// Roboto Mono / Droid Sans Mono），新增字体资产不值得。
// ─────────────────────────────────────────────────────────────────────────

/// 系统等宽家族。
const String kMonoFamily = 'monospace';

/// 等宽数字的字形特性。只影响数字，字母标点不受影响。
const List<FontFeature> kTabularFigures = <FontFeature>[
  FontFeature.tabularFigures(),
];

/// 车把模式主指标字号。设计文档 10.1 只要求 ≥72；取 120 是因为骑到 30km/h
/// 时瞄屏幕只有约 200ms，字号是唯一能把「一步扫读」做出来的杠杆。
const double kInstrumentNumeralSize = 120;

/// 字号刻度。所有文本走这里，不再往 widget 里塞 13 / 15 / 26 这类魔数。
const double kFontLabel = 11;
const double kFontBody = 14;
const double kFontSubtitle = 15;
const double kFontTitle = 20;
const double kFontMetric = 26;
const double kFontDisplay = 56;

/// 标签：小号疏排。刻意不用全大写——中文没有大小写，英文标签跟着保持句首
/// 大写即可，全大写标签是模板页的通病。
const TextStyle kLabelTextStyle = TextStyle(
  fontSize: kFontLabel,
  fontWeight: FontWeight.w500,
  letterSpacing: 0.6,
  color: kAppTextMuted,
);

/// 仪表读数：车把模式的主数字。
const TextStyle kInstrumentTextStyle = TextStyle(
  fontFamily: kMonoFamily,
  fontSize: kInstrumentNumeralSize,
  fontWeight: FontWeight.w700,
  height: 1.0,
  letterSpacing: -2,
  color: kAppTextPrimary,
  fontFeatures: kTabularFigures,
);

/// 中号数字：卡片主数值、汇总指标。
const TextStyle kMetricTextStyle = TextStyle(
  fontFamily: kMonoFamily,
  fontSize: kFontMetric,
  fontWeight: FontWeight.w700,
  height: 1.1,
  letterSpacing: -0.5,
  color: kAppTextPrimary,
  fontFeatures: kTabularFigures,
);

/// 大号数字：未完赛结算、个人最佳这类一次性读数。
const TextStyle kDisplayTextStyle = TextStyle(
  fontFamily: kMonoFamily,
  fontSize: kFontDisplay,
  fontWeight: FontWeight.w700,
  height: 1.0,
  letterSpacing: -1,
  color: kAppTextPrimary,
  fontFeatures: kTabularFigures,
);

/// 区块标题。
const TextStyle kSectionTextStyle = TextStyle(
  fontSize: kFontSubtitle,
  fontWeight: FontWeight.w600,
  color: kAppTextPrimary,
);

/// 正文。
const TextStyle kBodyTextStyle = TextStyle(
  fontSize: kFontBody,
  color: kAppTextPrimary,
);

/// 次级正文。
const TextStyle kMutedTextStyle = TextStyle(
  fontSize: kFontBody,
  color: kAppTextMuted,
);

// ─────────────────────────────────────────────────────────────────────────
// 间距与圆角
// ─────────────────────────────────────────────────────────────────────────

const double kSpaceXs = 4;
const double kSpaceS = 8;
const double kSpaceM = 12;
const double kSpaceL = 16;
const double kSpaceXl = 24;
const double kSpaceXxl = 32;

/// 细线元素（刻度、分隔）用的近直角。
const double kRadiusLine = 2;

/// 面板。
const double kRadiusPanel = 6;

/// 控件：按钮、输入框、sheet。
const double kRadiusControl = 10;

/// 1 像素结构线。用 [BorderSide] 而不是 [Divider] 的地方都该用它。
const BorderSide kHairline = BorderSide(color: kAppHairline, width: 1);

ThemeData buildAppTheme() {
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: kAppAccent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: kAppAccent,
    onPrimary: kAppOnAccent,
    secondary: kAppAccent,
    onSecondary: kAppOnAccent,
    error: kAppDanger,
    onError: kAppOnDanger,
    surface: kAppSurface,
    onSurface: kAppTextPrimary,
    surfaceContainerHighest: kAppSurfaceRaised,
    onSurfaceVariant: kAppTextMuted,
    outline: kAppHairline,
    outlineVariant: kAppHairline,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: kAppBackground,
    textTheme: const TextTheme(
      titleMedium: TextStyle(
        fontSize: kFontSubtitle,
        fontWeight: FontWeight.w600,
        color: kAppTextPrimary,
      ),
      bodyMedium: kBodyTextStyle,
      bodySmall: TextStyle(fontSize: 12, color: kAppTextMuted),
      labelSmall: kLabelTextStyle,
    ),
    dividerTheme: const DividerThemeData(
      color: kAppHairline,
      thickness: 1,
      space: 1,
    ),
    // 顶栏做成器件边框而不是 Material 的彩色 header：无阴影、无色调叠加，
    // 只留一条底部细线把「边框」和「面板」分开。
    appBarTheme: const AppBarTheme(
      backgroundColor: kAppBackground,
      surfaceTintColor: Colors.transparent,
      foregroundColor: kAppTextPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: kFontTitle,
        fontWeight: FontWeight.w600,
        color: kAppTextPrimary,
      ),
      shape: Border(bottom: kHairline),
    ),
    // 选中态用琥珀，与主题色一致。琥珀在令牌层写的语义就是「正在发生 /
    // 可交互 / 已选中」（见文首），底栏选中态本来就是它该占的位置；此前
    // 为了把颜色全留给数据而让底栏走中性色，收敛过头了。未选中仍是次级灰，
    // 抬高面板继续承担形状上的区分，颜色只负责「哪个被选中」。
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: kAppSurface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: kAppSurfaceRaised,
      indicatorShape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(kRadiusLine)),
      ),
      elevation: 0,
      height: 64,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith(
        (Set<WidgetState> states) => IconThemeData(
          size: 22,
          color: states.contains(WidgetState.selected)
              ? kAppAccent
              : kAppTextMuted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (Set<WidgetState> states) => TextStyle(
          fontSize: kFontLabel,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.4,
          color: states.contains(WidgetState.selected)
              ? kAppAccent
              : kAppTextMuted,
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: kAppSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(kRadiusPanel)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kAppAccent,
        foregroundColor: kAppOnAccent,
        disabledBackgroundColor: kAppSurfaceRaised,
        disabledForegroundColor: kAppTextMuted,
        elevation: 0,
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: kSpaceXl),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(kRadiusControl)),
        ),
        textStyle: const TextStyle(fontSize: kFontSubtitle, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kAppTextPrimary,
        disabledForegroundColor: kAppTextMuted,
        side: kHairline,
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: kSpaceL),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(kRadiusControl)),
        ),
        textStyle: const TextStyle(fontSize: kFontBody, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: kAppAccent,
        textStyle: const TextStyle(fontSize: kFontBody, fontWeight: FontWeight.w600),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? kAppAccent
              : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? kAppOnAccent
              : kAppTextMuted,
        ),
        side: const WidgetStatePropertyAll<BorderSide>(kHairline),
        shape: const WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(kRadiusControl)),
          ),
        ),
        textStyle: const WidgetStatePropertyAll<TextStyle>(
          TextStyle(fontSize: kFontBody, fontWeight: FontWeight.w600),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kAppSurface,
      labelStyle: kMutedTextStyle,
      floatingLabelStyle: const TextStyle(color: kAppAccent),
      helperStyle: const TextStyle(fontSize: 12, color: kAppTextMuted),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: kSpaceM,
        vertical: kSpaceM,
      ),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(kRadiusControl)),
        borderSide: kHairline,
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(kRadiusControl)),
        borderSide: kHairline,
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(kRadiusControl)),
        borderSide: BorderSide(color: kAppAccent, width: 1.5),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: kAppSurfaceRaised,
      contentTextStyle: kBodyTextStyle,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: kAppSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(kRadiusPanel)),
      ),
      titleTextStyle: TextStyle(
        fontSize: kFontSubtitle,
        fontWeight: FontWeight.w600,
        color: kAppTextPrimary,
      ),
      contentTextStyle: kMutedTextStyle,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: kAppSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kRadiusControl)),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: kAppTextMuted,
      textColor: kAppTextPrimary,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: kAppAccent,
    ),
  );
}