# 收尾：启动封面先行 / 地图跟随 / 速度来源 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把本轮已经写完的三处改动（封面先于建库渲染、骑行中地图相机跟随、上报速度为 0 时按位移推算）补齐实机验证与文档口径，然后按主题分组提交并推送到 Gitee / GitHub 两个远端。

**Architecture:** 代码与测试已经完成并通过门禁（`flutter analyze` 无告警、790 条测试通过），本轮不再新增功能代码，只做四件事：在 OPPO 实机上补一次运行验证、把两处行为口径写进设计文档、清掉仓库里的临时产物、按主题拆成 7 个提交推双远端。

**Tech Stack:** Flutter 3.47.4（`/Users/ling/fvm/versions/3.47.4/bin/flutter`）、Riverpod 3、flutter_map 8.x、sqflite；Android 侧 adb（`OPPO R9s Plus`，`cb2e5863`，Android 7.1.1 / API 25）。

---

## 开始之前必须知道的现状

以下是上一个会话结束时的工作树状态，执行者不必重新探索：

- 工作树里有 14 个已改动文件 + 4 个未跟踪目录（`.opencode/`、`.screenshots/`、`design/`、`integration_test/`）以及未跟踪的 `ios/Podfile.lock`。
- `lib/` 下三处改动**都已完成并有测试覆盖**：
  - `lib/main.dart` + `lib/app/app.dart` + `lib/app/providers.dart`：数据库在 `runApp` 之后才打开，首帧由 Flutter 画封面。
  - `lib/features/record/live_route_map.dart`：相机按「可见范围的安全区」跟随当前位置，320ms 平移补间。
  - `lib/domain/recording/recording_session.dart`：`speedMps` 为 `0` 时按「平台没给速度」处理，回退到位移推算。
- `docs/superpowers/specs/2026-09-21-cycling-app-design.md` 的 9.4 节已经改好（相机跟随 + 2026-10-28 修正注记），但 8.1 与 14.4 还缺本轮两处口径。
- iOS 模拟器（`A53C6056-78B1-4084-BD50-EFD8661DCE23`）上已经跑过一次模拟骑行：相机中心随位置东移约 700 米。iOS 26 模拟器的 `simctl privacy grant` 不落 TCC，复跑会因定位被拒卡住，**不要再去折腾 iOS**。
- OPPO 实机上 `flutter run` 仍在后台挂着（应用已安装、已启动到记录页）；该机 `adb shell cmd location` 返回 `No shell command implementation.`，**无法用系统命令喂假轨迹**。
- 本机 `flutter test` 结尾会打印 `TRAE Sandbox Error: hit restricted`（`.vscode/` 与 Dart DTD 目录不在沙箱白名单），这是环境噪音，退出码 1 不代表测试失败，只看 `All tests passed!` 那行。

## 文件结构（本轮涉及）

| 文件 | 责任 | 本轮动作 |
| --- | --- | --- |
| `lib/main.dart` | 入口；把建库挪出 `runApp` 之前 | 已改，仅提交 |
| `lib/app/app.dart` | `CyclingApp` 用 `FutureBuilder<Database>` 让封面先出 | 已改，仅提交 |
| `lib/app/providers.dart` | `databaseProvider` 的 `overrideWith` 签名适配 | 已改，仅提交 |
| `lib/features/record/live_route_map.dart` | 实时地图与相机跟随 | 已改，仅提交 |
| `lib/domain/recording/recording_session.dart` | 速度来源回退（`0` 视作缺失） | 已改，仅提交 |
| `test/app/app_test.dart`、`test/app/providers_test.dart` | 启动顺序测试 | 已改，仅提交 |
| `test/features/record/record_views_test.dart` | 相机跟随回归测试 | 已改，仅提交 |
| `test/domain/recording/recording_session_test.dart` | 速度为 0 的里程回归测试 | 已改，仅提交 |
| `integration_test/simulated_ride_test.dart` | 模拟骑行验证工具（自动点开始、打印相机中心） | 新增，入库 |
| `docs/superpowers/specs/2026-09-21-cycling-app-design.md` | 设计口径 | 本轮补 8.1 与 14.4 |
| `.gitignore` | 仓库卫生 | 本轮追加三行 |
| `ios/Runner.xcodeproj/project.pbxproj`、`ios/Runner.xcworkspace/contents.xcworkspacedata`、`ios/Podfile.lock` | CocoaPods 接入产物（`pod install` 生成） | 单独一个 chore 提交 |

---

## Task 1: 在 OPPO 实机上补一次运行验证

**Files:** 无（只验证，不改代码）

**背景：** 这台机器是 Android 7.1.1（API 25），既没有 `cmd location` 也没有现成的 mock location 应用，所以本轮只能验证「安装 → 启动封面 → 记录页渲染 → 进入记录态」这一段；相机跟随与速度为 0 的修复仍由 iOS 模拟器日志与单测覆盖。不要把「跑得起来」写成「跟随已验证」。

- [ ] **Step 1: 确认应用还在前台**

Run:
```bash
adb -s cb2e5863 shell dumpsys activity activities | grep -m2 -E "mResumedActivity"
```
Expected: `mResumedActivity: ActivityRecord{... u0 com.ling.cycling_app/.MainActivity ...}`

若没有这一行（应用被系统回收或 `flutter run` 已断），重新起一个：
```bash
/Users/ling/fvm/versions/3.47.4/bin/flutter run -d cb2e5863
```
Expected: 末尾出现 `Flutter run key commands.` 与 `A Dart VM Service ... is available at:`。

- [ ] **Step 2: 截一张待机页**

Run:
```bash
adb -s cb2e5863 exec-out screencap -p > /tmp/oppo-standby.png
```
Expected: 能打开这张图并看到「准备出发 · 等待定位」「距离 0 m」「开始骑行」与底部四个 tab。若坐标与下面不同，以这张图为准重新换算（截图宽 576，设备物理宽 1080，缩放系数 1.875）。

- [ ] **Step 3: 确认定位链路在跑（不是被权限卡住）**

Run:
```bash
adb -s cb2e5863 shell appops get com.ling.cycling_app | grep -i location
adb -s cb2e5863 shell dumpsys package com.ling.cycling_app | grep -m2 "ACCESS_FINE_LOCATION: granted"
```
Expected: `FINE_LOCATION: allow` 与 `android.permission.ACCESS_FINE_LOCATION: granted=true, flags=[ USER_SET ]`。

- [ ] **Step 4: 点「开始骑行」**

Run（「开始骑行」按钮中心在 1080×1920 上约 `(554, 1640)`）：
```bash
adb -s cb2e5863 shell input tap 554 1640
sleep 6
adb -s cb2e5863 exec-out screencap -p > /tmp/oppo-recording.png
```
Expected: 新截图里状态条变成记录态、底部动作区出现「暂停 / 结束」；室内无星时地图仍是「等待定位…」。

- [ ] **Step 5: 收尾，不留未结束的记录**

Run:
```bash
adb -s cb2e5863 shell input tap 900 1786   # 若「结束」按钮位置不同，以 Step 4 的截图换算
sleep 4
adb -s cb2e5863 exec-out screencap -p > /tmp/oppo-finish.png
```
Expected: 出现结束确认（「结束骑行？/ 保存」之类）。若有弹窗，按截图换算坐标点确认；这一步的目的是让数据库里不留 `recording` 状态的骑行——留着的话下次启动会被 `RecoveryGate` 弹窗挡住。

- [ ] **Step 6: 看一遍 logcat 有没有异常**

Run:
```bash
adb -s cb2e5863 logcat -d -t 300 | grep -iE "FATAL|AndroidRuntime|E/flutter" | head -20
```
Expected: 没有输出（空）。

---

## Task 2: 把两处行为口径写进设计文档

**Files:**
- Modify: `docs/superpowers/specs/2026-09-21-cycling-app-design.md:225-226`（8.1，速度来源）
- Modify: `docs/superpowers/specs/2026-09-21-cycling-app-design.md:671-676`（14.4，相机跟随的残余风险）

- [ ] **Step 1: 在 8.1 的第 2 条「最高速」后面补一段速度来源口径**

在第 225 行（`2. **最高速**：...`）之后、第 226 行（`3. **曲线锯齿**：...`）之前插入：

```markdown
   **速度来源：上报为 `0` 按「没给」处理**（2026-10-28）。`Location.getSpeed()` 解不出速度时
   返回 `0`（iOS 返回 `-1`），模拟器同样这么报。若把 `0` 当成真实速度，静止死区
   （`kSpeedDeadbandEnterMps`）会把整段骑行判成静止，速度与里程一起卡在 0——已在 iOS 模拟器上
   复现：位置每 2 秒北移 20 米，`dist` 始终是 `0.0 m`。口径是只有「正数且不超过
   `kMaxPlausibleSpeedMps`」的上报值才直接采用，其余（含 `0`）一律回退到「位移 ÷ 时间」，
   抖动仍由死区兜住。
```

- [ ] **Step 2: 改掉 14.4 第 7 条里对旧相机行为的描述**

把第 671–676 行那一条整段替换为：

```markdown
7. **骑行界面全屏地图的真实瓦片渲染**（本轮更新）。合并那一轮室内无定位，地图停在
   「等待定位…」占位态；后来用模拟定位注入拿到了定位点，**底图瓦片加载出来、轨迹折线
   画在模拟轨迹上**，这两件事已从「只算代码路径通」升级为「看过」。相机跟随也在
   iOS 模拟器上补验过：位置向东走约 1.2 km，相机中心随之平移约 700 m，每次约 240 m
   （= 可见宽度的一半再乘安全区比例）。仍未覆盖的是 **真实户外 GPS 下的贴合度**：
   模拟定位给的是理想轨迹，瓦片与折线叠得准不准、真实抖动会不会让箭头在安全区边缘
   反复触发平移，都还是模拟数据证明不了的。需户外一次完整骑行才能确认，与第 2 条同批。
```

- [ ] **Step 3: 校验改动落到了正确位置**

Run:
```bash
grep -n "速度来源：上报为" docs/superpowers/specs/2026-09-21-cycling-app-design.md
grep -n "相机跟随也在" docs/superpowers/specs/2026-09-21-cycling-app-design.md
```
Expected: 两条各命中一行，行号分别在 8.1 与 14.4 的范围内（约 226 与 674）。

---

## Task 3: 仓库卫生

**Files:**
- Modify: `.gitignore`

**背景：** `.screenshots/`（4 MB 的本轮验证截图）与 `.opencode/`（200 KB 工具目录）是本地产物；`design/`（3.1 MB 的 `.pen` 与导出图）是设计源文件，图标已经复制进 `assets/`，构建不依赖它。三者都不该进仓库。

- [ ] **Step 1: 在 `.gitignore` 的「本地草稿」段落后追加一段**

在 `.trae/` 那一行之后插入：

```gitignore
# 本地验证截图、工具目录与设计源文件
.screenshots/
.opencode/
design/
```

- [ ] **Step 2: 确认未跟踪列表只剩该进的**

Run:
```bash
git status --short
```
Expected: 未跟踪项只剩 `ios/Podfile.lock` 与 `integration_test/`，`design/`、`.screenshots/`、`.opencode/` 不再出现。

---

## Task 4: 跑门禁

**Files:** 无

- [ ] **Step 1: 静态检查**

Run:
```bash
/Users/ling/fvm/versions/3.47.4/bin/flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 2: 全量测试**

Run:
```bash
/Users/ling/fvm/versions/3.47.4/bin/flutter test 2>&1 | tail -3
```
Expected: `00:xx +790: All tests passed!`（末尾可能跟一行 `TRAE Sandbox Error`，忽略它，只看这一行）。

- [ ] **Step 3: 若有失败**

先停下，用 `superpowers:systematic-debugging` 定位，不要带着红色门禁提交。

---

## Task 5: 按主题分组提交

**Files:** 见每个提交的文件清单

**背景：** 一次 `.git add` 全部文件会把「启动流程」「地图跟随」「速度修复」「验证工具」「iOS 构建产物」「仓库卫生」混成一个提交，回滚时无法单独摘出。按下面的分组逐个提交，每个提交前先跑一次 `git status --short` 核对暂存内容。

- [ ] **Step 1: 启动流程**

```bash
git add lib/main.dart lib/app/app.dart lib/app/providers.dart test/app/app_test.dart test/app/providers_test.dart
git commit -m "$(cat <<'EOF'
feat: 封面先于建库渲染，启动不再停在白屏

数据库打开从 main() 的 await 挪到 runApp 之后：首帧由 Flutter 画封面，
建库失败时给兜底提示，而不是停在没有任何反馈的空屏。
EOF
)"
```

- [ ] **Step 2: 地图跟随**

```bash
git add lib/features/record/live_route_map.dart test/features/record/record_views_test.dart
git commit -m "$(cat <<'EOF'
fix: 骑行中的地图相机跟着当前位置走

原来用轨迹包围盒判断要不要重新取景，而包围盒按定义永远包含最新点，
条件恒成立，首帧之后相机再没动过——骑出去几分钟箭头就出了画面。
改为按相机可见范围的安全区判断，并用 320ms 补间平移过去。
EOF
)"
```

- [ ] **Step 3: 速度来源**

```bash
git add lib/domain/recording/recording_session.dart test/domain/recording/recording_session_test.dart
git commit -m "$(cat <<'EOF'
fix: 上报速度为 0 时按位移推算，里程不再卡在 0

安卓 getSpeed() 解不出速度时返回 0、iOS 模拟器同样如此；照单全收会让静止
死区把整段骑行判成静止，速度与里程一起停在 0。
EOF
)"
```

- [ ] **Step 4: 文档**

```bash
git add docs/superpowers/specs/2026-09-21-cycling-app-design.md
git commit -m "$(cat <<'EOF'
docs: 同步相机跟随与速度来源口径
EOF
)"
```

- [ ] **Step 5: 模拟骑行验证工具**

```bash
git add integration_test/simulated_ride_test.dart pubspec.yaml pubspec.lock
git commit -m "$(cat <<'EOF'
test: 加入模拟骑行用的 integration test

自动跳过残留的恢复对话框、点开始骑行，并按 2 秒打印相机中心与轨迹点数，
配合 simctl / 真机喂点即可复核跟随。
EOF
)"
```

- [ ] **Step 6: iOS 构建产物**

```bash
git add ios/Runner.xcodeproj/project.pbxproj ios/Runner.xcworkspace/contents.xcworkspacedata ios/Podfile.lock
git commit -m "$(cat <<'EOF'
chore(ios): 提交 CocoaPods 接入后的工程文件

pod install 生成的工程引用与 Podfile.lock，之前没入库，每次构建都会把工作树弄脏。
EOF
)"
```

- [ ] **Step 7: 仓库卫生**

```bash
git add .gitignore
git commit -m "$(cat <<'EOF'
chore: 忽略本地截图、工具目录与设计源文件
EOF
)"
```

- [ ] **Step 8: 核对**

Run:
```bash
git status --short && git log --oneline -8
```
Expected: `git status` 为空（工作树干净），`git log` 顶部是上面 7 个提交，其下是 `ad65a7f`。

---

## Task 6: 推到两个远端

**Files:** 无

- [ ] **Step 1: 推 Gitee**

```bash
git push origin main
```
Expected: `main -> main`，无 `! [rejected]`。

- [ ] **Step 2: 推 GitHub**

```bash
git push github main
```
Expected: `main -> main`。

- [ ] **Step 3: 核对两端状态**

```bash
git ls-remote --heads origin main
git ls-remote --heads github main
git rev-parse HEAD
```
Expected: 三行 SHA 完全一致。

若出现 `rejected`，**不要** `--force`：先 `git fetch origin && git log --oneline HEAD..origin/main` 看清楚远端多了什么，再决定合并还是询问用户。

---

## 完成标准

1. OPPO 上「安装 → 封面 → 记录页 → 进入记录态 → 结束」走通，logcat 无 FATAL。
2. 设计文档的 8.1 与 14.4 补上了本轮两条口径。
3. `flutter analyze` 无告警，`flutter test` 790 条全过。
4. 工作树干净，7 个提交按主题拆分，Gitee 与 GitHub 的 `main` 与本地 HEAD 指向同一个 SHA。
