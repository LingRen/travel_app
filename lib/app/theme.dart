import 'package:flutter/material.dart';

import '../data/settings_repository.dart';

// ─────────────────────────────────────────────────────────────────────────
// 纸本令牌
//
// 行迹只有一套亮色纸本主题：纸色承担背景，墨色承担正文与读数，发丝线承担
// 分区，主题颜料只出现在「正在发生 / 可交互 / 已选中」与轨迹上。页面不再
// 使用阴影与抬升来表达层级——纸上的分区是一条线或一段留白。
//
// 颜色分两层：`kApp*` 常量是过渡期兼容名，值已指向纸本令牌；新代码一律通过
// `context.palette` 读取语义名，主题色切换时整树重着色。
// ─────────────────────────────────────────────────────────────────────────

/// 纸底。
const Color kPaper = Color(0xFFF5F0E5);

/// 纸面：输入框、面板、卡片这类比纸底略亮的表面。
const Color kSheet = Color(0xFFFCF9F2);

/// 墨：正文与主读数。
const Color kInk = Color(0xFF1D1B17);

/// 次级墨：标签、说明、未选中态。
const Color kMutedInk = Color(0xFF746D60);

/// 发丝线：只用于分区，不用阴影代替。
const Color kHairlineColor = Color(0xFFD8CEBB);

/// 抬高一层的纸面：旧页面里的嵌套面板、按压态。
const Color kPaperRaised = Color(0xFFEFE8DA);

// 过渡期兼容名。旧页面仍直接引用这些常量；值已切换到纸本，避免一次改完
// 所有页面才能编译。新代码不要再用 `kApp*`。
const Color kAppBackground = kPaper;
const Color kAppSurface = kSheet;
const Color kAppSurfaceRaised = kPaperRaised;
const Color kAppHairline = kHairlineColor;
const Color kAppTextPrimary = kInk;
const Color kAppTextMuted = kMutedInk;
const Color kAppOnAccent = kPaper;

/// 警告：GPS 弱、传感器断开。深琥珀在纸底上仍有 7.6:1，并与藤黄文字色
/// 靠明度拉开距离。
const Color kAppWarning = Color(0xFF6B4300);

/// 危险：结束记录、解除配对、清空数据。
const Color kAppDanger = Color(0xFF8C1D18);

/// 危险色上的纸色字。
const Color kAppOnDanger = kPaper;

/// 运行时可变的纸本令牌。挂在 [ThemeData.extensions] 上，widget 通过
/// `context.palette` 读取——主题色不再是编译期常量，切主题即整树重着色。
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.paper,
    required this.sheet,
    required this.ink,
    required this.muted,
    required this.hairline,
    required this.accent,
    required this.accentInk,
    required this.warning,
    required this.danger,
  });

  /// 纸底。
  final Color paper;

  /// 纸面。
  final Color sheet;

  /// 正文与主读数。
  final Color ink;

  /// 次级文字与标签。
  final Color muted;

  /// 发丝线。
  final Color hairline;

  /// 原始颜料：色点、大面积标记。
  final Color accent;

  /// 文字安全色：文字、图标、按钮、选中态、轨迹与图表线。
  final Color accentInk;

  /// 警告。
  final Color warning;

  /// 危险。
  final Color danger;

  /// 强调色上的文字色。
  Color get onAccent => paper;

  @override
  AppPalette copyWith({
    Color? paper,
    Color? sheet,
    Color? ink,
    Color? muted,
    Color? hairline,
    Color? accent,
    Color? accentInk,
    Color? warning,
    Color? danger,
  }) =>
      AppPalette(
        paper: paper ?? this.paper,
        sheet: sheet ?? this.sheet,
        ink: ink ?? this.ink,
        muted: muted ?? this.muted,
        hairline: hairline ?? this.hairline,
        accent: accent ?? this.accent,
        accentInk: accentInk ?? this.accentInk,
        warning: warning ?? this.warning,
        danger: danger ?? this.danger,
      );

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      paper: Color.lerp(paper, other.paper, t)!,
      sheet: Color.lerp(sheet, other.sheet, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentInk: Color.lerp(accentInk, other.accentInk, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

/// 便捷读取当前纸本令牌。
extension AppPaletteContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}

// ─────────────────────────────────────────────────────────────────────────
// 地图轨迹
// ─────────────────────────────────────────────────────────────────────────

/// 轨迹线的描边色。纸色底图上仍用墨色描边把主题色轨迹剥出来。
const Color kRouteCasing = Color(0xCC1D1B17);

/// 轨迹线宽。骑行界面是整页地图，4pt 骑行中扫一眼就滑过去了。
const double kRouteStrokeWidth = 5;

/// 轨迹描边宽（整圈，两侧各占一半）。
const double kRouteCasingWidth = 3;

/// 瓦片降饱和矩阵：保留 55% 饱和度，再轻微提亮，配合纸色薄罩使用。
const List<double> kMapTileColorMatrix = <double>[
  0.6457, 0.3218, 0.0325, 0, 6,
  0.0957, 0.8718, 0.0325, 0, 3,
  0.0957, 0.3218, 0.5825, 0, -4,
  0, 0, 0, 1, 0,
];

// ─────────────────────────────────────────────────────────────────────────
// 字体
//
// 标题衬线、正文无衬线、数据等宽。不打包中文字体，全部走平台回退链；
// 数字一律启用 tabular figures，实时读数不会随位数变化横向抖动。
// ─────────────────────────────────────────────────────────────────────────

/// 标题衬线字体栈。
const String kSerifFamily = 'Noto Serif SC';
const List<String> kSerifFallback = <String>[
  'Songti SC',
  'Noto Serif CJK SC',
  'serif',
];

/// 正文无衬线字体栈。
const String kSansFamily = 'Noto Sans SC';
const List<String> kSansFallback = <String>[
  'PingFang SC',
  'Noto Sans CJK SC',
  'sans-serif',
];

/// 数据等宽字体栈。
const String kMonoFamily = 'IBM Plex Mono';
const List<String> kMonoFallback = <String>['Menlo', 'Courier New', 'monospace'];

/// 等宽数字的字形特性。只影响数字，字母标点不受影响。
const List<FontFeature> kTabularFigures = <FontFeature>[
  FontFeature.tabularFigures(),
];

/// 车把模式主指标字号。设计文档 10.1 只要求 ≥72；取 120 是因为骑到 30km/h
/// 时瞄屏幕只有约 200ms，字号是唯一能把「一步扫读」做出来的杠杆。
const double kInstrumentNumeralSize = 120;

/// 字号刻度。所有文本走这里，不再往 widget 里塞 13 / 15 / 26 这类魔数。
const double kFontLabel = 11;
const double kFontMeta = 13;
const double kFontBody = 14;
const double kFontSubtitle = 15;
const double kFontTitle = 20;
const double kFontMetric = 26;
const double kFontPageTitle = 34;
const double kFontDisplay = 56;

/// 标签：小号疏排。中文没有大小写，英文标签保持句首大写。
const TextStyle kLabelTextStyle = TextStyle(
  fontFamily: kSansFamily,
  fontFamilyFallback: kSansFallback,
  fontSize: kFontLabel,
  fontWeight: FontWeight.w500,
  letterSpacing: 1.4,
  height: 1.4,
  color: kMutedInk,
);

/// 页面大标题：衬线。
const TextStyle kPageTitleTextStyle = TextStyle(
  fontFamily: kSerifFamily,
  fontFamilyFallback: kSerifFallback,
  fontSize: kFontPageTitle,
  fontWeight: FontWeight.w600,
  letterSpacing: 2,
  height: 1.2,
  color: kInk,
);

/// 区块衬线标题。
const TextStyle kSerifHeadingTextStyle = TextStyle(
  fontFamily: kSerifFamily,
  fontFamilyFallback: kSerifFallback,
  fontSize: 22,
  fontWeight: FontWeight.w600,
  height: 1.3,
  color: kInk,
);

/// 静态大数字：历史距离、详情汇总、统计累计。衬线，接近设计稿的 Bodoni 观感。
const TextStyle kSerifDisplayTextStyle = TextStyle(
  fontFamily: kSerifFamily,
  fontFamilyFallback: kSerifFallback,
  fontSize: kFontDisplay,
  fontWeight: FontWeight.w500,
  height: 1.05,
  letterSpacing: 1,
  color: kInk,
);

/// 仪表读数：车把模式的主数字。
const TextStyle kInstrumentTextStyle = TextStyle(
  fontFamily: kMonoFamily,
  fontFamilyFallback: kMonoFallback,
  fontSize: kInstrumentNumeralSize,
  fontWeight: FontWeight.w700,
  height: 1.0,
  letterSpacing: -2,
  color: kInk,
  fontFeatures: kTabularFigures,
);

/// 中号数字：卡片主数值、汇总指标。
const TextStyle kMetricTextStyle = TextStyle(
  fontFamily: kMonoFamily,
  fontFamilyFallback: kMonoFallback,
  fontSize: kFontMetric,
  fontWeight: FontWeight.w700,
  height: 1.1,
  letterSpacing: -0.5,
  color: kInk,
  fontFeatures: kTabularFigures,
);

/// 大号数字：未完赛结算、个人最佳这类一次性读数。
const TextStyle kDisplayTextStyle = TextStyle(
  fontFamily: kMonoFamily,
  fontFamilyFallback: kMonoFallback,
  fontSize: kFontDisplay,
  fontWeight: FontWeight.w700,
  height: 1.0,
  letterSpacing: -1,
  color: kInk,
  fontFeatures: kTabularFigures,
);

/// 区块标题。
const TextStyle kSectionTextStyle = TextStyle(
  fontFamily: kSansFamily,
  fontFamilyFallback: kSansFallback,
  fontSize: kFontSubtitle,
  fontWeight: FontWeight.w600,
  color: kInk,
);

/// 正文。
const TextStyle kBodyTextStyle = TextStyle(
  fontFamily: kSansFamily,
  fontFamilyFallback: kSansFallback,
  fontSize: kFontBody,
  height: 1.5,
  color: kInk,
);

/// 次级正文。
const TextStyle kMutedTextStyle = TextStyle(
  fontFamily: kSansFamily,
  fontFamilyFallback: kSansFallback,
  fontSize: kFontBody,
  height: 1.5,
  color: kMutedInk,
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

/// 印章与按钮。
const double kRadiusSeal = 3;
const double kRadiusButton = 3;

/// 面板。纸本不再用大圆角卡片。
const double kRadiusPanel = 3;

/// 控件：按钮、输入框。
const double kRadiusControl = 3;

/// 底部面板只圆上方两角。
const double kRadiusSheet = 18;

/// 1 像素结构线。用 [BorderSide] 而不是 [Divider] 的地方都该用它。
const BorderSide kHairline = BorderSide(color: kHairlineColor, width: 1);

ThemeData buildAppTheme([ThemeAccent accent = ThemeAccent.cinnabar]) {
  final Color accentInk = accent.inkColor;
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: accentInk,
    brightness: Brightness.light,
  ).copyWith(
    primary: accentInk,
    onPrimary: kPaper,
    primaryContainer: accentInk.withValues(alpha: 0.12),
    onPrimaryContainer: accentInk,
    secondary: accentInk,
    onSecondary: kPaper,
    error: kAppDanger,
    onError: kPaper,
    errorContainer: kAppDanger.withValues(alpha: 0.12),
    onErrorContainer: kAppDanger,
    surface: kSheet,
    onSurface: kInk,
    surfaceDim: kPaper,
    surfaceBright: kSheet,
    surfaceContainerLowest: kSheet,
    surfaceContainerLow: kSheet,
    surfaceContainer: kSheet,
    surfaceContainerHigh: kPaperRaised,
    surfaceContainerHighest: kPaperRaised,
    onSurfaceVariant: kMutedInk,
    outline: kHairlineColor,
    outlineVariant: kHairlineColor,
    surfaceTint: Colors.transparent,
    inverseSurface: kInk,
    onInverseSurface: kPaper,
    inversePrimary: accentInk,
    scrim: kInk.withValues(alpha: 0.4),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: kPaper,
    canvasColor: kPaper,
    dividerColor: kHairlineColor,
    extensions: <ThemeExtension<dynamic>>[
      AppPalette(
        paper: kPaper,
        sheet: kSheet,
        ink: kInk,
        muted: kMutedInk,
        hairline: kHairlineColor,
        accent: accent.color,
        accentInk: accentInk,
        warning: kAppWarning,
        danger: kAppDanger,
      ),
    ],
    textTheme: const TextTheme(
      displayLarge: kSerifDisplayTextStyle,
      displayMedium: kSerifDisplayTextStyle,
      displaySmall: kSerifHeadingTextStyle,
      headlineMedium: kPageTitleTextStyle,
      headlineSmall: kSerifHeadingTextStyle,
      titleLarge: kSerifHeadingTextStyle,
      titleMedium: kSectionTextStyle,
      bodyLarge: kBodyTextStyle,
      bodyMedium: kBodyTextStyle,
      bodySmall: TextStyle(
        fontFamily: kSansFamily,
        fontFamilyFallback: kSansFallback,
        fontSize: 12,
        height: 1.5,
        color: kMutedInk,
      ),
      labelLarge: TextStyle(
        fontFamily: kSansFamily,
        fontFamilyFallback: kSansFallback,
        fontSize: kFontBody,
        fontWeight: FontWeight.w600,
        color: kInk,
      ),
      labelMedium: kLabelTextStyle,
      labelSmall: kLabelTextStyle,
    ),
    iconTheme: const IconThemeData(color: kInk),
    dividerTheme: const DividerThemeData(
      color: kHairlineColor,
      thickness: 1,
      space: 1,
    ),
    // 旧页面仍在使用 AppBar；纸本版式会逐步换成 PageHeader。
    appBarTheme: const AppBarTheme(
      backgroundColor: kPaper,
      surfaceTintColor: Colors.transparent,
      foregroundColor: kInk,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: kSerifFamily,
        fontFamilyFallback: kSerifFallback,
        fontSize: kFontTitle,
        fontWeight: FontWeight.w600,
        color: kInk,
      ),
      shape: Border(bottom: kHairline),
    ),
    // 旧外壳仍用 NavigationBar；阶段一结束会换成 PaperNavBar。
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: kSheet,
      surfaceTintColor: Colors.transparent,
      indicatorColor: accentInk.withValues(alpha: 0.10),
      indicatorShape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(kRadiusLine)),
      ),
      elevation: 0,
      height: 58,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith(
        (Set<WidgetState> states) => IconThemeData(
          size: 20,
          color: states.contains(WidgetState.selected) ? accentInk : kMutedInk,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (Set<WidgetState> states) => TextStyle(
          fontFamily: kSansFamily,
          fontFamilyFallback: kSansFallback,
          fontSize: 10,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.4,
          color: states.contains(WidgetState.selected) ? accentInk : kMutedInk,
        ),
      ),
    ),
    cardTheme: const CardThemeData(
      color: kSheet,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(kRadiusPanel)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accentInk,
        foregroundColor: kPaper,
        disabledBackgroundColor: kPaperRaised,
        disabledForegroundColor: kMutedInk,
        elevation: 0,
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: kSpaceXl),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(kRadiusControl)),
        ),
        textStyle: const TextStyle(
          fontFamily: kSansFamily,
          fontFamilyFallback: kSansFallback,
          fontSize: kFontSubtitle,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kInk,
        disabledForegroundColor: kMutedInk,
        side: kHairline,
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: kSpaceL),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(kRadiusControl)),
        ),
        textStyle: const TextStyle(
          fontFamily: kSansFamily,
          fontFamilyFallback: kSansFallback,
          fontSize: kFontBody,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accentInk,
        textStyle: const TextStyle(
          fontFamily: kSansFamily,
          fontFamilyFallback: kSansFallback,
          fontSize: kFontBody,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? accentInk
              : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? kPaper
              : kMutedInk,
        ),
        side: const WidgetStatePropertyAll<BorderSide>(kHairline),
        shape: const WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(kRadiusControl)),
          ),
        ),
        textStyle: const WidgetStatePropertyAll<TextStyle>(
          TextStyle(
            fontFamily: kSansFamily,
            fontFamilyFallback: kSansFallback,
            fontSize: kFontBody,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kSheet,
      labelStyle: kMutedTextStyle,
      floatingLabelStyle: TextStyle(color: accentInk),
      helperStyle: const TextStyle(
        fontFamily: kSansFamily,
        fontFamilyFallback: kSansFallback,
        fontSize: 12,
        color: kMutedInk,
      ),
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
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(kRadiusControl)),
        borderSide: BorderSide(color: accentInk, width: 1.5),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: kInk,
      contentTextStyle: TextStyle(
        fontFamily: kSansFamily,
        fontFamilyFallback: kSansFallback,
        fontSize: kFontBody,
        color: kPaper,
      ),
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(kRadiusPanel)),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: kSheet,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(kRadiusPanel)),
      ),
      titleTextStyle: TextStyle(
        fontFamily: kSerifFamily,
        fontFamilyFallback: kSerifFallback,
        fontSize: kFontTitle,
        fontWeight: FontWeight.w600,
        color: kInk,
      ),
      contentTextStyle: kMutedTextStyle,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: kSheet,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: kSheet,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kRadiusSheet)),
      ),
      dragHandleColor: kHairlineColor,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: kMutedInk,
      textColor: kInk,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: accentInk),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: accentInk,
      selectionColor: accentInk.withValues(alpha: 0.20),
      selectionHandleColor: accentInk,
    ),
    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(
        color: kInk,
        borderRadius: BorderRadius.all(Radius.circular(kRadiusPanel)),
      ),
      textStyle: TextStyle(
        fontFamily: kSansFamily,
        fontFamilyFallback: kSansFallback,
        fontSize: 12,
        color: kPaper,
      ),
    ),
  );
}
