# 多主题色真机核对 Tasks（2026-10-15）

配套 spec：[2026-10-15-accent-theme-device-verification.md](file:///Users/ling/code/travel_app/docs/superpowers/specs/2026-10-15-accent-theme-device-verification.md)

设备：OPPO R9s Plus（`-s cb2e5863`），1080×1920，density 480。
截图统一落 `/tmp`。

## [x] T1 紫罗兰点选即时生效
```
adb -s cb2e5863 shell input tap 921 1097
adb -s cb2e5863 exec-out screencap -p > /tmp/oppo_violet.png
```
**通过**。证据 `/tmp/oppo_relaunch2.png`：保存按钮 / 字段标签 / 解除 / 底栏选中态均为紫罗兰；紫罗兰点带白圈 + 对勾。
（注：点选后设备熄屏，重唤醒后 App 已冷启动，紫罗兰仍生效——顺带验到持久化。）

## [x] T2 对勾颜色在浅色点上的可读性
**通过，非缺陷**。像素探针 `/tmp/oppo_mint.png`、`/tmp/oppo_sky.png`、`/tmp/oppo_appearance.png`：
三个色点内圈都恰好含 240 个 `#0B0E12` 像素 = 对勾笔画，即对勾统一取 `kAppOnAccent`（[settings_page.dart](file:///Users/ling/code/travel_app/lib/features/settings/settings_page.dart#L324-L330) `context.palette.onAccent`），不是白色。
`#0B0E12` 压在天青 `#7DD3FC` 上对比度 ≈ 11.5:1，读得清；之前看到的「白」是选中用的白圈（`kAppTextPrimary`）。

## [x] T3 其它页面跟随主题色
**通过**。
- 历史 `/tmp/oppo_history2.png`：底栏 历史 图标 = 紫罗兰 `#A78BFA`（逐像素命中 383 个）。
- 统计 `/tmp/oppo_stats2.png`：周/月/年选中段与趋势曲线、趋势填充均随主题色（曲线像素命中 `#7DD3FC` 1041 个）。
- 详情 `/tmp/oppo_detail_hr2.png`、`/tmp/oppo_detail_hr.png`：踏频、功率曲线与「导出 GPX」按钮随主题色。
- 卡片上那条橙色横条不是漏迁移的强调色：它是速度色带的数据色（`kSpeedColorMid = 0xFFFB8C00`），按设计不跟主题色。

## [x] T4 详情页撞色复核（本轮重点，须在 sky 下）
```
adb -s cb2e5863 shell input tap 671 1097      # 切回天青
```
**通过（门禁内），但记录两条事实**，证据 `/tmp/oppo_detail_hr3.png`：
1. 心率曲线 = 天青 `#7DD3FC`（强调色）；心率区间蓝 = `#64B5F6`（数据色）。亮度比 1.33 ≥ 1.30，色相差 ≈ 8°，属同一浅蓝色系、靠亮度差区分。同屏并不叠放（曲线在上、区间条在下），实际没有发生「两条蓝压在一起」。
2. **发现缺陷（与本次主题色改动无关）**：心率区间条本体没画出来。`/tmp/oppo_detail_hr3.png` 里区间条是一个只有细线边框、内部全为底色 `#0B0E12` 的 14dp 空矩形（y 1283–1324 全区域扫不到任何一个区间色），而它下方的图例正常显示 Z1 41% / Z2 29% / Z3 30%。根因见 [hr_zone_bar.dart](file:///Users/ling/code/travel_app/lib/features/detail/hr_zone_bar.dart#L44-L57)：`Row` 未设 `crossAxisAlignment: CrossAxisAlignment.stretch`，`ColoredBox` 无子节点时在松约束下高度取 0。**未改代码，待你决定是否修**。
   顺带结论：速度曲线按 `colorBySpeed: true` 走数据色（橙色），只有心率/踏频/功率三条走强调色——与 spec 表格里「4 条曲线都用强调色」的表述需按此理解。

## [x] T5 持久化（冷启动）
```
adb -s cb2e5863 shell am force-stop com.ling.cycling_app
adb -s cb2e5863 shell am start -n com.ling.cycling_app/.MainActivity
```
**通过**，证据 `/tmp/oppo_coldrestart2.png`：重启后强调色仍为天青（继续按钮、开始按钮、底栏选中态），全屏扫不到琥珀/薄荷/紫罗兰像素。

## [x] T6 收尾：设备设置复查 + 汇报
**通过，无需还原**。
- `wm size` 1080x1920、`wm density` 480：均为物理默认，无 override。
- `accelerometer_rotation` 1、`user_rotation` 0、`screen_off_timeout` 1800000：均未改动。
- `stay_on_while_plugged_in`：核对开始时读到 7，中途因长时间分析导致熄屏两次，为让屏幕保持常亮把它显式写回 7（与来时同值，净改动为零），收尾仍为 7。
- 未执行 `git push`；未新增提交。

## [x] T7 修复心率区间条空矩形（2026-10-16，T4 顺带发现）
1. [hr_zone_bar.dart](file:///Users/ling/code/travel_app/lib/features/detail/hr_zone_bar.dart#L44-L57)：`Row` 加 `crossAxisAlignment: CrossAxisAlignment.stretch`（根因）；`DecoratedBox` 加 `position: DecorationPosition.foreground`（保边框）。
2. [detail_page_test.dart](file:///Users/ling/code/travel_app/test/features/detail/detail_page_test.dart#L524-L549)：新增「每段高度撑满 14dp，不会退化成空矩形」，断言每段 `ColoredBox` 高度为 14。
3. 变异验证：把 `stretch` 换回 `center` 后该用例失败（`height 0 ≠ 14`），确认门禁真的能杀死这个缺陷；随后还原。
4. `fvm flutter analyze` 无问题；`fvm flutter test` **601** 全绿（原 600 + 新增 1）。
5. 真机复核通过：`/tmp/fix_hrbar.png` 像素扫描——条盒 y 1487–1529、上下 1dp 细线边框在位、内部三段 40.9% / 29.2% / 30.0% 与图例一致。
6. 本轮未改动任何设备设置；未执行 `git push`，改动留在工作区未提交。

## [x] T8 换机重插后复核（2026-10-19）
设备重新插上（`cb2e5863`），`main` 仍为 `8a7a936`、工作区改动未变，因此**沿用机内 10-16 17:36 装的那版 APK**（装机时间与本地 `build/.../app-debug.apk` mtime 对得上），不重新构建。
1. 冷启动：主题色仍是**天青**（继续/开始按钮、底栏选中态），持久化继续成立。
2. 历史 → 2026-10-15 06:03 那条 → 滚到心率区块：区间条**正常渲染**，图例 Z1 41% / Z2 29% / Z3 30%。
3. 像素复核 `/tmp/v2_hrbar.png`：盒内细线 1499–1501 与 1538–1540（各 3 px = 1dp），色带 1502–1537（36 px = 12dp）；三段左→右 `#64B5F6` 40.9% / `#4CAF50` 29.2% / `#FFB300` 30.0%，与图例一致，Z4/Z5（0%）正确缺席；整盒 3+36+3 = 42 px = 14dp。
4. 设置 → 外观：4 个色点与名称齐全，天青带白圈 + 对勾，页面强调色随之为天青。
5. `logcat` 无 Flutter/Android 异常（仅 adb `input` 自身的 VM 日志）。
6. 设备设置复读：尺寸/密度/自动旋转/user_rotation/`stay_on_while_plugged_in`(7)/`screen_off_timeout` 全部与来时一致，无需还原；未 `git push`。

## [x] T9 清除机内测试数据（2026-10-19）
走「设置 → 调试（仅 debug 构建）→ 清空全部记录」这条既有路径，不碰数据库文件、不用 adb 删数据。
- 该动作的实现（[mock_ride_seeder.dart](file:///Users/ling/code/travel_app/lib/data/mock_ride_seeder.dart#L211-L222)）同时遍历 `listFinished()` 与 `findUnfinished()`，所以那几条每次冷启动弹窗的 09-24 未结束骑行也一并清掉。
- 执行结果：提示「已删除 **35** 条记录」——16 条模拟骑行之外，还有 09-23/09-24 早期真机测试留下的记录。
- 复核 1：历史页空状态「还没有骑行记录」（`/tmp/clean_history.png`）。
- 复核 2：统计页 距离 0 m / 时长 00:00 / 爬升 0 m / 次数 **0** / 功率「—」、趋势图无点（`/tmp/clean_stats.png`）。
- 复核 3：冷启动后记录页**不再弹**「检测到未结束的骑行」（`/tmp/clean_restart.png`）。
- 未清除（属设置而非测试数据，保留）：主题色天青、心率传感器配对 `C4:C3:D8:3E:65:76`、个人参数；调试分组本身仍在（debug 构建固有）。
- 本轮同样未改动任何设备设置。
