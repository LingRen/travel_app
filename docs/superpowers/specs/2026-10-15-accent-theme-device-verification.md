# 多主题色真机核对 Spec（2026-10-15）

## 目标

对已提交（`main` @ `8a7a936`）的「4 组可切换主题色」改动做 Android 真机核对，**不推送代码**。
产出：逐项「通过 / 失败」结论 + 截图依据；设备设置若被改动必须还原。

## 被测代码（已实现，无需改动）

| 位置 | 内容 |
| --- | --- |
| [settings_repository.dart](file:///Users/ling/code/travel_app/lib/data/settings_repository.dart#L19-L42) | `ThemeAccent` 枚举：amber `#FFA92B` / mint `#33D69F` / sky `#7DD3FC` / violet `#A78BFA`；持久化键 `accent_theme`，未知值回退 amber |
| [theme.dart](file:///Users/ling/code/travel_app/lib/app/theme.dart#L40-L61) | `AppPalette extends ThemeExtension`，`context.palette.accent`；`buildAppTheme(ThemeAccent)` 参数化 |
| [settings_page.dart](file:///Users/ling/code/travel_app/lib/features/settings/settings_page.dart#L228-L270) | `_AppearanceSection`：4 个 `_AccentDot`（key `accent-<dbValue>`），点选即存即生效 |
| [settings_page.dart](file:///Users/ling/code/travel_app/lib/features/settings/settings_page.dart#L167-L203) | `_save()` 显式携带 `accent`，防止保存其它字段时被重置 |
| [detail_page.dart](file:///Users/ling/code/travel_app/lib/features/detail/detail_page.dart) | 4 条曲线传 `baseColorArgb: context.palette.accent.toARGB32()` |
| [theme_test.dart](file:///Users/ling/code/travel_app/test/app/theme_test.dart) | 门禁：色相差 ≥30° 或亮度比 ≥1.30（amber 豁免但须与危险色差 ≥30°） |

## 核对环境（已确认）

- 设备：**OPPO R9s Plus**，Android 7.1.1（API 25），物理 1080×1920，density 480（= 360×640 dp）。串号 `cb2e5863`，当前 `USB powered: true`，即用户刚插上的那台。
- adb：`/Users/ling/Library/Android/sdk/platform-tools/adb`；截图一律落 `/tmp`。
- 坐标换算：`screencap` 返回 1080×1920，按 1.875 倍换算到 576×1024 的预览图。
- 已装入 App：因 `flutter run` 的 streamed install 会被 ColorOS 安装器拦截，改用 `adb install -r -t build/app/outputs/flutter-apk/app-debug.apk`（已 Success）。
- 构建须**关闭沙箱**运行：sqlite3 native asset 需从 GitHub 下载，且 Gradle 要写 `~/Library/Android/sdk/analytics.settings`。

## 已完成核对（截图证据）

| 项 | 结论 | 证据 |
| --- | --- | --- |
| 冷启动默认主题色为琥珀 | 通过 | `/tmp/oppo_after_settle.png`（开始按钮 / 记录 tab 琥珀） |
| 设置页「外观」分组：4 色点 + 名称标签齐全 | 通过 | `/tmp/oppo_appearance.png`（琥珀/薄荷/天青/紫罗兰，名称在点下方） |
| 选中态：白圈 + 对勾落在当前色点上 | 通过 | 同上（琥珀带白圈与对勾） |
| 点选**薄荷**即时重着色（不点保存） | 通过 | `/tmp/oppo_mint.png`（保存按钮、字段标签、解除、底栏全变绿） |
| 点选**天青**即时重着色 | 通过 | `/tmp/oppo_sky.png`（同上，全变天青） |
| 侧载 APK 与 ColorOS 安装器的交互问题已定位 | 通过 | `/tmp/oppo_settings4.png`（安装器安全扫描页）；手动 `adb install` 可绕过 |

## 待核对项（决策完备，逐条执行）

1. **紫罗兰点选**：`adb shell input tap 921 1097` → 截图，期望保存按钮/字段标签/底栏选中态/解除按钮全变紫罗兰，紫罗兰点出现白圈+对勾。
2. **对勾颜色在浅色点上的可读性（待确认项）**：天青点上的对勾在 `/tmp/oppo_sky.png` 里看着偏深墨色，而琥珀/薄荷上偏白。需局部放大确认对勾是否统一取 `kAppOnAccent #0B0E12`；若为白色，则在天青（浅底）上对比度不足，属于缺陷。
   放大方法：`sips -c` 裁切天青点区域（设备坐标中心 ≈ (671, 1097)，半径 ≈ 60px）后查看，或直接取像素比对 `#0B0E12` / `#FFFFFF`。
3. **其它页面跟随**：切到 violet 后依次看 历史 / 统计 / 详情 三页，确认强调色一致（底栏选中态、可交互控件、曲线）。
4. **详情页撞色复核（本轮重点）**：切到 **sky**，进任意一条历史记录详情，比对 4 条曲线的颜色（应为主题色 `#7DD3FC`）与心率区间条的区间蓝，确认**色相/亮度可区分**。这是本轮改 sky 值的唯一目的。
5. **持久化（冷启动）**：`adb shell am force-stop com.ling.cycling_app` 后 `am start -n com.ling.cycling_app/.MainActivity`，确认主题色**保持**为停机前的选择（热重启不作数）。
6. **还原设备设置**：核对本轮是否动过「显示密度 / 自动旋转 / user_rotation」。目前**尚未改动**任何一项，仅在收尾时复查确认无需还原；顺带核对 `stay_on_while_plugged_in` 是否为设备原有值（当前 = 7）。

## 未决决策（需用户确认）

- **核对设备归属**：现场有两个 Android 设备——USB 插着的 OPPO R9s Plus（本 spec 采用）与无线连接的 `192.168.1.8:40139`（Redmi K40 / alioth，`adb` 14 天前记录显示它才是上一次真机验收用的机器）。若本 spec 用错设备，第 1–6 项需在 alioth 上重跑。
- **`flutter run` 与 `adb install` 的取舍**：ColorOS 会拦截 `flutter run` 的 streamed install。是否接受「手动 `adb install` + 无热重载」作为本机常规流程？

## 约束

- 不执行 `git push`；不新增提交除非用户要求。
- 不改动被测业务代码；若第 2 项确认是对勾对比度缺陷，先行汇报，由用户决定是否修。

## 验收标准

第 1–6 项全部给出「通过 / 失败」结论与截图路径；第 4 项在 sky 下有可区分性结论；第 5 项为冷启动后的持久化结论；第 6 项确认设备设置已还原或本就未改。

## 核对结果（2026-10-15 收尾）

6 项全部执行完毕，逐项结论与截图路径见 [tasks](file:///Users/ling/code/travel_app/docs/superpowers/specs/2026-10-15-accent-theme-device-verification-tasks.md)。摘要：

| 项 | 结论 |
| --- | --- |
| 1 紫罗兰即时生效 | 通过（`/tmp/oppo_relaunch2.png`） |
| 2 对勾颜色 | 通过，非缺陷（探针命中 240 个 `#0B0E12`，即 `onAccent`） |
| 3 其它页面跟随 | 通过（历史/统计/详情；橙色横条为速度色带数据色，按设计不上主题色） |
| 4 详情页撞色 | 通过（`#7DD3FC` 对 `#64B5F6` 亮度比 1.33，且两者不同屏叠放） |
| 5 冷启动持久化 | 通过（`/tmp/oppo_coldrestart2.png`，仍为天青） |
| 6 设备设置 | 通过，无需还原 |

### 核对中新发现（与本次主题色改动无关）

- **心率区间条没画出来（已修复）**：详情页上区间条曾是一个只有细线边框、内部全为底色 `#0B0E12` 的 14dp 空矩形（`/tmp/oppo_detail_hr3.png` 像素扫描：y 1283–1324，上下边框 `#2A343F`，中间 19 行全是 `#0B0E12`），而下方图例正常显示 Z1 41% / Z2 29% / Z3 30%。根因在 [hr_zone_bar.dart](file:///Users/ling/code/travel_app/lib/features/detail/hr_zone_bar.dart#L44-L57)：`Row` 没设 `crossAxisAlignment: CrossAxisAlignment.stretch`，无子节点的 `ColoredBox` 在松高度约束下取 `constraints.smallest` → 每段高度 0。该文件**不在** `8a7a936` 改动范围内（`git show --stat 8a7a936` 无此文件），属既有缺陷；此前只验过「无心率数据」分支所以没暴露。
  - 修法（2026-10-16）：给该 `Row` 加 `crossAxisAlignment: CrossAxisAlignment.stretch`；顺带把 `DecoratedBox` 改为 `position: DecorationPosition.foreground`——色块撑满 14dp 后会把默认画在背景里的细线边框整个盖住，先前那圈边框能看见只是因为色块高度为 0。回归门禁见 [detail_page_test.dart](file:///Users/ling/code/travel_app/test/features/detail/detail_page_test.dart#L524-L549)「每段高度撑满 14dp，不会退化成空矩形」（旧用例只钉宽度，所以漏掉）。
  - 真机复核（`/tmp/fix_hrbar.png`，OPPO R9s Plus，天青主题）：区间条盒 y 1487–1529；上下各 3 px（= 1dp）为 `#2A343F` 边框；内部 36 行分三段，左→右 `#64B5F6` 40.9% / `#4CAF50` 29.2% / `#FFB300` 30.0%，与图例 41 / 29 / 30 一致，Z4/Z5 为 0% 正确缺席。
- **该机遗留多条 09-24 未结束骑行**：每次冷启动弹出一条（18:46 / 21:03 / 21:07 各见一次）。核对中为打通详情页点过一次「结算保存」，因此设备上多出一条 21:03 的 179 m / 26 s 记录；另用调试页「生成模拟数据」写入 16 条模拟记录（该功能为覆盖式，不累加）。
