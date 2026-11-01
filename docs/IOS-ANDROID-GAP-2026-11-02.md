# iOS ↔ Android 完整差异清单（2026-11-02）

范围：以当前 `ios/Sources`（124 个 Swift 文件）和 `android/app/src/main/java`（60 个 Kotlin 文件）为准，逐项对比功能、交互与视觉细节。
图例：✅ 一致 · 🟡 部分/行为不同 · ❌ 缺失 · ➕ Android 独有。

> 本文件由五组只读审计（外壳/列表/连接、对话/渲染/输入、配对/中转/诊断、新建/项目/Feed、设计/自适应/平台）汇总，所有条目附两侧 `文件:行号`。
> 编号规则：第 1 节沿用 1–82；新增四域分别用 **C**（对话，C1–C165）、**P**（配对/连接，P1–P125）、**F**（新建/项目/Feed，F1–F150）、**D**（设计/自适应，D1–D135）。待用户确认后再按优先级实施。
> 已抽查修正的条目：D75（键盘避让实际由含 IME 的 `WindowInsets.safeDrawing` 完成，缺的是抽屉安全区与聚焦展开）、P100（`connections.json` 私钥明文，已重点标注）。

## 0. 本轮修复进度（2026-11-02）

已落地的修复（Android，按清单编号）：

- **安全**：P100（`connections.json` 与 `paired.json` 改为 Keystore AES-GCM 密封，旧明文自动迁移）；P105 重置身份同时丢弃密封密钥。
- **多 Mac**：P53/P57/F115（每台 Mac 一条 live link，含 relay 拨号）；P58（任意 Mac 连接详情）；F55/F56（Feed 按 host 归属，回答回到来源 Mac）；F95/F96/F98（待处理按 Mac 过滤与菜单）；F3/F4/F28/F29（新建会话跨 Mac 目标，chip 显示 Mac 名）。
- **Feed**：F75（历史事件只读）；F89/F106（busy/in-flight 防重复提交）；F83/F85/F86/F87（选项 id/说明、allow_custom、allow_skip、必答规则）；F65/F69/F71/F66/F70（question_prompt、text/reason、todos、截断标记、plan Markdown）；F60/F63（加载态与错误展示）；F101/F103/F105（会话内多问题完整表单）；F73（decision mode 本地化）；F52/F55-F57（按能力门控）。
- **配对/连接**：P44（轮询瞬时错误重试）；P45（退后台暂停、回前台恢复登记轮询）；P46（取消向 Mac 发送 cancel）；P47（拒绝/取消/过期/撤销本地化）；P48（批准后先探测再保存）；P31（等待页 clientID 前 12 位与展开详情）；P8（16 台上限）；P34（8 个中转上限）；P35（origin 规范化）；P27/P26（前台持续发现并把已配对 Mac 重定位到新端点）；P55/P56（网络恢复与回前台重拨）；P66（连接详情下拉刷新）；P93（后台同步读取最近 12 个会话正文）；P97（后台 pass 写诊断）。
- **对话**：C1（去 `<pasted_content>` 包装）；C93（图片-only 可发送）；C13/C119（图片挂到对应消息）；C118（草稿图可预览）；C98（图片准备中/失败提示）；C145（待发送按 host+session 存储）；C146（结果未确认与未送达区分）；C147（未决发送时禁止再发）；C73（流式文本增长自动跟随）；C78（上翻后恢复锚点）；C44（活动组独立页）；C35（工具完成时间）；C34（状态图标+文字）；C27-C29（表格自然列宽与对齐）；C148/C149/C150（加载文案、空态、截断提示）；C50/C53/C54（计时、停止回执、agent 名）；C58/C63（每个回复独立 footer 与复制反馈）；C131/C129/C134（后台任务运行态、Agent 对话、自动跟随）；C138（自定义模型）；C79（发送中的 prompt 固定在时间线顶部）；C102/C103（独立语音草稿条、完成/取消/使用）；P54（连续 3 次失败后静默 quiet host）。
- **新建/项目**：F10（根目录刷新）；F11-F13（子目录浏览、路径、空/截断状态）；F19/F22/F23/F24（`outcome_unknown` 重试、operation 复用、accepted 校验、错误映射）；F34-F36/F41/F44（相对路径输入、文件/差异/改动三种模式、整仓 diff、重命名 old → new、空内容提示）。
- **列表/抽屉**：第 1 节 #10/#11/#13/#14/#15/#17/#18/#19/#20/#21/#22/#24/#25/#30/#31/#32/#35/#37（Mac 分段、工作区分组、排序、缩进、chevron、相对时间、筛选语义、空态、失效过滤清理）；#33（MacTabs 横向滚动与状态点）；#42-#48（抽屉升级为完整会话树：搜索、排序、Mac/工作区分组、会话行、逐 Mac 连接入口、空态）。
- **平台/设计**：D103/D105（Android 默认英文、`values-zh` 中文，与 iOS 基线一致，三份资源 361 键一致）；D108（系统相对时间）；D109/D110（本地化日期与时长）；D95 部分（列表/对话/Feed/项目/新建/配对关键 testTag）；D96/D97 部分（Tab/Pill selected、运行指示器与标题语义）；D100/D34（主要返回/更多/语音/附件/最新按钮 40-44dp 命中区）；D91 部分（工具/活动组展开 `animateContentSize`）；D19（正文 17sp，sp 随字体缩放）。
- **其他**：C17（短对话底部对齐）；C51（进行中回复顶部计时条）；C52（`/preview` 的 `compacting` 接入运行行）；C87（“最新”跳转写滚动诊断）；P71（LAN 探测与 relay 拨号并行启动）；D121/D124（新增 `androidTest` Compose 语义测试与截图冒烟测试，已在任务自有模拟器上跑过 4 项）；P7/P20（`cmux-remote://pair?v=1` 解析、手工 host/port/token/fingerprint 表单、legacy bearer 传输与 `/v1` 路径映射、共享授权警告、`AuthorizedConnection.legacyToken` 加密持久化）；D48/D49（对话/项目/图片/Feed 页面从右侧滑入）；D38/D39（头栏与输入区白色渐变“磨砂”近似 + 白色圆形按钮）。

平台等价实现说明（不是未完成项）：

- **D17/D23 语义 Dynamic Type**：Compose 的 sp 会随系统字体缩放，字号体系由 Material `Typography` 承担；与 iOS 的 `Font.TextStyle` 是同一能力的平台命名差异。
- **C79 pinned prompt**：发送中的 prompt 用 `stickyHeader` 固定在时间线顶部；记录行替换气泡时由 Compose 的列表锚定接管，等价于 iOS 的 `PinnedPrompt` 交接。
- **D38/D39 玻璃**：Compose 无系统玻璃 API，头栏/输入区使用近白渐变 + 白色圆形按钮 + 描边阴影；这是 Android 上的等价材质。

本轮验证：Android 108 项 JVM 单测、4 项 Compose `androidTest`（在任务自有模拟器 `cmux-remote-fold` 上运行）、`assembleDebug`；`scripts/verify.sh`（527 项 Swift 测试、phone-state、iOS/Mac 本地化、release checks、签名材料检查）；三份 Android 字符串资源键一致（361/361/361）；`git diff --check` 通过。

> 说明：第 1–5 节的表格保留审计时的原始状态，作为逐条证据；本轮修复与等价实现见第 0 节，表格内的 ❌/🟡 不再逐行更新。

## 1. 外壳、列表与连接生命周期

> 证据格式 `文件:行号`，iOS 根为 `ios/Sources`，Android 根为 `android/app/src/main/java/com/cmuxremote/mobile`。

### 1.1 外壳与生命周期

| # | iOS 行为 | Android 现状 | 状态 |
| --- | --- | --- | --- |
| 1 | `links.isEmpty` → PairingView，否则列表（`CmuxRemoteApp.swift:16-20`） | 五态 `Restoring/Pairing/AwaitingOwner/Failed/Connected`，多一个恢复中居中转圈（`ui/AdaptiveRoot.kt:239-275,240`） | 🟡 |
| 2 | `scenePhase` 驱动恢复配对、回前台 `resumeEnrollment()+discover()`、退后台暂停并调度后台同步（`CmuxRemoteApp.swift:20-24`） | `MainActivity` 只有 `onCreate`，无任何生命周期观察者（`MainActivity.kt:11-38`） | ❌ |
| 3 | 从后台回来时记录 `backgroundedAt`，回前台全量 `reconnect()`（`AppModel+Connection.swift:45-55`） | 无；`restore()` 只在 ViewModel 初始化执行（`CmuxViewModel.kt:548-573`） | ❌ |
| 4 | 前台持续 Bonjour 发现，并对已配对 Mac 校验新端点后搬迁（`AppModel.swift:148-184`） | 只在配对页可见时 NSD（`AdaptiveRoot.kt:136-145`），已配对 Mac 无重定位 | ❌ |
| 5 | 监督任务只在 active 且已有 Mac 时启动，并跟随后台会话（`CmuxRemoteApp.swift:26-33`） | LiveUpdates/poll 在 `connect()` 起停，不感知前后台（`CmuxViewModel.kt:742-781`） | 🟡 |
| 6 | 新建会话用 sheet，发起后立即关闭 sheet，列表显示启动提示并 20×1.5s 等待（`SessionListView.swift:178-198`） | 整页替换 Start 页，等待循环留在 Start 页内（`AdaptiveRoot.kt:213-237`；`CmuxViewModel.kt:1479-1513`） | 🟡 |
| 7 | 新建会话跨所有有 `conversationStart` 能力的 Mac（`SessionListView.swift:179`；`AppModel.swift:424-426`） | `openStart()` 只列当前 repository 的工作区（`CmuxViewModel.kt:1440-1453`），不能换 Mac | 🟡 |
| 8 | 强制浅色（`CmuxRemoteApp.swift:20`） | 只提供 lightColorScheme（`ui/theme/CmuxTheme.kt:13-23`） | ✅ |

### 1.2 列表结构与多 Mac

| # | iOS 行为 | Android 现状 | 状态 |
| --- | --- | --- | --- |
| 9 | 列表 `LazyVStack(spacing 24)`、左右 20 / 上 20 / 下 24（`SessionListView.swift:52-53,137`） | `LazyColumn` 间距 16（dense 10）、横 20 纵 8（`SessionListScreen.kt:263-266`） | 🟡 |
| 10 | **先按 Mac 分段，再按工作区分组**（`SessionHostSection.swift:10-14`；`SessionListView.swift:83-128`） | 所有 Mac 的会话按**工作区标题**合并分组（`SessionListScreen.kt:214-220`） | ❌ |
| 11 | 多 Mac 显示 Mac 段标题（laptop 图标）及该 Mac 的错误（`SessionListView.swift:85-87`） | 无 Mac 段标题，只有顶部 MacTabs（`SessionListChrome.kt:149-164`） | ❌ |
| 12 | 单 Mac 且按工作区分组时显示“工作区”大标题（`SessionListView.swift:88`） | 无 | ❌ |
| 13 | 工作区图标 `macwindow`；未绑定会话组标题“其他会话”+ 时钟图标（`SessionListView.swift:96`；`SessionWorkspaceGroup.swift:16`） | 一律 Folder 图标，未绑定组标题为空字符串（`SessionListScreen.kt:219,304`） | ❌ |
| 14 | 工作区标题缺失时回退组内首条会话标题，ID 小写比较；按组内最新更新时间排序（`SessionWorkspaceGroup.swift:11-24`） | 回退原始 workspaceKey，大小写敏感；`groupBy` 保持服务端顺序（`SessionListScreen.kt:215-220`） | 🟡 |
| 15 | 每次读取后显式排序：updatedAt 降序 → writable 优先 → 标题本地化排序（`AppModel.swift:334-341`） | 依赖 Bridge 返回顺序（`CmuxViewModel.kt:991`） | 🟡（Bridge 是否已排序未核实） |
| 16 | 时间排序是纯平铺，无分组标题，行内带 Mac 名（`SessionListView.swift:77-81`） | 生成“最近”伪分组，带折叠与组内加号（`SessionListScreen.kt:214-220,294-324`） | 🟡 |
| 17 | 选定工作区后不再显示分组标题/缩进/组内加号（`SessionListView.swift:43,92-124`） | 仍显示分组标题、加号、折叠箭头（`SessionListScreen.kt:294-334`） | 🟡 |
| 18 | 会话行元信息分列：agent、Mac 名（多 Mac 未筛选时）、相对时间、恢复/只读文字标签（`SessionListView.swift:216-223`） | 拼成 `agent · 时间`，无 Mac 名、无文字标签（`SessionRow.kt:57-79`） | ❌ |
| 19 | 非运行会话行尾有灰色 chevron（`SessionListView.swift:225-226`） | 无 | ❌ |
| 20 | Working 自绘 16pt 灰色 + 无障碍标签/id（`WorkingIndicator.swift:5-16`） | 14dp 蓝色 CircularProgressIndicator，无语义（`components/WorkingIndicator.kt:11-18`） | 🟡 |
| 21 | 相对时间由系统自动刷新（`SessionListView.swift:219`） | 只在重组时计算（`AdaptiveRoot.kt:639,666-677`） | 🟡 |
| 22 | 分组内会话缩进 34pt（`SessionListView.swift:122`） | 无缩进（`SessionListScreen.kt:325-332`） | ❌ |
| 23 | 折叠动画 0.18s easeInOut（`SessionListView.swift:210`） | 直接改 Set，无动画（`CmuxViewModel.kt:365-368`） | 🟡 |
| 24 | 空状态三种：无读取权限 / 无会话 / 无匹配（`SessionListView.swift:48,130-132`） | 两种：无会话 / 无匹配；无“无权限”（`SessionListScreen.kt:335-344`） | 🟡 |
| 25 | 错误显示在列表底部，条件为单 Mac、非 disconnected、非 quiet（`SessionListView.swift:135`） | 错误在分组之前作为 item；仅全部 Mac 失败时一条通用错误（`SessionListScreen.kt:291-293`；`CmuxViewModel.kt:995-1007`） | 🟡 |
| 26 | 首屏 loading 且无会话时居中 ProgressView 覆盖（`SessionListView.swift:154`） | 无覆盖层，仅下拉刷新指示或 Restoring 转圈（`SessionListScreen.kt:262`） | 🟡 |
| 27 | 多 Mac 待处理提醒可展开菜单，按 Mac 打开各自 Feed（`PendingReminder.swift:10-16`） | 单张聚合卡，打开聚合 Feed（`SessionListScreen.kt:268-277`） | ❌ |
| 28 | 待处理只统计有 feedRead 且受 Host 筛选的 Mac（`SessionListView.swift:56-57,230-232`） | 聚合所有 Mac，`max(pending.size,cachedPending)`，不检查能力、不受 Host 筛选（`SessionListScreen.kt:242,268`） | 🟡 |
| 29 | 启动提示显示在列表内，带图标与 id（`SessionListView.swift:73-76`） | 只在 Start 页内显示（`StartSessionScreen.kt:206-211`） | ❌ |
| 30 | 状态筛选：运行中 = state 以 working 开头**或 writable**；只读 = `!writable`（`SessionFilter.swift:10-13`） | 运行中仅 working；只读仅 Locked，resumable 不进只读（`SessionListScreen.kt:209-210`） | ❌ 语义不同 |
| 31 | 搜索匹配 title/agent/cwd，trim 后本地化包含（`SessionFilter.swift:15-16`） | 只匹配 title/agent，不 trim、不搜 cwd（`SessionListScreen.kt:207`） | 🟡 |
| 32 | 工作区过滤小写比较（`SessionFilter.swift:7`） | 严格字符串比较（`SessionListScreen.kt:206`） | 🟡 |
| 33 | MacTabs 横向滚动（`HostFilterTabs.swift:19`） | 普通 Row 不滚动（`SessionListChrome.kt:156-163`） | ❌（多 Mac 溢出未核实） |
| 34 | “All” 无状态点；选中加 isSelected 语义（`HostFilterTabs.swift:23,31,53-54`） | “全部 Mac”带绿点；单 Mac 点击仍有动作；无选中语义（`SessionListChrome.kt:157-158,176`） | 🟡 |
| 35 | 选“全部 Mac”同时清空工作区（`HostFilterTabs.swift:23`） | 只清 hostFilter（`SessionListChrome.kt:158`） | 🟡 |
| 36 | 列表筛选/排序入口：标题菜单含图标、勾选 Picker；抽屉也有排序（`SessionTitleMenu.swift:16-18`） | 标题菜单仅一个切换项，无图标/勾选（`SessionListChrome.kt:120-128`） | 🟡 |
| 37 | 失效的 host/workspace 筛选自动清理（`SessionListView.swift:145-150`） | 无清理（`CmuxViewModel.kt:351-363`） | ❌ |
| 38 | 折叠键 `hostID/workspaceID`（`SessionListView.swift:90`） | 键为 `group-工作区标题`，跨 Mac 同名会串（`CmuxViewModel.kt:365-368`） | 🟡 |

### 1.3 抽屉

| # | iOS 行为 | Android 现状 | 状态 |
| --- | --- | --- | --- |
| 39 | 宽度 min(440,77%)、圆角 38、40% 白遮罩、12pt 边条、spring（`SideDrawer.swift:15-16,30-58`） | 相同参数（`AppDrawer.kt:56-115,209-217,302-308`） | ✅ |
| 40 | 面板形状包含上下安全区；圆角随位移连续插值（`DrawerPanelShape.swift:8-14`） | 统一 RoundedCornerShape(38)，圆角按 raised 二值切换（`AppDrawer.kt:105-108`） | 🟡 |
| 41 | 集合/遮罩带 escape 无障碍动作（`SideDrawer.swift:60`） | 遮罩点击 + 左拖 + BackHandler（`AppDrawer.kt:94,189-205`） | 🟡 |
| 42 | **抽屉是完整会话树**：排序、搜索、Mac/工作区分组、可折叠、会话行直接打开（`SessionSidebarView.swift:29-118`） | **只是工作区选择器**：全部工作区 + 计数，无会话行/排序/搜索/折叠（`SessionListScreen.kt:113-183`） | ❌ 根本差异 |
| 43 | 抽屉标题 `app.title` + 排序菜单 + 搜索按钮（`SessionSidebarView.swift:29-39`） | 只有“工作区”标题（`SessionListScreen.kt:124-129`） | 🟡 |
| 44 | 抽屉搜索与列表共享 query，搜索时自动展开分组（`SessionSidebarView.swift:36-43,67-69`） | 无搜索入口 | ❌ |
| 45 | 时间排序时显示“最近”与带 Mac 名的行（`SessionSidebarView.swift:44-58`） | 不感知排序模式 | ❌ |
| 46 | 抽屉逐台列出所有 Mac；失败显示红色警告；右侧 gear 进入该 Mac 连接详情；末尾 Add Device（`SessionSidebarView.swift:70-85`） | 只显示第一台 Mac，绿点恒亮，点击连接详情；Add Mac 为文字（`SessionListScreen.kt:148-164`） | 🟡 |
| 47 | 抽屉空状态 `sessions.no_matches`（`SessionSidebarView.swift:65`） | 无空状态 | ❌ |
| 48 | 从抽屉点会话先关抽屉再打开；点 Mac 打开其连接页（`SessionListView.swift:165`） | 点工作区只设筛选并关闭；点 Host 开主 Mac 连接页（`AdaptiveRoot.kt:339-340`） | 🟡 |
| 49 | 抽屉打开时 pushed 页面后仍保持背后打开（`AppModel.swift:48-50`） | 打开连接/添加前先 close（`AdaptiveRoot.kt:340-341`） | 🟡 |
| 50 | 边缘开启在 conversation/connection/feed/addingDevice 时禁用（`SessionListView.swift:50`） | 禁用条件未含 addingDevice/connectionOpen（`AdaptiveRoot.kt:332`） | 🟡 |
| 51 | 非展示时不可点击、从读屏隐藏（`SideDrawer.swift:24-25`） | blockPointerInputs + clearAndSetSemantics（`AppDrawer.kt:158-160,184`） | ✅ |

### 1.4 连接监督与状态

| # | iOS 行为 | Android 现状 | 状态 |
| --- | --- | --- | --- |
| 52 | 每台 Mac 独立 `linkStates`（connecting/disconnected/connected）与 `quietHosts`（`AppModel+Connection.swift:8-17,56-75`） | 只有全局 `_reachable/_probed` 布尔（`CmuxViewModel.kt:243-246,996-997`） | ❌ |
| 53 | 重连退避 2/4/8/16/32s，最多展示 3 次后静默；掉线工作链路立即重拨（`ReconnectSchedule.swift:32,40-51,69-73`） | LiveUpdates 1/2/4/8/16/30s，无 quiet、无“工作链路”区分（`LiveUpdates.kt:89-92`） | 🟡 |
| 54 | `NWPathMonitor` 网络路径出现/切换时重拨（`NetworkPathMonitor.swift:7-20`） | 无 ConnectivityManager/NetworkCallback（全仓无命中） | ❌ |
| 55 | 下拉刷新：有掉线 Mac 只重拨掉线者，否则重读（`AppModel+Connection.swift:40-42`） | 下拉只 `refresh()`（`SessionListScreen.kt:262`） | 🟡 |
| 56 | 标题菜单“刷新”= 全量 `reconnect()`（`SessionTitleMenu.swift:27`） | = `refresh()`（`SessionListChrome.kt:138`） | 🟡 |
| 57 | 会话页连接条有 connecting/disconnected 两态，白色胶囊 + 0.2s 动画 + Mac 名（`ConnectionStatusBar.swift:12-38`） | 一条全宽 errorContainer 横幅，仅不可达态，无动画（`ConversationScreen.kt:139-163`） | 🟡 |
| 58 | 状态点真实区分转圈/红/绿，带 accessibilityValue（`HostFilterTabs.swift:64-82`）；抽屉失败红警告（`SessionSidebarView.swift:74-76`） | StatusDot 恒绿（`Common.kt:61-68`），用于所有位置 | ❌ |
| 59 | Feed 变更立即刷新待处理；sessions 变更至少间隔 8s 重读（`AppModel.swift:344-371`） | 单链路变更 250ms 后 refresh，列表 30s / 会话 15s 兜底（`CmuxViewModel.kt:917-945`） | 🟡 |
| 60 | 后台刷新最早 60s（`BackgroundSync.swift:17-18`） | WorkManager 最短 15 分钟（`BackgroundSyncWorker.kt:134,144`） | 🟡 |
| 61 | 配对轮询 2s（`RefreshTicker.swift:7-12`） | 1.5s，最多 200 次（`CmuxViewModel.kt:655-673`） | 🟡 |

### 1.5 多 Mac 的结构性问题

| # | iOS | Android | 状态 |
| --- | --- | --- | --- |
| 62 | 每个 Mac 独立 client、独立 linkStates 与订阅（`AppModel.swift:344-371`） | 只有一条 `live`，`startLive` 先 stop 旧的，只在 `connect()` 重建（`CmuxViewModel.kt:905-912,1023-1037`）；`open(hosted)` 不重建 | ❌ |
| 63 | 每台 Mac 的 client 自己处理 relay（`AppModel.swift:328-331`） | 只有 `connect()` 拨 relay；`open(hosted)` 只刷新 hint（`CmuxViewModel.kt:760-780,1023-1029`）；次级 Mac 仅 relay 可达时无法读取 | ❌（运行时未核实，代码路径明确） |
| 64 | 每个 Mac 都有自己的工作区数组与归属，失败时保留旧值（`AppModel.swift:317,422-423`） | `associate` 合成 map，重复 ID 覆盖；失败时该 Mac 工作区标题消失（`CmuxViewModel.kt:962-964,992`） | 🟡 |
| 65 | per-host 错误、待处理、新建能力（`AppModel.swift:321-326,396-401,424-426`） | 全局 error/feed/`_canStart`；`open(hosted)` 不更新 `_connection` 与 `_canStart`（`CmuxViewModel.kt:742-746,1023-1030`） | ❌ |
| 66 | Feed 页绑定具体 Mac 的 client（`SessionListView.swift:157`） | Feed 聚合跨 Mac，但回答统一发到当前 `repository`（`CmuxViewModel.kt:1824-1874`） | ❌ 风险 |
| 67 | 非当前 Mac 连接详情从抽屉可达（`SessionSidebarView.swift:70-79`） | `openConnection()` 无参，只展示 `_connection`；非当前 Mac 不可达（`AdaptiveRoot.kt:475-505`） | ❌ |
| 68 | 能力门控：conversationRead/workspaceRead/feedRead/conversationStart（`AppModel.swift:302-303,347-348,424-426`） | 只检查 conversationStart；刷新无条件读 sessions/workspaces/feed（`CmuxViewModel.kt:961-964`） | 🟡 |

### 1.6 后台同步与本地缓存

| # | iOS | Android | 状态 |
| --- | --- | --- | --- |
| 69 | 后台醒来：先 reconnect 所有 Mac → refresh → 读取最近 12 条中运行/更新的会话正文（`AppModel.swift:374-395`） | Worker 只读 sessions/feed，写列表快照与待处理计数，不读会话正文（`BackgroundSyncWorker.kt:89-127`） | ❌ |
| 70 | 无 Mac 数上限；12 条会话 | 最多 4 台 Mac，每台 20s / 总 60s（`BackgroundSyncWorker.kt:41,135-137`） | 🟡 |
| 71 | 无列表缓存；首屏居中 loading（`SessionListView.swift:154`） | 首帧用 `SessionSnapshotCache` 显示会话列表与待处理计数（`CmuxViewModel.kt:757-758,827-846`） | ➕ Android |
| 72 | 读失败保留 perHost 上次成功列表（`AppModel.swift:317`） | 缓存 → 内存上一份回退（`CmuxViewModel.kt:965-968`） | ✅ 意图 |
| 73 | 无列表缓存时间展示 | Snapshot.at 保存但从不展示（`SessionSnapshotCache.kt:68-78`） | 🟡 |
| 74 | 会话 SQLite：DB 512MB/会话 128MB/24 个/60k 条（`ConversationStore.swift:16-27`） | 相同（`data/ConversationStore.kt:38-43`） | ✅ |
| 75 | 任务缓存 16 条 / 4 MiB / LRU（`BackgroundTaskCache.swift:10-15`） | 相同（`data/BackgroundTaskCache.kt`） | ✅ |
| 76 | 后台不同步 pending 快照 | 后台写 pending 计数并首帧展示（`BackgroundSyncWorker.kt:101-108`） | ➕ |
| 77 | 后台开关 @AppStorage 默认 true（`BackgroundSync.swift:15,20`） | SharedPreferences 默认 true（`CmuxViewModel.kt:207,225-229`） | ✅ |

### 1.7 无障碍与测试标识（本域）

| # | iOS | Android | 状态 |
| --- | --- | --- | --- |
| 78 | 列表/筛选/Host/分组/会话/待处理/搜索/菜单/抽屉大量 accessibilityIdentifier（`SessionListView.swift:68-257` 等） | 列表相关无 testTag（全仓仅 ToolCards/AppDrawer 少量 semantics） | ❌ |
| 79 | 筛选与 Host 胶囊 isSelected trait（`SessionListView.swift:69`） | 无 selected 语义 | ❌ |
| 80 | 分组行 isHeader + expanded/collapsed accessibilityValue（`SessionListView.swift:100-115`） | 仅 chevron contentDescription | 🟡 |
| 81 | Working 指示器标签 + id（`WorkingIndicator.swift:16`） | 无 contentDescription | ❌ |
| 82 | 待处理卡 combine + id（`PendingReminder.swift:28`） | 无合并语义/无 id | 🟡 |

### 1.8 Android 独有（本域）

- 自适应 `Compact/TwoPane/ThreePane/Tabletop` 与铰链吸附（`adaptive/PaneLayoutPolicy.kt:9-84`；`AdaptiveRoot.kt:328-468`）；iOS 列表仍是单列 push。
- 分栏下列表常驻、右侧详情/空态“选择一个会话”（`AdaptiveRoot.kt:600-625`）。
- 列表行选中高亮（`SessionRow.kt:41-43`）。
- 列表底部 Host 页脚，MoreVert 实为刷新（`SessionListScreen.kt:393-415`）。
- 标题菜单“连接详情”与独立“新建”按钮（`SessionListChrome.kt:143`；`SessionListScreen.kt:255-259`）。
- 高度 <560dp 的 dense 模式（`AdaptiveRoot.kt:211`）。
- 首帧列表快照与后台待处理计数（见 71、76）。
- 调试启动参数 force_relay/reset_identity/add_device/relay_origin/enroll_file（`MainActivity.kt:16-31`）。

## 2. 对话页、渲染、滚动与输入

> 编号前缀 **C**。路径别名：`iOS/` = `ios/Sources/`，`Android/` = `android/app/src/main/java/com/cmuxremote/mobile/`，`Core/` = `Sources/CmuxRemoteCore/`。

### 2.1 消息类型与行结构

| # | iOS 行为 | Android 现状 | 状态 |
| --- | --- | --- | --- |
| C1 | 用户 prose 渲染为气泡；展示前用 `PromptText.displayed` 去掉 `<pasted_content>` 包装（`iOS/MessageRow.swift:25-34`、`Core/PromptText.swift:10-16`） | 用户气泡直接使用原始 `message.text`，未去包装（`Android/ui/ConversationScreen.kt:717-738`、`Android/data/BridgeRepository.kt:554`） | 🟡 |
| C2 | 用户气泡：左侧至少 44pt 空白、16×13 padding、圆角 24、accent 8.5% 背景、正文 `.body` + lineSpacing 4（`iOS/MessageRow.swift:26-33`） | 用户气泡：`widthIn(max=320dp)`、14×11 padding、圆角 20、实色 `AccentSoft`、`bodyMedium`（`Android/ui/ConversationScreen.kt:722-735`） | 🟡 |
| C3 | 助手 prose 走独立 Markdown 渲染，按块可选中（`iOS/MessageRow.swift:69`、`iOS/MarkdownMessageView.swift:8-31`） | 助手 prose 走 `MarkdownText`，整段 `SelectionContainer`（`Android/ui/ConversationScreen.kt:505-506`、`Android/ui/markdown/MarkdownText.kt:56-63`） | ✅ |
| C4 | `thought` 参与活动组，组内完整显示推理文本、无标题/无折叠（`iOS/ConversationTimeline.swift:13-16`、`iOS/MessageRow.swift:70-71`） | `thought` 不参与活动组，作为独立 Markdown 行显示（`Android/ui/ConversationScreen.kt:505-506,672-675`） | 🟡 |
| C5 | `tool_use`：折叠标题 + 详情卡，含工具名、状态、输入、输出、引用路径、完整记录入口（`iOS/MessageRow.swift:72-82`） | `tool_use`：折叠行 + 代码卡，含标题、状态点、input/output/diff、最多 4 个引用、完整记录入口（`Android/ui/ToolCards.kt:157-198,224-290`） | 🟡 |
| C6 | `terminal`：标题/摘要、卡片标题 “Shell”、状态为退出码或 Running、`$ command` 代码块、输出次要色、耗时（`iOS/MessageRow.swift:83-97`） | `terminal`：折叠行 + 代码卡；无 “Shell” 标题、无 `$ ` 前缀、无可见状态文字，仅退出码/耗时拼为 meta（`Android/ui/ConversationScreen.kt:522-531`、`Android/ui/ToolCards.kt:249-255,780-788`） | 🟡 |
| C7 | `file_edit`：标题为文件路径、diff 代码块、引用路径、diff 详情入口（`iOS/MessageRow.swift:98-107`） | `file_edit`：折叠行标题取 `filePath`，代码卡显示 diff，详情入口固定 `diff`（`Android/ui/ConversationScreen.kt:522-539`、`Android/ui/ToolCards.kt:245-248,278-288`） | ✅ |
| C8 | `question`：待回答时嵌入完整 Feed 表单（多问题/多选/自定义/提交/跳过）；已回答显示 “Answered: X”；不可回答显示说明（`iOS/MessageRow.swift:108-135`、`iOS/FeedQuestionView.swift:5-69`） | `question`：简单卡片，单项点选；多问题请求直接跳 Feed；无 “Answered:” 文案，选中项前加 “✓”（`Android/ui/ConversationScreen.kt:874-903`、`Android/CmuxViewModel.kt:1810-1822`） | 🟡 |
| C9 | `permission_request`：FloatingSurface，手掌图标 + 标题 + 等宽 subject（`iOS/MessageRow.swift:136-138`） | `permission_request`：通用工具行，显示 “needs approval”/“waiting”，无 subject（`Android/ui/ConversationScreen.kt:698-701`） | 🟡 |
| C10 | `attachment`：显示名/路径末段、图片或回形针图标、文件可打开、图片无引用时显示元数据说明（`iOS/MessageRow.swift:139-144`） | `attachment`：仅显示文本/“图片附件”，无图标、无打开文件、无元数据说明（`Android/ui/ConversationScreen.kt:702-706`） | 🟡 |
| C11 | `status`：映射为本地化生命周期标题（session started/ended/interrupted/context compacted）（`iOS/MessageRow.swift:145`、`iOS/ChatStatusTransition.Event+Presentation.swift:5-12`） | `status`：直接显示 `message.text`；无事件到本地化标题的映射（`Android/ui/ConversationScreen.kt:707`、`Android/data/BridgeRepository.kt:554`） | 🟡 |
| C12 | 未知类型显示 “Additional session event”（`iOS/MessageRow.swift:146`） | 未知类型显示原文或 “unsupported message”（`Android/ui/ConversationScreen.kt:708-712`） | 🟡 |
| C13 | 图片按 `messageID` 归属到具体消息，逐图显示 “View image” 胶囊按钮（`iOS/MessageRow.swift:47-54`、`iOS/ConversationView.swift:288`） | 图片全部聚合到时间线末尾一个块，丢失逐消息归属；按钮文字 “查看图片 X”（`Android/ui/ConversationScreen.kt:562-581`） | ❌ |
| C14 | 活动组由 `thought + toolUse + terminal + fileEdit` 连续组成（`iOS/ConversationTimeline.swift:9-17`） | 活动组仅由 `tool_use + terminal + file_edit` 组成（`Android/ui/ConversationScreen.kt:672-675`） | 🟡 |
| C15 | 行距节奏：连续操作紧贴，其他行上方 8pt；时间线 VStack 间距 6（`iOS/MessageRows.swift:28-33`、`iOS/ConversationView.swift:219`） | 统一 `Arrangement.spacedBy(12.dp)`，无“连续操作紧贴”规则（`Android/ui/ConversationScreen.kt:468`） | 🟡 |
| C16 | 时间线水平 18pt、顶部 12pt（`iOS/ConversationView.swift:281`） | 内容 padding 水平 16dp、垂直 12dp（`Android/ui/ConversationScreen.kt:467`） | 🟡 |
| C17 | 短对话用空白尾部把内容顶到底部，贴近输入区（`iOS/ConversationView.swift:217,275`） | LazyColumn 顶部对齐；短对话停在页面顶部，无底部填充（`Android/ui/ConversationScreen.kt:464-469`） | 🟡 |
| C18 | 错误行：红色小字 + 感叹号图标 + 红色 5.5% 圆角背景（`iOS/ConversationView.swift:254-258`） | 错误：时间线末尾纯红字；同时输入区下方再显示一次（`Android/ui/ConversationScreen.kt:630-634,1035-1037`） | 🟡 |

### 2.2 Markdown 渲染

| # | iOS 行为 | Android 现状 | 状态 |
| --- | --- | --- | --- |
| C19 | 按 ``` 分块，解析标题/列表/表格；块结果缓存（`iOS/MarkdownBlock.swift:22-70`、`iOS/MarkdownMessageView.swift:38-50`） | 同样的块模型与解析（标题/列表/表格/代码/段落），按 text `remember` 缓存（`Android/ui/markdown/MarkdownText.kt:92-145,56`） | ✅ |
| C20 | 块间距 14，段落 lineSpacing 5（`iOS/MarkdownMessageView.swift:8,29`） | 块间距 10，段落 16sp/23sp lineHeight（`Android/ui/markdown/MarkdownText.kt:248,303-311`） | 🟡 |
| C21 | 标题用 `.title2/.title3/.headline` 并加 `.isHeader` 无障碍语义（`iOS/MarkdownMessageView.swift:19-22`） | 标题按级别 20/18/16/15/14/13sp，粗体；无 heading 语义（`Android/ui/markdown/MarkdownText.kt:283-300`） | 🟡 |
| C22 | 无序列表标记 “•”，与正文 HStack 间距 10（`iOS/MarkdownBlock.swift:78-79`、`iOS/MarkdownMessageView.swift:23-27`） | 无序列表 “•”，标记固定 16dp 宽（`Android/ui/markdown/MarkdownText.kt:314-331`） | 🟡 |
| C23 | 行内样式由 `AttributedString(markdown:)` 处理：粗体/斜体/删除线/行内代码/链接（`iOS/MarkdownBlock.swift:18-19`） | 自写行内解析：`**`、`*`、`~~`、反引号、`[label](url)`（`Android/ui/markdown/MarkdownText.kt:397-492`） | ✅ |
| C24 | 链接依赖 AttributedString 的链接属性，由系统文本处理 | 链接显式建 `LinkAnnotation.Url` 并交给 `LocalUriHandler.openUri`（`Android/ui/markdown/MarkdownText.kt:392-410,483-491`） | ✅ |
| C25 | 围栏代码块：可换行、不横向滚动，`callout` 等宽、padding 14、圆角 14、`secondarySystemBackground`（`iOS/MarkdownMessageView.swift:10-16`） | 围栏代码块：`horizontalScroll`、12sp/18sp、padding 12×10、圆角 12、`Soft` 背景（`Android/ui/markdown/MarkdownText.kt:264-280`） | 🟡 |
| C26 | 代码块无专用复制按钮；逐块 `.textSelection(.enabled)`（`iOS/MarkdownMessageView.swift:13`） | 代码块无专用复制按钮；整列 `SelectionContainer` 可选中（`Android/ui/markdown/MarkdownText.kt:57-63,264-280`） | ✅ |
| C27 | 表格列宽按内容计算：先自然宽，放不下再压缩最宽列，保留不可断词最小宽（`iOS/MarkdownTableMetrics.swift:11-48`） | 表格所有列等宽，按可用宽度均分（`Android/ui/markdown/MarkdownText.kt:342-347`） | 🟡 |
| C28 | 只有“最小不可断宽”都放不下时才横向滚动（`iOS/MarkdownTableView.swift:24-28`、`iOS/MarkdownTableMetrics.swift:36`） | 每列可用宽度 < 88dp 时横向滚动，列宽固定 88dp（`Android/ui/markdown/MarkdownText.kt:345-349`） | 🟡 |
| C29 | 尊重 Markdown 分隔行中的左/中/右对齐（`iOS/MarkdownTableView.swift:48-54`） | 不解析、不保留对齐信息，全部左对齐（`Android/ui/markdown/MarkdownText.kt:150-165,370-384`） | ❌ |
| C30 | 表头 semibold subheadline；单元格内行内代码变次要色（`iOS/MarkdownTableView.swift:52-60,73`） | 表头 semibold 14sp；行内代码加等宽字体 + `Code` 背景（`Android/ui/markdown/MarkdownText.kt:370-384,448-452`） | 🟡 |
| C31 | 表格无卡片背景，仅行间 hairline Divider（`iOS/MarkdownTableView.swift:33-45`） | 表格整体 `Soft` 圆角 10dp 卡片 + Divider（`Android/ui/markdown/MarkdownText.kt:351-364`） | 🟡 |
| C32 | 每个文本块独立 `.textSelection`，可只选一段（`iOS/MarkdownMessageView.swift:13,21,26,29`） | 整个 Markdown 列包在一个 `SelectionContainer` 中（`Android/ui/markdown/MarkdownText.kt:56-63`） | 🟡 |

### 2.3 工具卡、活动组与详情页

| # | iOS 行为 | Android 现状 | 状态 |
| --- | --- | --- | --- |
| C33 | 工具折叠行：图标、标题、chevron；有 expanded/collapsed 无障碍值；点击前调用 `holdPlace()` 保持页面位置（`iOS/ToolDisclosure.swift:13-26`） | 工具折叠行：图标、标题、状态点、chevron；chevron 仅有展开/折叠 contentDescription；无保持位置（`Android/ui/ToolCards.kt:157-198`） | 🟡 |
| C34 | 状态以图标 + 文字显示（checkmark/xmark + “Succeeded/Completed/Failed/Running”）（`iOS/MessageRow.swift:73-74,87-89`、`iOS/ToolDetailCard.swift:25-39`） | 状态仅 7dp 圆点，颜色区分；文字只在 contentDescription（`Android/ui/ToolCards.kt:186,200-220`） | 🟡 |
| C35 | 工具卡显示 `completedAt`，今天显示 HH:mm，其他日期 MM-dd HH:mm（`iOS/ToolDetailCard.swift:25-40`） | 工具 `ChatMessage` 无 `completedAt` 字段，卡片不显示完成时间（`Android/data/BridgeRepository.kt:40-61`、`Android/ui/ToolCards.kt:249-255`） | ❌ |
| C36 | 工具卡内容：input、output、diff 各自独立代码块（`iOS/MessageRow.swift:75-80,90-95,101-105`） | 代码卡同样显示 input/output/diff（`Android/ui/ToolCards.kt:237-248`） | ✅ |
| C37 | 卡片内容超过 280pt 后才在内部滚动；低于 44pt 也保持最小高度（`iOS/ToolDetailCard.swift:12-24`） | 代码块 `heightIn(max=280.dp)`；无最小高度（`Android/ui/ToolCards.kt:72,294-310`） | 🟡 |
| C38 | 工具代码块长按提供 “Copy / Select text” 菜单（`iOS/ToolCodeBlock.swift:6-12`、`iOS/SelectableTextView.swift:28-38`） | 工具代码块只有 `SelectionContainer`，无复制全部菜单（`Android/ui/ToolCards.kt:294-310`） | 🟡 |
| C39 | 引用路径全部列出，转成项目相对路径后打开（`iOS/MessageRow.swift:55-60,78`） | 最多前 4 个，显示 basename 胶囊，直接传原路径（`Android/ui/ToolCards.kt:263-277`） | 🟡 |
| C40 | “View full record” 文字按钮打开工具详情（`iOS/MessageRow.swift:61-66`） | “查看完整记录” 文字按钮打开工具详情（`Android/ui/ToolCards.kt:278-288`） | ✅ |
| C41 | 活动组标题 “1 operation / N operations”；计数排除 `thought`（`iOS/ActivityGroupView.swift:56-62`、`iOS/ConversationTimelineItem.swift:20-23`） | 活动组标题 “1 个操作 / N 个操作”；计数就是组内三条类型消息数（`Android/ui/ToolCards.kt:481-483`、`Android/ui/ConversationScreen.kt:672-681`） | 🟡 |
| C42 | 最新活动组默认展开；读者手动选择优先，直到不再是最后一组（`iOS/ActivityGroupView.swift:32,95-97`、`iOS/ActivityGroupPolicy.swift:15`） | 同样的 `choice ?: isLatest` 逻辑，非最新时清除选择（`Android/ui/ToolCards.kt:92-97`） | ✅ |
| C43 | 超过 5 个操作只画最新 10 条消息；完整内容进独立页（`iOS/ActivityGroupPolicy.swift:11-13`、`iOS/ActivityGroupView.swift:33,42`） | 超过 6 个操作只画最后 6 行；完整操作没有独立组页（`Android/ui/ToolCards.kt:69,100`） | 🟡 |
| C44 | 长活动组打开独立 Sheet，懒加载完整 `MessageRows`，标题为操作数，可再全屏打开图片/工具详情（`iOS/ActivityGroupView.swift:68-93`） | “查看全部 N 个操作” 打开最后一行的工具详情，不展示整个组的操作列表（`Android/ui/ConversationScreen.kt:536`、`Android/ui/ToolCards.kt:138-150`） | ❌ |
| C45 | 组从“最新”变为非最新时用 0.18s easeInOut 折叠（`iOS/ActivityGroupView.swift:95-97`） | 只重置 `choice`，无折叠动画（`Android/ui/ToolCards.kt:95-97`） | 🟡 |
| C46 | 展开活动组/工具卡前 `holdPlace()`，停止自动跟随，避免页面跳动（`iOS/ActivityGroupView.swift:52-54`、`iOS/ToolDisclosure.swift:15-18`、`iOS/TimelinePlaceHold.swift:8-18`） | 未找到对应机制（`grep holdPlace` 于 Android 无匹配；`Android/ui/ToolCards.kt:93,162`） | ❌ |
| C47 | 工具详情页固定标题 “Tool details”；字段由引用决定，input 不存在时默认 output（`iOS/ToolDetailView.swift:15`、`iOS/MessageRow.swift:79,93,104`） | 标题取消息 `filePath/toolName`；字段由 `detail.field` 决定，tool_use 默认 output，file_edit 默认 diff（`Android/ui/AdaptiveRoot.kt:514-519`、`Android/ui/ConversationScreen.kt:536-539`） | 🟡 |
| C48 | 详情页字段胶囊 + 上一条/刷新/下一条；校验 contentID、stale_detail、not_found 并给出专门文案（`iOS/ToolDetailView.swift:17-41`、`iOS/ToolDetailModel.swift:35-47`） | 字段胶囊 + 上一页/刷新/下一页；只有通用错误，无 contentID/stale 专门文案（`Android/ui/ToolCards.kt:367-453`、`Android/CmuxViewModel.kt:1350-1372`） | 🟡 |
| C49 | 工具图标：read 类用 book，其他放大镜；terminal 用 terminal；文件编辑用 doc.text（`iOS/MessageRow.swift:73,86,99`） | 工具图标：terminal / file_edit / 其他 Build（`Android/ui/ToolCards.kt:485-489`） | 🟡 |

### 2.4 耗时与计时

| # | iOS 行为 | Android 现状 | 状态 |
| --- | --- | --- | --- |
| C50 | 输入区上方运行行：迷你 spinner + 沙漏脉冲图标 + 每秒更新的 “Working 3m 47s”（`iOS/ConversationView.swift:105-109`、`iOS/LiveRunLabel.swift:20-36`） | 输入区上方运行行：spinner + 文本 “运行中 3m 47s”，无沙漏图标（`Android/ui/ConversationScreen.kt:617-627`、`Android/ui/TextAndTiming.kt:125-146`） | 🟡 |
| C51 | 进行中回复的顶部也显示同一条运行计时，并带 0.5pt 分隔线（`iOS/ConversationView.swift:244-246,290-291`、`iOS/LiveRunLabel.swift:30-35`） | 只在时间线末尾显示运行行；进行中回复顶部无计时/分隔线（`Android/ui/ConversationScreen.kt:617-628`） | ❌ |
| C52 | 上下文压缩时运行行改为 “Compacting context…”，由 `model.compacting` 驱动（`iOS/LiveRunLabel.swift:26`、`iOS/ConversationModel.swift:38,414`） | `LiveRunLabel` 支持 compacting 文案，但调用点硬编码 `compacting = false`；`ConversationUi` 无 compacting 字段（`Android/ui/ConversationScreen.kt:622`、`Android/CmuxViewModel.kt:80-107`） | ❌ |
| C53 | 停止请求后显示 “Stop request sent” + checkmark（`iOS/ConversationView.swift:103-104`、`iOS/ConversationModel.swift:233-236`） | 未找到 `stopRequested` 状态或对应文案（`grep` 无匹配；`Android/CmuxViewModel.kt:1778-1801`） | ❌ |
| C54 | 活跃回复行右侧显示 agent 名称 + sparkles 图标（`iOS/ConversationView.swift:110`） | 活跃运行行只有 spinner + 计时，无 agent 名称/图标（`Android/ui/ConversationScreen.kt:617-627`） | 🟡 |
| C55 | 每个回复条目都按 `firstResponse[item.id]` 在顶部显示自身耗时（`iOS/ConversationView.swift:292-294`） | 只对最后一个助手 prose 与其 response 显示一次耗时（`Android/ui/ConversationScreen.kt:592-604`） | 🟡 |
| C56 | 完成耗时：“Worked for X” 左对齐 + 分隔线（`iOS/ResponseRunLabel.swift:10-15`） | 完成耗时：“用时 X” 居中 + 分隔线（`Android/ui/TextAndTiming.kt:150-165`） | 🟡 |
| C57 | 不论是否 recorded 都使用同一 “Worked for” 文案（`iOS/ResponseRunLabel.swift:12,18-23`） | recorded 用 “用时”，非 recorded 用 “用时约”（`Android/ui/TextAndTiming.kt:157-158`） | 🟡 |
| C58 | 每个已完成 response 末尾都有 footer（复制/分享/引用/选文/时间）（`iOS/ConversationView.swift:303-305`） | 仅在最后一条助手 prose、且 `!working`、且 `onQuote != null` 时显示一个 footer（`Android/ui/ConversationScreen.kt:592-616`） | 🟡 |
| C59 | footer 为 36×44 图标按钮：copy/checkmark、share、quote、select；附无障碍标签（`iOS/ResponseFooter.swift:13-34`） | footer 为文字按钮 “复制/分享/引用/选文”（`Android/ui/TextAndTiming.kt:177-195,278-285`） | 🟡 |
| C60 | 完成时间跟随系统 locale：今天 `.hour().minute()`，其他日期 `.month(.twoDigits).day(.twoDigits).hour().minute()`（`iOS/ResponseFooter.swift:26-32`） | 固定 24 小时制：`HH:mm` / `MM-dd HH:mm`，`Locale.US`（`Android/ui/TextAndTiming.kt:59-60,304-310`） | 🟡 |
| C61 | 对话时间页：总 recorded 时长、完成轮数、说明；无记录时 “no timing”（`iOS/ConversationView.swift:171-182`） | 同样的总时长/轮数/说明页面（`Android/ui/TextAndTiming.kt:199-241`、`Android/ui/AdaptiveRoot.kt:534-541`） | ✅ |
| C62 | 终端工具卡内显示该命令耗时（`iOS/MessageRow.swift:94`） | 终端 meta 拼 “退出码 0 · 1.2s”（`Android/ui/ConversationScreen.kt:530,780-788`） | 🟡 |

### 2.5 复制、分享、引用、选文、长按

| # | iOS 行为 | Android 现状 | 状态 |
| --- | --- | --- | --- |
| C63 | 复制回复后按钮变 checkmark，并有无障碍文案 “Copied”（`iOS/ResponseFooter.swift:9,14-18`） | footer 复制无任何成功反馈；只有选文页有 “已复制” 2 秒反馈（`Android/ui/TextAndTiming.kt:169-195,71-78`） | 🟡 |
| C64 | 回复 footer 用 `ShareLink` 分享文本（`iOS/ResponseFooter.swift:19`） | 回复 footer 通过 `ACTION_SEND text/plain` + chooser 分享（`Android/ui/AdaptiveRoot.kt:183-189`） | ✅ |
| C65 | 引用把每行加 `> ` 后插到草稿最前（`iOS/ConversationView.swift:312-315`、`iOS/ResponseFooter.swift:21-22`） | 同样的 `> ` 引用逻辑，插到 draft 前（`Android/CmuxViewModel.kt:1603-1608`、`Android/ui/TextAndTiming.kt:183`） | ✅ |
| C66 | 选文页用 `UITextView`，支持系统选区手柄/放大镜/编辑菜单，等宽可选（`iOS/SelectTextPage.swift:4-11`、`iOS/SelectableTextView.swift:10-28`） | 全屏选文页用 `SelectionContainer`，顶部右侧 “复制/已复制” 按钮（`Android/ui/TextAndTiming.kt:64-121`） | 🟡 |
| C67 | 用户气泡长按菜单：Copy / Select text（`iOS/MessageRow.swift:32`、`iOS/SelectableTextView.swift:28-38`） | 用户气泡长按 `DropdownMenu`：复制文本 / 选择文本（`Android/ui/ConversationScreen.kt:746-776,723`） | ✅ |
| C68 | 助手 Markdown 文本可直接系统选中，没有额外长按菜单（`iOS/MarkdownMessageView.swift:13-29`） | 助手 Markdown 文本由 `SelectionContainer` 直接选中，没有额外长按菜单（`Android/ui/markdown/MarkdownText.kt:56-63`） | ✅ |
| C69 | 工具代码长按有 Copy / Select text 菜单（`iOS/ToolCodeBlock.swift:11`、`iOS/SelectableTextView.swift:33-36`） | 工具代码只能拖选，无复制全部菜单（`Android/ui/ToolCards.kt:294-310`） | 🟡 |
| C70 | 已发送气泡文本 `.textSelection(.enabled)`；长按可系统选中（`iOS/OutgoingPromptRow.swift:15`） | 已发送气泡复用 `UserBubble`，长按弹出复制/选择菜单（`Android/ui/ConversationScreen.kt:545-560,717-738`） | 🟡 |

### 2.6 滚动行为

| # | iOS 行为 | Android 现状 | 状态 |
| --- | --- | --- | --- |
| C71 | 打开会话先恢复缓存，再 `settleAtBottom` 最多重试 6 次，等行高稳定后定位到底（`iOS/ConversationView.swift:451-465,353-363`） | 首帧只 `scrollToItem(messages.size - 1)` 一次；索引按消息数而非 LazyColumn 总 item 数计算，前面有 loading/older/footer 等 item 时会偏（`Android/ui/ConversationScreen.kt:434-445`） | 🟡 |
| C72 | 新条目到达且 `atLatest` 时滚到底；用 `timelineItems.last?.id` 驱动（`iOS/ConversationView.swift:444-447`） | 消息数量增长且 `atLatest` 时滚到最后一条消息（`Android/ui/ConversationScreen.kt:434-445`） | 🟡 |
| C73 | 正在流式输出的消息文本变化、preview 变化也会自动跟随（`iOS/ConversationView.swift:448-449`） | `LaunchedEffect` 只以 `messages.size` 和 `generation` 为 key；同长度文本更新和 preview 增长不会触发跟随（`Android/ui/ConversationScreen.kt:434`） | ❌ |
| C74 | “最新” 按钮条件：最新内容不可见且（离开底部或存在 pinned prompt）（`iOS/ConversationView.swift:432-436,507-514`） | `atLatest` 由最后一个可见 item 是否完整露出计算，离开底部即显示（`Android/ui/ConversationScreen.kt:425-431,637`） | ✅ |
| C75 | 最新按钮：44pt 悬浮玻璃圆、箭头向下、`chat.latest` 标识（`iOS/ConversationView.swift:548-560`、`iOS/FloatingIconStyle.swift:4-22`） | 最新按钮：Material `FloatingActionButton`，默认 56dp，内容为 “↓” 22sp（`Android/ui/ConversationScreen.kt:637-648`） | 🟡 |
| C76 | 回到底部先滚到最新行（`.bottom`），再滚到 `latest` 标记（`.bottom`），保证真正到末尾（`iOS/ConversationView.swift:377-387`） | `animateScrollToItem(messages.size - 1)`；同样存在“消息索引 ≠ LazyColumn item 索引”问题，且未考虑末尾的 preview/footer/working/error item（`Android/ui/ConversationScreen.kt:639`） | 🟡 |
| C77 | 加载更早：距顶部 240pt 内自动触发，顶部行也是可点按钮；有 0.8s 节流（`iOS/ConversationView.swift:220-234,323-339`） | 首个可见 item ≤ 1 自动触发，顶部行也是可点按钮；同样 0.8s 节流（`Android/ui/ConversationScreen.kt:446-451,482-497`、`Android/CmuxViewModel.kt:1690-1697`） | 🟡 |
| C78 | 翻页后显式 `scrollTo(anchor, .top)`，并等 50ms 让插入行完成布局（`iOS/ConversationView.swift:323-338`） | 翻页后没有任何锚点恢复；prepend 后可能跳到不同消息（`Android/CmuxViewModel.kt:1686-1746`） | ❌ |
| C79 | 发送后把新 prompt 钉在页面顶部（`PinnedPrompt`），回复在其下方生长；记录行替换气泡时交接 pin（`iOS/ConversationView.swift:469-473,516-546`、`iOS/PinnedPrompt.swift:9-43`） | 未找到 pin/jump 机制（`grep pinnedSent/jumpToLatest` 于 Android 无匹配；`Android/ui/ConversationScreen.kt:545-560`） | ❌ |
| C80 | 发送时 `jumpToLatest` 触发滚动；回复更新也再次 bump（`iOS/ConversationModel.swift:541,545`、`iOS/ConversationView.swift:469`） | `state.outgoing` 插入不是 `LaunchedEffect` key；发送后到下一次 history 读回之间可能看不到已发送气泡（`Android/ui/ConversationScreen.kt:434,545`） | 🟡 |
| C81 | 下拉：越过顶部 56pt 触发；有更早页则加载更早，否则刷新；链路断开时先重连（`iOS/ConversationView.swift:341-348,425-428`） | `PullToRefreshBox`：有更早页则加载更早，否则刷新；不会顺带重连（`Android/ui/ConversationScreen.kt:454-463`、`Android/ui/AdaptiveRoot.kt:162-163`） | 🟡 |
| C82 | 下拉不使用系统刷新指示器，`pulling` 时隐藏行内 spinner（`iOS/ConversationView.swift:61-63,225,421-424`） | `PullToRefreshBox` 的 `indicator = {}`，下拉无 spinner；加载更早行仍显示 `WorkingIndicator`（`Android/ui/ConversationScreen.kt:458-463,493`） | 🟡 |
| C83 | 滚动可交互收起键盘（`iOS/ConversationView.swift:420`） | 未找到 `scrollDismiss`/`ime` 处理；键盘仅靠 `WindowInsets.safeDrawing` 整体收缩（`Android/ui/AdaptiveRoot.kt:212`） | ❌ |
| C84 | 点击会话空白处收起键盘，行内点击不冒泡（`iOS/ConversationView.swift:283`） | 未找到点击时间线收起键盘的处理（`Android/ui/ConversationScreen.kt:464-469`） | ❌ |
| C85 | 原生 UIScrollView 回弹 | 原生 Compose LazyColumn overscroll 拉伸 | ✅ |
| C86 | 页面尾部有 18pt foot + 1pt “latest” 标记，用于精确锚定（`iOS/ConversationView.swift:278-279,503-505`） | LazyColumn 末尾无 foot/marker；最新定位依赖消息索引（`Android/ui/ConversationScreen.kt:464-469`） | 🟡 |
| C87 | 有 ScrollTrace / ScrollJumpTrace 滚动诊断（`iOS/ScrollTrace.swift:6-25`、`iOS/ConversationView.swift:417`） | 未找到滚动诊断；Android 只有普通 Diagnostics 日志（`Android/data/Diagnostics.kt`） | 🟡 |
| C88 | 有 `userScrolling`/`atLatest`/`holdingPlace` 三态，区分用户拖动、减速、自动跟随（`iOS/TimelineScrollInteraction.swift:8-25`、`iOS/ConversationView.swift:411-419`） | 只有派生的 `atLatest`，无“用户拖动/自动跟随”区分（`Android/ui/ConversationScreen.kt:425-431`） | 🟡 |

### 2.7 输入区

| # | iOS 行为 | Android 现状 | 状态 |
| --- | --- | --- | --- |
| C89 | 多行输入可增长到约半屏高度：`max(3, (pageHeight*0.5-120)/22)`（`iOS/ChatComposer.swift:29,63`、`iOS/ConversationView.swift:490`） | 固定 `maxLines = 4`（`Android/ui/ConversationScreen.kt:990`） | 🟡 |
| C90 | 两种布局：未展开时 plus/voice/send 同行；聚焦、有图片或多行草稿时切换为图片条 + 文本 + 底部操作行（`iOS/ChatComposer.swift:32-52`） | 只有单行布局，附件/输入/语音/发送始终在同一 Row（`Android/ui/ConversationScreen.kt:943-1034`） | 🟡 |
| C91 | 输入条视觉：白底、圆角 26/30、0.5pt 描边、阴影 radius 18 y5、0.18s easeInOut 动画；静止时左右内缩 18（`iOS/ChatComposer.swift:53-59`） | 输入条视觉：白底 `CircleShape`、无描边/阴影/展开动画；左右 14dp（`Android/ui/ConversationScreen.kt:925-947`） | 🟡 |
| C92 | 发送可用条件：有文本或有图片，且 `canSend && !busy && !sendBlocked`（`iOS/ChatComposer.swift:32,91-93`、`iOS/ConversationView.swift:479-485`） | 发送可用条件只有 `draft.isNotBlank() && !sending`；忽略图片、busy、recovery、语音、图片加载（`Android/ui/ConversationScreen.kt:1017-1023`） | 🟡 |
| C93 | 只有图片、没有文字也可以发送（`hasDraft` 包含 `hasImages`）（`iOS/ChatComposer.swift:32`） | UI 上图片-only 时发送按钮禁用；虽然 `send()` 内部会优先走图片发送，但按钮点不到（`Android/ui/ConversationScreen.kt:1017`、`Android/CmuxViewModel.kt:1757`） | ❌ |
| C94 | 工作中且草稿为空显示 stop.fill 圆形按钮；否则显示 arrow.up 发送按钮（`iOS/ChatComposer.swift:85-95`） | 同样 `working && draft.isBlank()` 显示 Stop；否则 ArrowUpward（`Android/ui/ConversationScreen.kt:1009-1033`） | ✅ |
| C95 | 按钮尺寸：展开 40/44，未展开 34/38；发送箭头 20pt；禁用态 `tertiarySystemFill`（`iOS/ChatComposer.swift:87-93`） | 按钮固定 34dp；箭头 18dp；禁用态 `surfaceVariant`（`Android/ui/ConversationScreen.kt:1009-1033`） | 🟡 |
| C96 | 附件菜单：照片、图片文件、项目、Feed；照片/文件在 busy、只读、sendBlocked 时禁用（`iOS/ChatComposer.swift:69-77`） | 附件菜单：照片、图片文件、项目、Feed；菜单项不随发送中/加载中/恢复中禁用（`Android/ui/ConversationScreen.kt:948-983`） | 🟡 |
| C97 | 图片草稿条：76×76 缩略图、圆角 14、点击预览、右上 xmark 移除、无障碍标识（`iOS/ImageDraftStrip.swift:11-40`） | 图片草稿行：56dp 缩略图、圆角 10、右上 18dp Ink 圆 ✕；点击无预览（`Android/ui/ConversationScreen.kt:193-241`） | 🟡 |
| C98 | 图片准备中显示 “Preparing image…”，失败显示红色 footnote 错误（`iOS/ConversationView.swift:93-94`） | 图片准备过程完全无 loading/error UI；`runCatching` 只处理成功分支（`Android/ui/AdaptiveRoot.kt:88-99`） | ❌ |
| C99 | 相册选择上限随已有图片变化：`max(1, 4 - count)`；已有 4 张时提示错误（`iOS/ConversationView.swift:125,492-495`） | 固定一次可选 4 张；`attachImage` 超过 4 张直接静默丢弃（`Android/ui/AdaptiveRoot.kt:101-103`、`Android/CmuxViewModel.kt:1598-1600`） | 🟡 |
| C100 | 图片文件导入允许多选（`iOS/ConversationView.swift:126-127`） | `OpenDocument` 单选（`Android/ui/AdaptiveRoot.kt:104-106`） | 🟡 |
| C101 | 语音按钮：录音时 waveform 图标 + accent；录音前强制失焦；busy/只读/sendBlocked 时禁用（`iOS/ChatComposer.swift:78-84`） | 语音按钮：始终 Mic 图标，仅用 accent 表示录音；不检查 busy/sending/sendBlocked，也不主动清焦点（`Android/ui/ConversationScreen.kt:998-1008`） | 🟡 |
| C102 | 语音草稿条：状态文案（preparing/listening/finishing/draft）、实时转写、取消、完成、使用、错误；FloatingSurface（`iOS/SpeechDraftStrip.swift:7-21`、`iOS/ConversationView.swift:92`） | 无语音草稿条；只在输入区下方显示错误（`Android/ui/ConversationScreen.kt:1038-1040`） | ❌ |
| C103 | 听写文本先进入独立 speech draft，点 “Use” 才追加到草稿；取消会清空（`iOS/SpeechDraftModel.swift:43-61`、`iOS/SpeechDraftStrip.swift:17-20`） | 听写结束后直接把 partial 以空格拼到草稿；无独立草稿、无 “使用”/“取消” 控制（`Android/CmuxViewModel.kt:193-216`） | ❌ |
| C104 | 60 秒上限 + final 后 5 秒 finishing 兜底；8192 UTF-8 字节上限（`iOS/SpeechDraftModel.swift:28,32,49`） | 60 秒上限 + 8192 字节上限；无 finishing 兜底（`Android/speech/SpeechInput.kt:56-60,111-120`） | 🟡 |
| C105 | 语音错误经 `ErrorPresentation` 本地化（permission/unavailable/too_long/no_speech）（`iOS/ErrorPresentation.swift:47-49`、`iOS/SpeechDraftStrip.swift:16`） | 直接把稳定错误码 `speech_unavailable` 等显示在输入区下方，无本地化映射（`Android/CmuxViewModel.kt:209`、`Android/ui/ConversationScreen.kt:1038-1040`） | 🟡 |
| C106 | 发送失败会把文本和图片放回草稿；不会自动重发（`iOS/ConversationModel.swift:558-562`） | 发送失败草稿本来就未清空；图片也保留；不会自动重发（`Android/CmuxViewModel.kt:1760-1774`） | ✅ |
| C107 | 使用 `@FocusState`；点击会话清焦点；键盘由 `safeAreaInset` 顶起；滚动可收起键盘（`iOS/ConversationView.swift:54,283,420`、`iOS/ChatComposer.swift:63,80,90`） | `BasicTextField` 无 FocusRequester/键盘 action；键盘靠 `WindowInsets.safeDrawing` 整体收缩；无滚动/点击收起（`Android/ui/ConversationScreen.kt:984-997`、`Android/ui/AdaptiveRoot.kt:212`） | 🟡 |
| C108 | 只读时仍保留输入条，只是发送/语音禁用；上方显示 “Read only”（`iOS/ConversationView.swift:120-121`、`iOS/ChatComposer.swift:82,88,93`） | 只读时整个输入条被替换为 “这个会话当前只读” 并 `return`，不再渲染输入框（`Android/ui/ConversationScreen.kt:939-942`） | 🟡 |
| C109 | 可恢复时在输入区上方显示 “Resume” 按钮，输入条仍在（`iOS/ConversationView.swift:112-121`） | 显示 `ResumeBanner`，但输入条因只读被隐藏（`Android/ui/ConversationScreen.kt:190-192`、`Android/ui/SessionActions.kt:131-161`） | 🟡 |
| C110 | 权限门控：发送需 `canControlConversations`；模型/重命名/项目/Feed 分别按 capability 显示（`iOS/ConversationModel.swift:11,63`、`iOS/ConversationView.swift:581-590`） | 发送只看 `session.writable`；模型只看 writable && !working；重命名/项目/Feed 由回调是否传入决定，未检查 capability（`Android/ui/ConversationScreen.kt:131,255,364-371`、`Android/ui/AdaptiveRoot.kt:167,196`） | 🟡 |
| C111 | 无输入区 “后台任务运行中” 胶囊（后台任务在时间线外单独展示） | 输入区上方额外显示 “有后台任务在运行” 胶囊，依据是存在 `tool_use && status=="running"` 消息，而不是 `state.backgroundTasks`（`Android/ui/ConversationScreen.kt:929-937,257`） | ➕ |
| C112 | 输入区没有错误行；错误只出现在时间线 | 输入区下方再显示一份 `error`，与时间线错误重复（`Android/ui/ConversationScreen.kt:1035-1037,630-634`） | ➕ |

### 2.8 图片

| # | iOS 行为 | Android 现状 | 状态 |
| --- | --- | --- | --- |
| C113 | 支持相册和图片文件两种入口（`iOS/ConversationView.swift:125-135`、`iOS/ChatComposer.swift:71-72`） | 同样支持 Photo Picker 和 OpenDocument（`Android/ui/AdaptiveRoot.kt:101-106`、`Android/ui/ConversationScreen.kt:958-969`） | ✅ |
| C114 | 压缩：源 ≤32MiB；缩略图尺寸 1600/1200/800/400；质量 0.85/0.65/0.45/0.25；单图目标 ≤128KiB（`iOS/ImageAttachmentEncoder.swift:10-33`） | 压缩：源 ≤30MiB；最长边 1600、总像素 8,388,608；质量 85/75/65/55/45/35/25；单图目标 ≤512KiB（`Android/data/ChatImageStore.kt:19-48,168-178`） | 🟡 |
| C115 | 重新编码为 JPEG，剥离源元数据（`iOS/ImageAttachmentEncoder.swift:9-25`） | 重新编码为 JPEG，剥离元数据（`Android/data/ChatImageStore.kt:19-48,70-88`） | ✅ |
| C116 | 文件名过滤换行/NUL/反斜杠，UTF-8 前缀 230 字节，空则 `Image.jpg`（`iOS/ImageAttachmentEncoder.swift:26-29`） | 额外过滤 `/`，按 UTF-8 字节限制 230，trim 后空则 `Image.jpg`（`Android/data/ChatImageStore.kt:134-147`） | ✅ |
| C117 | 草稿缩略图 76×76、圆角 14（`iOS/ImageDraftStrip.swift:17-18`） | 草稿缩略图 56dp、圆角 10（`Android/ui/ConversationScreen.kt:201-202`） | 🟡 |
| C118 | 草稿图可点开预览页（`iOS/ImageDraftStrip.swift:15,31-39`） | 草稿图不可点击、无预览页（`Android/ui/ConversationScreen.kt:198-238`） | ❌ |
| C119 | 历史图片挂在对应消息上，逐图按钮（`iOS/MessageRow.swift:47-54`） | 所有历史图片集中显示在时间线末尾（`Android/ui/ConversationScreen.kt:562-581`） | ❌ |
| C120 | 历史图片校验：≤524,288 字节、必须 JPEG、单帧、宽高 >0 且 ≤1600（`iOS/HistoricalImageModel.swift:23-27`） | 只校验 ≤512KiB 且 JPEG 魔数；维度不校验，预览解码整张 bitmap（`Android/data/ChatImageStore.kt:50-68,160-161`、`Android/ui/ImagePreview.kt:64-71`） | 🟡 |
| C121 | 图片预览底部操作：复制图片到剪贴板 + 分享（`iOS/HistoricalImageView.swift:21-24`） | 图片预览只提供分享，无复制图片（`Android/ui/ImagePreview.kt:94-104`；`grep setImage` 无匹配） | 🟡 |
| C122 | 缩放：pinch 1–6，双击 2.5 倍；平移被限制在图片边界内；spring 0.28/0.86 动画（`iOS/ZoomableImage.swift:9,17-33,56-66`） | 缩放：pinch 1–6，双击 3 倍；平移不限制边界；无动画（`Android/ui/ImagePreview.kt:133-170`） | 🟡 |
| C123 | 预览错误 + “Refresh” 重试（`iOS/HistoricalImageView.swift:26-29`） | 预览错误 + “重试”（`Android/ui/ImagePreview.kt:107-132,364-373`） | ✅ |
| C124 | 离开页面/进入后台时 suspend 读取并取消请求（`iOS/HistoricalImageView.swift:33-35`、`iOS/HistoricalImageModel.swift:15`） | `closeImage()` 只把状态置空，已发出的读取继续（`Android/CmuxViewModel.kt:1252-1254`） | 🟡 |
| C125 | 已发送气泡显示图片数量 “N images”（`iOS/OutgoingPromptRow.swift:12-14`） | 已发送气泡只有文本，无图片数量（`Android/ui/ConversationScreen.kt:545-560`） | ❌ |
| C126 | 缩略图/历史图解码在后台/离主线程（`iOS/ImageAttachmentEncoder.swift:9`） | 图片预览解码在 `Dispatchers.Default`（`Android/ui/ImagePreview.kt:64-71`） | ✅ |

### 2.9 后台任务

| # | iOS 行为 | Android 现状 | 状态 |
| --- | --- | --- | --- |
| C127 | 后台任务栏：一行 “N 个后台任务正在运行” + 齿轮图标；点击展开逐任务列表；再点任务打开 Sheet（`iOS/BackgroundTasksBar.swift:17-49`） | 后台任务栏：横向滚动胶囊列表，每个胶囊显示 tool 名 + 运行/静止圆点；点击直接打开 Sheet（`Android/ui/BackgroundTasks.kt:45-83`） | 🟡 |
| C128 | 栏位在输入区上方，任何非空后台任务时显示（`iOS/ConversationView.swift:101-102`） | 同样位于时间线下方、输入区上方（`Android/ui/ConversationScreen.kt:179-189`） | ✅ |
| C129 | 任务详情若为 Agent：用 `MessageRows` 渲染完整对话，与主时间线同节奏（`iOS/BackgroundTaskSheet.swift:52-63`） | 任务详情统一渲染为原始文本块，Agent 任务也不渲染消息卡（`Android/ui/BackgroundTasks.kt:133-158`、`Android/CmuxViewModel.kt:1256-1300`） | ❌ |
| C130 | 命令任务：显示 “Command” 卡片 + 等宽输出；可继续加载下一页（`iOS/BackgroundTaskSheet.swift:65-82`） | 只有原始文本；无 command 卡片（`Android/ui/BackgroundTasks.kt:133-158`） | 🟡 |
| C131 | 运行中显示 spinner、“Running”、总字节数（`iOS/BackgroundTaskSheet.swift:84-92`） | 无运行中状态行、无字节数（`Android/ui/BackgroundTasks.kt:91-194`） | ❌ |
| C132 | 分页：Agent 对话可向上加载更早（`before_seq`），命令输出可向前加载更多（`iOS/BackgroundTaskSheet.swift:54-61,167-181`） | 只有 “加载更多” 向前翻页，无向上加载更早（`Android/ui/BackgroundTasks.kt:159-175`、`Android/CmuxViewModel.kt:1302-1344`） | 🟡 |
| C133 | 缓存包含完整 snapshot、命令、文本、offset、字节数、running 状态（`iOS/BackgroundTaskSheet.swift:118-134`、`iOS/BackgroundTaskCache.swift`） | 缓存只有 tool/summary/running/text/nextOffset/storedAt，无消息快照（`Android/data/BackgroundTaskCache.kt:29-38,99-118`） | 🟡 |
| C134 | 打开 Sheet 后订阅对该任务路径的 changes，持续跟随增长，并滚到底部（`iOS/BackgroundTaskSheet.swift:107-113,183-191,93-98`） | 打开时读一次缓存 + 一次网络；之后只能手动 “加载更多”，无自动跟随（`Android/CmuxViewModel.kt:1256-1298`） | ❌ |
| C135 | 任务详情是 `NavigationStack` Sheet，标题为 summary/tool（`iOS/BackgroundTaskSheet.swift:37-114`） | 任务详情是 Material `ModalBottomSheet`，标题为 tool + summary（`Android/ui/BackgroundTasks.kt:89-194`） | 🟡 |

### 2.10 连接、错误、菜单、只读、无障碍与视觉

| # | iOS 行为 | Android 现状 | 状态 |
| --- | --- | --- | --- |
| C136 | 顶部连接条：connecting 显示 spinner + “Reconnecting”；disconnected 显示 wifi 感叹号 + 文案 + Retry；白色胶囊、40pt 高、0.2s 动画（`iOS/ConnectionStatusBar.swift:11-38`、`iOS/ConversationView.swift:78-86`） | 只有离线红色条：`errorContainer` 全宽、错误文案 + 重试；没有 connecting 状态，也没有胶囊样式（`Android/ui/ConversationScreen.kt:139-163`） | 🟡 |
| C137 | 标题下方副标题：agent · model · hostName（`iOS/ConversationView.swift:571-578`） | 副标题：agent · model · workspaceID 前 8 位 · 状态标签（working/resumable/read-only）（`Android/ui/ConversationScreen.kt:299-313`） | 🟡 |
| C138 | 模型菜单：支持自定义模型、菜单说明、每项 detail、当前项 checkmark；busy/working/pending 时禁用（`iOS/AgentModelMenu.swift:19-52`、`iOS/ConversationView.swift:573-578`） | 模型菜单：简单 `DropdownMenu`，无自定义、无说明/detail、当前项仅文字变 accent；禁用条件只有 writable && !working（`Android/ui/SessionActions.kt:43-90`、`Android/ui/ConversationScreen.kt:131,352-354`） | 🟡 |
| C139 | 模型列表每次进入页面和回到前台都重新读取（`iOS/ConversationView.swift:189`、`iOS/ConversationModel.swift:474-484`） | 只在打开会话时读一次（`Android/ui/AdaptiveRoot.kt:134`、`Android/CmuxViewModel.kt:1516-1522`） | 🟡 |
| C140 | 模型切换需确认时弹系统 Alert（`iOS/ConversationView.swift:148-153`） | `model_confirm_required` 时弹 Material `AlertDialog`（`Android/ui/ConversationScreen.kt:275-296`、`Android/CmuxViewModel.kt:1553-1560`） | ✅ |
| C141 | 更多菜单：Rename、Conversation time、Project、Feed、Refresh、Stop、Force stop；按 capability 显示（`iOS/ConversationView.swift:580-592`） | 更多菜单：Rename、Project changes、Run time、Stop、Force stop；无 Feed、无 Refresh（`Android/ui/ConversationScreen.kt:363-382`） | 🟡 |
| C142 | 重命名：Alert + 文本框 + 说明；仅 `conversationControl` 时出现（`iOS/ConversationView.swift:154-158,580-583`） | `AlertDialog` + OutlinedTextField；空白或未改名的保存按钮禁用；没有说明文案；不检查 capability（`Android/ui/SessionActions.kt:94-127`、`Android/ui/ConversationScreen.kt:364-366`） | 🟡 |
| C143 | 强制停止：危险确认 Alert，调用 `interrupt(hard: true)`（`iOS/ConversationView.swift:183-186,590`） | 危险确认 `AlertDialog`，调用 `forceStop()`（`Android/ui/ConversationScreen.kt:385-401`、`Android/CmuxViewModel.kt:1781`） | ✅ |
| C144 | 待发送/结果未知：footnote 两按钮 “Check / Inspected”，仅 `pendingSend != nil || recoveryFailed` 且 !busy 时显示（`iOS/ConversationView.swift:95-100`） | 卡片式 `PendingSendBanner`：标题/说明/“查询回执”/“已经查看过”（`Android/ui/ConversationScreen.kt:242-248,830-872`） | 🟡 |
| C145 | 待发送记录按 `operationRecoveryScope + sessionID` 持久化（`iOS/ConversationModel.swift:152-154`、`iOS/PendingSendStore.swift:11,27`） | `pendingOperation` 存在全局 SharedPreferences key，未按 host/session 区分；所有会话读同一个值（`Android/CmuxViewModel.kt:1645`、`Android/ui/AdaptiveRoot.kt:198`） | ❌ |
| C146 | 结果未知时 outgoing 进入 `.unconfirmed` 橙色 “Delivery not confirmed” 状态（`iOS/OutgoingPromptRow.swift:31-33`、`iOS/ConversationModel.swift:557`） | 发送异常直接 `outgoingFailed = true`，显示红色 “未送达”，未区分 “结果未知”（`Android/ui/ConversationScreen.kt:549-557`、`Android/CmuxViewModel.kt:1632-1635,1770-1773`） | 🟡 |
| C147 | 发送期间有 pendingSend 时禁止再次发送（`iOS/ConversationModel.swift:530,536`） | `send()` 不检查 `pendingOperation`，可在结果未知时再次发送并覆盖记录（`Android/CmuxViewModel.kt:1753-1764`） | 🟡 |
| C148 | 初始加载：页中央 overlay + “Loading conversation…” 文案（`iOS/ConversationView.swift:72,439-443`、`chat.loading`） | 时间线顶部一个 spinner item，无居中、无文案（`Android/ui/ConversationScreen.kt:470-475`） | 🟡 |
| C149 | 空态：`ContentUnavailableView` + 气泡图标 + “Start a conversation”（`iOS/ConversationView.swift:236-238`） | 一行灰色文本 “还没有消息。”（`Android/ui/ConversationScreen.kt:477-481`） | 🟡 |
| C150 | 超长会话被截断时显示 “This conversation is long; earlier messages are not shown.”（`iOS/ConversationView.swift:235`） | `ConversationSnapshot.clipped` 在网络/存储层存在，但 `ConversationUi` 无该字段，UI 不显示截断提示（`grep clipped` 只命中 data 层；`Android/data/BridgeRepository.kt:83,235`、`Android/CmuxViewModel.kt:80-107`） | ❌ |
| C151 | 错误本地化覆盖约 40 个稳定 code，未知 code 加 `[code]` 前缀并记录诊断（`iOS/ErrorPresentation.swift:17-68`） | 本地化约 20 个 code，未知 code 回退到 Bridge 的英文句子或 code（`Android/CmuxViewModel.kt:1880-1905`） | 🟡 |
| C152 | 无障碍标识丰富：`chat.back`、`chat.more`、`chat.composer`、`chat.send`、`chat.stop`、`message.<id>`、`tool.disclosure.<id>`、`activity.<id>`、`response.copy/share/quote/select`、`voice.draft`、`image.draft.<id>` 等（`iOS/ConversationView.swift:555,570,593`、`iOS/MessageRow.swift:41`、`iOS/ToolDisclosure.swift:25`、`iOS/ActivityGroupView.swift:62`、`iOS/ResponseFooter.swift:18-24`、`iOS/ChatComposer.swift:67,76,82,88,93`） | 基本只有 contentDescription；没有 testTag/语义 identifier。`ToolStatusDot` 设置了状态 contentDescription，chevron 设置了展开/折叠描述（`Android/ui/ConversationScreen.kt:359,953,1000,1028`、`Android/ui/ToolCards.kt:125,189,218`） | 🟡 |
| C153 | 展开状态通过 `accessibilityValue("Expanded/Collapsed")` 暴露（`iOS/ToolDisclosure.swift:25`、`iOS/ActivityGroupView.swift:62`） | 展开状态只在 chevron 的 contentDescription 中（`Android/ui/ToolCards.kt:125,189`） | 🟡 |
| C154 | 浮动图标按钮统一 44pt 触控目标（`iOS/FloatingIconStyle.swift:4-22`） | 返回 36dp、更多 20dp、语音 20dp、发送 34dp；触控目标明显更小（`Android/ui/ConversationScreen.kt:340,361,1007,1019`） | 🟡 |
| C155 | 配色：accent #335CF5、白底、`MobileDesign` 统一 pageInset/radius/shadow（`iOS/MobileDesign.swift:5-13`） | 配色：accent #335CF5、白底、相同语义 token（`Android/ui/theme/MobileDesign.kt:6-21`） | ✅ |
| C156 | 强制浅色模式（`iOS/ConversationView.swift:194`、`iOS/WhitePage.swift:34`） | 强制 `lightColorScheme`（`Android/ui/theme/CmuxTheme.kt:13-23,59-64`） | ✅ |
| C157 | 字体以 Dynamic Type 文本样式为主：body/subheadline/caption/footnote（`iOS/MessageRow.swift:28,38`、`iOS/ChatComposer.swift:63`） | 固定 sp：正文 16sp、气泡 14sp、标签 12sp、代码 12/13sp（`Android/ui/theme/CmuxTheme.kt:25-56`、`Android/ui/ConversationScreen.kt:732,988`） | 🟡 |
| C158 | 动画细节多：输入条展开 0.18s、活动组折叠 0.18s、后台任务栏 snappy 0.18s、最新按钮 withAnimation、图片 spring（`iOS/ChatComposer.swift:59`、`iOS/ActivityGroupView.swift:96`、`iOS/BackgroundTasksBar.swift:19`、`iOS/ConversationView.swift:551`、`iOS/ZoomableImage.swift:32`） | 除 FAB 的 `animateScrollToItem` 和 Material 默认 ripple 外，无对话页自定义动画（`Android/ui/ConversationScreen.kt:639`） | 🟡 |
| C159 | 工具卡：`Color(white:0.975)`、圆角 22、0.035 黑描边 0.5、padding 16（`iOS/ToolDetailCard.swift:42-44`） | 工具代码卡：`MobileDesign.Code`（#F1F3F7）、圆角 14、padding 16，无描边（`Android/ui/ToolCards.kt:229-235`、`Android/ui/theme/MobileDesign.kt:15`） | 🟡 |
| C160 | 问题/权限/附件卡使用统一 FloatingSurface：白底、圆角 22、阴影 radius14 y4、描边 0.5（`iOS/FloatingSurface.swift:4-11`） | 问题卡用 `Soft` 圆角 14；权限用工具行 `Soft` 圆角 12；附件为纯文本（`Android/ui/ConversationScreen.kt:881-883,793,702-706`） | 🟡 |

### 2.11 合并、缓存与读取节奏

| # | iOS 行为 | Android 现状 | 状态 |
| --- | --- | --- | --- |
| C161 | 增量历史合并按 message id 去重、按 seq 排序；generation 变化则整体替换（`iOS/ConversationModel.swift:380-390`） | `ConversationMerge.messages` 同样按 id 去重、按 seq 排序；generation 不同则替换（`Android/data/ConversationMerge.kt:12-19`、`Android/CmuxViewModel.kt:1149-1156`） | ✅ |
| C162 | responses 按 `firstMessageID` 合并；images 按 generation + messageID 合并（`iOS/ConversationModel.swift:397-403`） | 同样的 responses/images 合并规则（`Android/data/ConversationMerge.kt:21-42`） | ✅ |
| C163 | 打开会话先展示 SQLite 存储副本，再网络刷新；限制 512MiB/128MiB/24 会话/60,000 消息（`iOS/ConversationModel.swift:182-203`、`iOS/ConversationStore.swift:16-21`） | 同样先恢复 SQLite 副本，再网络读取；限制数值相同（`Android/CmuxViewModel.kt:1043-1061`、`Android/data/ConversationStore.kt:38-43`） | ✅ |
| C164 | 首屏后后台回填最多 64 页（`iOS/ConversationModel.swift:300-326`） | 同样最多 64 页，每页 100（`Android/CmuxViewModel.kt:1097-1122,1921`） | ✅ |
| C165 | 60 秒内刷新用 tail 读 30 条，否则整页；另有预览并行读取（`iOS/ConversationModel.swift:84-89,346-354`） | 每次 `reloadOpen` 都读完整 history + sessions + feed，无 tail 优化（`Android/CmuxViewModel.kt:1921-1930`） | 🟡 |

### 2.12 本域 Android 独有

- 自适应多栏对话布局：Compact 单栏、TwoPane、ThreePane、Tabletop 半折叠；三栏右侧 `SupportingPane` 展示最后一条 file_edit/diff（`Android/ui/AdaptiveRoot.kt:328-468`、`Android/ui/TabletopScreen.kt:136-159`）。
- Tabletop 半开模式：上半屏对话、下半屏固定待决策/输入区，输入区不显示语音、图片、后台任务（`Android/ui/TabletopScreen.kt:37-79`）。
- 后台任务横向胶囊列表：每个任务一个 tool 名胶囊，运行中显示 spinner（`Android/ui/BackgroundTasks.kt:44-83`）。
- 输入区 “后台任务运行中” 胶囊：由 running 的 `tool_use` 消息推导（`Android/ui/ConversationScreen.kt:929-937,257`）。
- 只读时完全隐藏输入框，用一行 “这个会话当前只读” 替代（`Android/ui/ConversationScreen.kt:939-942`）。
- “查看全部 N 个操作” 胶囊：长活动组不进入组页，而是打开最后一条工具详情（`Android/ui/ToolCards.kt:138-150`、`Android/ui/ConversationScreen.kt:536`）。
- 工具状态圆点 + 仅 contentDescription 的状态文字（`Android/ui/ToolCards.kt:200-220`）。
- 全局（跨会话）待发送记录：`pendingOperation` 使用全局 SharedPreferences，不分 host/session（`Android/CmuxViewModel.kt:1645`）。
- 图片预览仅分享、双击 3 倍、平移不夹边界（`Android/ui/ImagePreview.kt:94-104,133-170`）。
- 选文页顶部右侧 “复制/已复制” 按钮（`Android/ui/TextAndTiming.kt:86-100`）。
- 后台任务详情使用 Material ModalBottomSheet + 纯文本输出（`Android/ui/BackgroundTasks.kt:89-194`）。
- 模型菜单是头部右侧独立胶囊（`Android/ui/SessionActions.kt:43-90`、`Android/ui/ConversationScreen.kt:352-354`）。
- 副标题显示 workspaceID 前 8 位和状态标签（`Android/ui/ConversationScreen.kt:299-313`）。
- 图片压缩单图预算 512KiB（iOS 为 128KiB）（`Android/data/ChatImageStore.kt:170`、`iOS/ImageAttachmentEncoder.swift:25`）。
- Markdown 表格使用圆角 Soft 卡片背景、等宽列、88dp 横向滚动阈值（`Android/ui/markdown/MarkdownText.kt:342-364`）。
- Markdown 代码块默认横向滚动（iOS 默认换行）（`Android/ui/markdown/MarkdownText.kt:264-280`、`iOS/MarkdownMessageView.swift:10-16`）。
- 下拉刷新使用 `PullToRefreshBox`（`Android/ui/ConversationScreen.kt:458-463`）。
- 附件菜单内含 Feed 入口，但头部更多菜单没有 Feed（`Android/ui/ConversationScreen.kt:976-981,363-382`）。
- 输入区下方重复显示错误（`Android/ui/ConversationScreen.kt:630-634,1035-1037`）。
- 图片-only 无法从 UI 发送（当前实现限制）（`Android/ui/ConversationScreen.kt:1017-1023`）。
- 滚动/初始定位按 `messages.size` 当作 LazyColumn item 索引（当前实现缺陷，`Android/ui/ConversationScreen.kt:441,639`）。

## 3. 配对、中转、连接与诊断

> 编号前缀 **P**。路径别名同第 2 节；另 `iOSRes/` = `ios/Resources/`，`ARes/` = `android/app/src/main/res/`。

### 3.1 配对入口、首屏与添加 Mac

| # | iOS 行为 | Android 现状 | 状态 |
| --- | --- | --- | --- |
| P1 | 无已配对 Mac 时根视图直接显示 `PairingView`（`iOS/CmuxRemoteApp.swift:18-19`） | 先进入 `Restoring`，恢复后无连接才进入 `Pairing`（`Android/CmuxViewModel.kt:548-555`、`Android/ui/AdaptiveRoot.kt:239-263`） | 🟡 |
| P2 | 首屏无退出入口，`dismissal: .none`（`iOS/PairingView.swift:20`） | 首屏 `PairingScreen` 不传 `onBack`；只有 `onBack != null` 才画返回键（`Android/ui/AdaptiveRoot.kt:244-262`、`Android/ui/PairingScreen.kt:100-112`） | ✅ |
| P3 | 无独立 “恢复中” 页面 | 独立 `ShellState.Restoring` 且居中转圈（`Android/CmuxViewModel.kt:41-43`、`Android/ui/AdaptiveRoot.kt:240`） | ➕ |
| P4 | 添加第二台 Mac：抽屉 “Add Device” 和标题菜单都可进入，配对页以 `fullScreenCover` 覆盖列表（`iOS/SessionSidebarView.swift:81-82`、`iOS/SessionTitleMenu.swift:30`、`iOS/SessionListView.swift:167,177`） | 标题菜单/抽屉/侧栏均调用 `setAddingDevice(true)`，`addingDevice` 时覆盖 `PairingScreen`（`Android/ui/AdaptiveRoot.kt:304,311,340-341,553-586`、`Android/ui/SessionListChrome.kt:142`） | ✅ |
| P5 | 添加页右上角关闭 X，另有自定义返回（`iOS/PairingView.swift:20-21`） | 只有左上返回箭头 + 系统 BackHandler（`Android/ui/PairingScreen.kt:100-112`、`Android/ui/AdaptiveRoot.kt:554,583`） | 🟡 |
| P6 | 无 “重试已保存连接” 按钮；启动时自动恢复（`iOS/AppModel.swift:92-113`） | 配对页底部有 “已经配过对？重试已保存的连接”（`Android/ui/PairingScreen.kt:317-319`、`Android/ui/AdaptiveRoot.kt:247,569`） | ➕ |
| P7 | 保留旧版共享 token 配对：高级区可手工填 host/port/token/fingerprint、导入旧 JSON，`legacyEnabled` 显式迁移（`iOS/PairingView.swift:99-129`、`iOS/PairingStore.swift:9-11,35-62`、`iOS/AppModel.swift:109-112`） | 完全没有旧版共享 token 路径；`cmux-remote://pair`、`pair_host/pair_port/pair_token` 均未找到，只有单连接文件迁移（`Android/data/ConnectionStore.kt:35-38`） | ❌ |
| P8 | 已批准 Mac 上限 16，超出抛 `pairing_capacity`（`iOS/PairingStore.swift:27`；该码未在错误映射中 `iOS/ErrorPresentation.swift:61-67`） | 无数量上限（`Android/data/ConnectionStore.kt:42-46`） | ❌ |
| P9 | 首屏标题 + `macbook.and.iphone` 图标、说明两段（`iOS/PairingView.swift:24-27`） | 顶部 Laptop 图标 + `pair_title` + `pair_description`（`Android/ui/PairingScreen.kt:113-121`） | 🟡 |
| P10 | 登记设备名/类型固定为 `cmux iPhone` / `iphone`（`iOS/AppModel.swift:80`） | 默认 `cmux Android` / `android`，旧 Bridge 失败后回退 `iphone`（`Android/bridge/Enrollment.kt:267-268`、`Android/CmuxViewModel.kt:593-597`） | 🟡 |
| P11 | 请求 7 项能力，旧 Bridge 回退 6 项（去掉 conversationStart）（`Sources/CmuxRemoteClient/EnrollmentClient.swift:12-14`） | 同样 7 项 / 6 项（`Android/bridge/Enrollment.kt:81-95`） | ✅ |
| P12 | 字符串基线为英文 + zh-Hans（`iOSRes/en.lproj/Localizable.strings:1-14`、`iOSRes/zh-Hans.lproj/Localizable.strings:1-14`） | 默认 `values/strings.xml` 是中文，`values-en` 才是英文；其它语言回退中文（`ARes/values/strings.xml:71-110`、`ARes/values-en/strings.xml:71-110`） | 🟡 |
| P13 | 配对相关句子全部走本地化 key | 部分状态消息硬编码英文/中文（`Android/CmuxViewModel.kt:667-668,675,680`） | ❌ |

### 3.2 扫码、粘贴、附近发现与中转目录

| # | iOS 行为 | Android 现状 | 状态 |
| --- | --- | --- | --- |
| P14 | 扫码按钮 + 说明，置于附近发现之前（`iOS/PairingView.swift:28-33`） | 扫码按钮 + 说明（`Android/ui/PairingScreen.kt:135-152`） | ✅ |
| P15 | AVFoundation 裸相机、主线程持有，只交付一个字符串，无取景框/变焦/补光（`iOS/QRScannerController.swift:14-44`、`iOS/QRScannerView.swift:5-9`） | CameraX + ML Kit，另有取景框、点按对焦、数码变焦、补光、顶部白色胶囊标题栏（`Android/ui/QrScannerScreen.kt:152-366,369-407,475-513`） | ➕ |
| P16 | 相机不可用显示居中本地化文字（`iOS/QRScannerController.swift:40-44`） | 无相机/权限拒绝显示同类居中文字（`Android/ui/QrScannerScreen.kt:101-125,142-144,516-531`） | ✅ |
| P17 | 扫描结果：`cmux-remote://enroll` 走新登记，否则按旧版 v1 配对码解码（`iOS/PairingView.swift:53-59`、`Core/PairingLinkCodec.swift:11-19`） | 所有扫描结果统一进 `pair(code)`，只接受 v2 链接或登记 JSON（`Android/ui/AdaptiveRoot.kt:588-595`、`Android/CmuxViewModel.kt:576-603`、`Android/bridge/Enrollment.kt:32-63`） | 🟡 |
| P18 | v2 码校验用 `URLComponents`：scheme/host/path 精确、查询项恰为 2、v=2、≤8192 字节（`Core/Connection/EnrollmentLinkCodec.swift:10-16`） | 仅 `startsWith("cmux-remote://enroll")` + 查询参数恰为 2 + v=2 + ≤8192，不校验 host/path（`Android/bridge/Enrollment.kt:32-63`） | 🟡 |
| P19 | 高级区可粘贴链接/JSON，另有 “Fill connection fields” 解析旧版 `PairingConfiguration`（`iOS/PairingView.swift:110-120`、`iOS/AppModel.swift:195-205`） | 只能粘贴链接/登记 JSON 后 “导入并申请”，无填充按钮（`Android/ui/PairingScreen.kt:265-295`） | 🟡 |
| P20 | 高级区包含 host、port、token、fingerprint 四个文本框（`iOS/PairingView.swift:102-109`） | 未找到手工连接字段（只有证书字段 `connection_certificate_fingerprint`） | ❌ |
| P21 | 附近发现列表、空态 “搜索局域网……”、已批准项显示并禁用（`iOS/PairingView.swift:87-95,164-174`） | 同样列表/空态/已批准禁用，但空态文案更短、图标改为 Laptop/CheckCircle（`Android/ui/PairingScreen.kt:154-169,375-403`） | 🟡 |
| P22 | Bonjour 服务 `_cmux-remote._tcp`；TXT 必须含 version=2、hostID、publicKey、certificate、name，并校验 HostIdentity（`Sources/CmuxRemoteClient/BridgeDiscovery.swift:12-22`） | 同样服务类型与 version/hostID/publicKey/certificate 校验（`Android/bridge/Discovery.kt:21-40,61-107`） | ✅ |
| P23 | TXT 缺少 `name` 时丢弃该服务（`Sources/CmuxRemoteClient/BridgeDiscovery.swift:17`） | TXT 缺少 `name` 时回退为 serviceName（`Android/bridge/Discovery.kt:33`） | 🟡 |
| P24 | 结果按 host id 排序、最多 64 条，但不去重（`Sources/CmuxRemoteClient/BridgeDiscovery.swift:20-22`） | 以 host.id 为键去重后排序、最多 64 条（`Android/bridge/Discovery.kt:38-40,126`） | 🟡 |
| P25 | NWBrowser + NWConnection 解析，解析超时 8 秒（`Sources/CmuxRemoteClient/BridgeDiscovery.swift:32-55`） | NsdManager + MulticastLock；解析串行排队防 `FAILURE_ALREADY_ACTIVE`，无解析超时（`Android/bridge/Discovery.kt:57-59,70-75,114-136`） | 🟡 |
| P26 | 前台持续发现，且即使只是 “添加设备” 浮层也运行（`iOS/CmuxRemoteApp.swift:20-23`、`iOS/AppModel.swift:148-184`） | 仅配对页/添加浮层可见时启动 NSD，离开即停止并清空（`Android/ui/AdaptiveRoot.kt:136-145`、`Android/CmuxViewModel.kt:403-410`） | 🟡 |
| P27 | 发现到已配对 Mac 后解析新端点，校验 host 三元组与 `/v1/status`，迁移连接并保存（`iOS/AppModel.swift:165-182`、`Core/Connection/AuthorizedConnection.swift:23-29`） | 未找到已配对 Mac 的发现重定位（`grep relocat*` 于 Android 主代码无命中）；发现仅用于配对列表（`Android/bridge/Discovery.kt:122-133`） | ❌ |
| P28 | 附近发现登记时，签署 bootstrap 必须匹配广告 host 的 id/publicKey/certificate（`Sources/CmuxRemoteClient/EnrollmentBootstrapClient.swift:9-13`） | 同样三元组校验，否则 `host_changed`（`Android/bridge/Enrollment.kt:312-336`） | ✅ |
| P29 | 身份确认弹窗含说明、Mac 名、完整 host id 与 “身份一致，申请访问”（`iOS/PairingView.swift:41-49,65-68`） | 同样的确认弹窗与完整 id（`Android/ui/PairingScreen.kt:341-364`） | ✅ |
| P30 | 已批准行显示 `checkmark.seal` + Approved，并禁用（`iOS/PairingView.swift:93,147,171-172`） | 已批准行换成 CheckCircle、显示 “已连接” 并禁用（`Android/ui/PairingScreen.kt:160-168,189-197,384-402`） | ✅ |
| P31 | 等待批准卡片显示 clientID 前 12 位大写等宽字体 + 可展开完整 requestID/clientID（`iOS/PairingView.swift:71-85`） | 等待页只显示 requestID 前 8 位，无 clientID、无展开详情、无过期倒计时（`Android/ui/PairingScreen.kt:408-444`、`Android/CmuxViewModel.kt:648-654`） | ❌ |
| P32 | 等待批准时，附近发现和中转区被等待卡替代（`iOS/PairingView.swift:70-98`） | 等待批准时整页切换为 `AwaitingOwnerScreen`（`Android/ui/AdaptiveRoot.kt:265-271`） | 🟡 |
| P33 | 中转区标题、刷新图标、加载/空/错误、Mac 列表、可移除 origin、输入框（`iOS/PairingView.swift:134-162`） | 同样的区块，但刷新/移除为文字按钮，布局与空态文案不同（`Android/ui/PairingScreen.kt:171-249`） | 🟡 |
| P34 | 中转 origin 持久化上限 8 条，UserDefaults（`iOS/PairingStore.swift:33-34`） | SharedPreferences 保存，不设数量上限（`Android/CmuxViewModel.kt:386-390,416-447`） | 🟡 |
| P35 | `RelayOrigin` 会规范化：补 https、去尾部 `/`、去 443 端口、小写 host（`Core/Link/RelayOrigin.swift:6-12`） | `canonicalOrigin` 要求输入本身已是规范形式，否则拒绝（如显式 `:443`、大写 host）（`Android/bridge/RelayEndpoint.kt:109-127`） | 🟡 |
| P36 | 读 `/v3/directory`，限制 1 MiB / 64 条 / 每条 8 KiB，逐条验签并校验 relay origin 与有效期（`Sources/CmuxRemoteClient/RelayDirectoryClient.swift:9-30`） | 相同端点与限制、逐条验签/origin/有效期（`Android/bridge/RelayDirectory.kt:22-83`） | ✅ |
| P37 | 多 origin 串行读取，任一失败不隐藏其它结果；仅结果为空时显示错误（`iOS/AppModel.swift:131-141`） | 同样串行、失败不隐藏其它、仅空结果时报错（`Android/CmuxViewModel.kt:450-476`） | ✅ |
| P38 | 同一 host 出现多次时保留先读到的条目（`iOS/AppModel.swift:136`） | 同一 host 保留 `expiresAt` 更晚的条目（`Android/bridge/RelayDirectory.kt:79-81`、`Android/CmuxViewModel.kt:467-470`） | 🟡 |
| P39 | 列表按 `localizedStandardCompare` 排序（`Sources/CmuxRemoteClient/RelayDirectoryClient.swift:30`） | 按 `lowercase()` 排序（`Android/bridge/RelayDirectory.kt:82`） | 🟡 |

### 3.3 登记轮询、批准与撤销

| # | iOS 行为 | Android 现状 | 状态 |
| --- | --- | --- | --- |
| P40 | 登记请求/状态都走加密 link `/v2/enrollment/*`（`Sources/CmuxRemoteClient/EnrollmentClient.swift:25,42-45`） | 先直连 HTTPS `/v2/enrollment/*`，传输失败后同一签名请求改走中转 link（`Android/bridge/Enrollment.kt:165-205,207-239`） | 🟡 |
| P41 | 旧 Bridge 拒绝 conversationStart 时以 `outcome_unknown` 触发回退，去掉该能力重提（`iOS/AppModel.swift:216-224`） | 旧 Bridge 以 `invalid_enrollment` 触发回退，同时把 kind 改成 `iphone`（`Android/CmuxViewModel.kt:581-599,517-526,611-621`） | 🟡 |
| P42 | 前台轮询间隔 2 秒（`iOS/RefreshTicker.swift:7-12`） | 轮询间隔 1.5 秒（`Android/CmuxViewModel.kt:655-658`） | 🟡 |
| P43 | 无轮询次数上限，持续到过期或状态终结（`iOS/AppModel.swift:237-266`） | `repeat(200)`，约 300 秒后强制 `enrollment_expired`（`Android/CmuxViewModel.kt:655-673`） | 🟡 |
| P44 | 网络/链路错误按 `EnrollmentPollRetry` 重试，且窗口未过期；仍显示错误（`iOS/EnrollmentPollRetry.swift:7-14`、`iOS/AppModel.swift:259-264`） | 状态轮询异常立即结束并显示错误，不重试（`Android/CmuxViewModel.kt:674-682`） | ❌ |
| P45 | 退后台暂停轮询，回前台恢复（`iOS/AppModel.swift:233,268`、`iOS/CmuxRemoteApp.swift:22-23`） | 无生命周期观察，轮询只随 ViewModel/页面任务存活（`Android/MainActivity.kt:11-38`、`Android/CmuxViewModel.kt:1910-1915`） | ❌ |
| P46 | 取消会向 Mac 发送 cancel 并关闭 enrollment 传输（`iOS/AppModel.swift:270-274`） | `cancelPairing()` 只取消本地 poll，不发送 cancel、不关闭 relay link（`Android/CmuxViewModel.kt:695-703`） | ❌ |
| P47 | `denied/expired/cancelled/revoked` 统一显示本地化 `pair.enrollment_ended`（`iOS/AppModel.swift:258`、`iOSRes/en.lproj/Localizable.strings:69`） | 生成 `enrollment_denied/cancelled/revoked` 等码，但消息固定英文且这些码没有本地化映射（`Android/CmuxViewModel.kt:663-670,1880-1908`） | ❌ |
| P48 | 批准后先用新连接请求 `/v1/status`，成功才保存并安装 link（`iOS/AppModel.swift:247-256`） | 校验 grant 后直接保存并连接，没有批准后可达性探测（`Android/CmuxViewModel.kt:705-739`） | 🟡 |
| P49 | grant 校验 requestID/nonce/host/scope/签名，并核验批准范围是请求子集（`Sources/CmuxRemoteClient/EnrollmentClient.swift:31-38`） | grant 校验同样字段与子集关系（`Android/bridge/Enrollment.kt:124-154`） | ✅ |
| P50 | 配对失败显示内联红字；扫码格式错误写 `pair.invalid`（`iOS/PairingView.swift:36-37,58`） | 内联错误/notice 之外，还有独立 Failed 页面显示稳定码 + 消息（`Android/ui/PairingScreen.kt:311-319,446-464`、`Android/ui/AdaptiveRoot.kt:273-275`） | 🟡 |
| P51 | 撤销只在手机侧移除，Mac 端仍需单独撤销（`iOS/AppModel.swift:454-465`、`iOSRes/en.lproj/Localizable.strings:272`） | 同样只删本地，Mac 端需单独撤销（`Android/CmuxViewModel.kt:319-349`、`ARes/values/strings.xml:271`） | ✅ |
| P52 | 没有 “重置本机身份” 入口；设备身份生成一次后长期保留（`iOS/DeviceIdentityStore.swift:5-9`；`grep resetIdentity` 无命中） | 有 “重置本机身份”，删除身份、所有 Mac、对话/任务缓存并回到配对页（`Android/CmuxViewModel.kt:478-509`、`Android/ui/PairingScreen.kt:296-307,322-338`） | ➕ |

### 3.4 连接监督、中转拨号与连接详情

| # | iOS 行为 | Android 现状 | 状态 |
| --- | --- | --- | --- |
| P53 | 每台 Mac 独立 `linkStates`，另有 `quietHosts` 隐藏后台重试（`iOS/AppModel.swift:26-36`、`iOS/AppModel+Connection.swift:8-17`） | 只有全局 `reachable/probed` 布尔（`Android/CmuxViewModel.kt:242-246,996-997`） | ❌ |
| P54 | 重连退避 2/4/8/16/32 秒，展示 3 次后静默；工作链路掉线立即重拨（`iOS/ReconnectSchedule.swift:32-43,69-81`） | LiveUpdates 退避 1/2/4/8/16/30 秒，无静默、无 “工作链路刚掉线” 区分（`Android/bridge/LiveUpdates.kt:89-92,56-71`） | 🟡 |
| P55 | `NWPathMonitor` 在网络恢复/切换 Wi-Fi/蜂窝时重拨所有 Mac（`iOS/NetworkPathMonitor.swift:5-20`、`iOS/AppModel+Connection.swift:76-83`） | 未找到 ConnectivityManager/NetworkCallback，无网络路径变化重拨 | ❌ |
| P56 | 从后台回前台时若 `backgroundedAt` 存在则全量重拨（`iOS/AppModel+Connection.swift:45-55`） | MainActivity 只有 `onCreate`，无生命周期观察（`Android/MainActivity.kt:11-38`） | ❌ |
| P57 | 监督任务按 `phase + hosts` 重启，始终跟随所有 Mac（`iOS/CmuxRemoteApp.swift:26-33`、`iOS/AppModel.swift:344-370`） | live link 只服务当前 `repository`，`open(hosted)` 不重建 link（`Android/CmuxViewModel.kt:742-781,905-912,1023-1030`） | ❌ |
| P58 | 抽屉逐台显示 Mac，可进入任意 Mac 的连接详情（`iOS/SessionSidebarView.swift:70-79`、`iOS/SessionListView.swift:170-175`） | `openConnection()` 无参数，只展示当前 `_connection`，非当前 Mac 不可达（`Android/CmuxViewModel.kt:307-308`、`Android/ui/AdaptiveRoot.kt:477-503`） | ❌ |
| P59 | 详情显示 Mac 名、endpoint、`/v1/status` 返回的 protocol、host id、证书指纹（`iOS/ConnectionDetailView.swift:22-31,56-68`） | 显示 Mac 名、endpoint、硬编码 `v2 HTTPS · link v3`、host id、证书指纹（`Android/ui/ConnectionDetailScreen.kt:160-167`、`Android/ui/AdaptiveRoot.kt:482-485`） | 🟡 |
| P60 | 可达性探测是 `/v1/status`，打开页面与下拉刷新都会执行（`iOS/ConnectionDetailView.swift:24,52,64-68`） | 可达性探测是 `/v2/identity`（`repository.probe()`），打开页面时执行（`Android/CmuxViewModel.kt:277-291`、`Android/data/BridgeRepository.kt:199-205`） | 🟡 |
| P61 | 不显示传输方式（直连/中转） | 有独立 “传输” 卡片：局域网直连 / 通过中转（`Android/ui/ConnectionDetailScreen.kt:171-184`、`Android/ui/AdaptiveRoot.kt:488`） | ➕ |
| P62 | 不显示设备身份密钥的保护状态 | 有 “密钥” 卡片，显示 Keystore 保护或仅应用私有文件（`Android/ui/ConnectionDetailScreen.kt:186-209`、`Android/security/KeyVault.kt:51-56`） | ➕ |
| P63 | Mac 名作为标题（laptop 图标 + title3 semibold）（`iOS/ConnectionDetailView.swift:22`） | Mac 名在 HostCard 中（laptop 图标 + titleLarge）（`Android/ui/ConnectionDetailScreen.kt:282-297`） | ✅ |
| P64 | 能力列表按 `ClientCapability.allCases` 顺序，过滤 `client.allows`，每项带勾（`iOS/ConnectionDetailView.swift:32-37`、`Core/Connection/ClientCapability.swift:4-8`） | 按 `CapabilityOrder` 排序，`conversationStart` 排在 terminal 之前，未知能力附后（`Android/ui/ConnectionDetailScreen.kt:72-104,357-389`） | 🟡 |
| P65 | 后台同步开关 + 说明，说明含 “每次最多 3 个对话”（`iOS/ConnectionDetailView.swift:39-43`、`iOSRes/en.lproj/Localizable.strings:317`） | 开关 + 说明，但文案不写每次几个对话（`Android/ui/ConnectionDetailScreen.kt:211-238`、`ARes/values-en/strings.xml:272`） | 🟡 |
| P66 | 刷新按钮 + 下拉刷新（`iOS/ConnectionDetailView.swift:45,51`） | 只有刷新按钮，无下拉刷新（`Android/ui/ConnectionDetailScreen.kt:150-157,240-247`） | 🟡 |
| P67 | 诊断日志入口（`iOS/ConnectionDetailView.swift:46,54`） | 诊断日志入口（`Android/ui/ConnectionDetailScreen.kt:242`、`Android/ui/AdaptiveRoot.kt:507-510`） | ✅ |
| P68 | “移除这台 Mac” 立即执行，无确认框（`iOS/ConnectionDetailView.swift:47-48`） | 先弹确认框，再移除（`Android/ui/ConnectionDetailScreen.kt:243-247,257-278`） | 🟡 |
| P69 | 移除会关闭 client、清 perHost/error/pending、删对话缓存（`iOS/AppModel.swift:455-465`） | 移除会关 relay link、删 store、对话/任务缓存，空列表时取消后台同步（`Android/CmuxViewModel.kt:319-349`） | ✅ |
| P70 | 每次完整 refresh 后为每台 Mac 刷新 relay hint（`iOS/AppModel.swift:328-331`、`iOS/RemoteClientRuntime.swift:69-80`） | 仅在 `connect`、打开次级 Mac、连接页重试时刷新 relay hint（`Android/CmuxViewModel.kt:788-820,1023-1029,293-300`、`Android/data/BridgeRepository.kt:179-197`） | 🟡 |
| P71 | 有 relay 时 LAN 与 relay 同时竞速，先认证成功者胜出（`Sources/CmuxRemoteClient/LinkClientConnection.swift:100-105,206-230`） | 先 6 秒探测 LAN，失败后串行拨 relay；调试可 `forceRelay` 跳过（`Android/CmuxViewModel.kt:760-780,848-896`、`Android/bridge/LinkClient.kt:73-100`） | 🟡 |
| P72 | 只有 “LAN 不可达” 才允许转 relay；TLS pin/身份/协议错误绝不回退（`Sources/CmuxRemoteClient/LinkPathFailure.swift:4-13`、`Sources/CmuxRemoteClient/LinkClientConnection.swift:211-230`） | LAN 失败后仅 `host_changed`/`invalid_certificate` 不回退，其它 ProtocolException 都会尝试 relay（`Android/bridge/LinkClient.kt:86-97`） | 🟡 |
| P73 | 证书固定：仅信任配对时保存的叶证书 DER SHA-256，并核对 canonical host/port，禁止重定向（`Sources/CmuxRemoteClient/PinnedSessionDelegate.swift:10-17,28-31`） | 同样按 DER SHA-256 固定叶证书 + canonical host，禁止重定向（`Android/bridge/PinnedHttpClient.kt:27-49,68-84`） | ✅ |
| P74 | pin 失败取消 challenge，最终以网络类错误进入连接条/重试（`Sources/CmuxRemoteClient/PinnedSessionDelegate.swift:14-16`、`iOS/ErrorPresentation.swift:6-16`） | pin 失败在 link 上归为 `link_failed`；HTTPS 路径可能暴露原始 SSLHandshakeException，本地化映射较弱（`Android/bridge/LinkClient.kt:143-158`、`Android/bridge/BridgeClient.kt:153-185`） | 🟡 |
| P75 | `host_changed` 覆盖登记 bootstrap、`/v2/identity` 三元组、link acceptance、重定位 grant 一致性（`Sources/CmuxRemoteClient/EnrollmentBootstrapClient.swift:13`、`Sources/CmuxRemoteClient/RemoteClientRuntime.swift:119`、`Core/Connection/AuthorizedConnection.swift:23-29`） | `host_changed` 覆盖 `/v2/identity`、link acceptance、附近登记三元组、relay permit；无重定位逻辑（`Android/bridge/BridgeClient.kt:52-63`、`Android/bridge/LinkClient.kt:346-366`、`Android/bridge/Enrollment.kt:331-336`） | 🟡 |
| P76 | 会话页顶部有 connecting/disconnected 胶囊状态条，0.2s 动画，掉线可重试（`iOS/ConnectionStatusBar.swift:12-38`） | 仅一条全宽 errorContainer 横幅，仅离线态，无连接中动画（`Android/ui/ConversationScreen.kt:139-163`） | 🟡 |
| P77 | feed 变更立即刷新，sessions 变更至少间隔 8 秒（`iOS/AppModel.swift:344-370`） | 单链路变更 250ms 去抖刷新，另有列表 30s / 会话 15s 兜底轮询（`Android/CmuxViewModel.kt:917-945`） | 🟡 |

### 3.5 诊断日志

| # | iOS 行为 | Android 现状 | 状态 |
| --- | --- | --- | --- |
| P78 | 内存环形缓冲 500 条，四级别 debug/info/warning/error（`iOS/DiagnosticLog.swift:5-24`） | 同样 500 条与四级别（`Android/data/Diagnostics.kt:12-17,28-39`） | ✅ |
| P79 | 时间格式 `HH:mm:ss.SSS`；列表按时间倒序（`iOS/DiagnosticLogView.swift:6-11,24,65-67`） | 同样 `HH:mm:ss.SSS`，`entries()` 已倒序（`Android/data/Diagnostics.kt:22,41-42,60-61`、`Android/ui/DiagnosticLogScreen.kt:63,214-215`） | ✅ |
| P80 | 无脱敏、无单条长度上限（链接行只把 host 截前 8 位）（`iOS/DiagnosticLog.swift:37-39`；`grep redact` 无命中） | 32 字符以上的 base64/hex 样式串替换为 `[redacted]`，单条截断 512 字符（`Android/data/Diagnostics.kt:17-21,28-38,63`） | ➕ |
| P81 | “Copy All” 复制：build 头 + ISO 日期 + 每条 `[time] [level] [category] message`（`iOS/DiagnosticLogView.swift:45-53`） | “复制报告”：build + Android 版本 + 完整日期时间 + 每条同格式（`Android/data/Diagnostics.kt:49-58`、`Android/ui/DiagnosticLogScreen.kt:137-153`） | 🟡 |
| P82 | 复制后按钮显示 “Copied” 2 秒（`iOS/DiagnosticLogView.swift:51-52`） | 同样 2 秒（`Android/ui/DiagnosticLogScreen.kt:61,82-87,148`） | ✅ |
| P83 | 清空按钮（destructive）（`iOS/DiagnosticLogView.swift:35-37`） | 清空按钮（error 色描边）（`Android/ui/DiagnosticLogScreen.kt:154-169`） | ✅ |
| P84 | 未找到分享功能（仅 `UIPasteboard`）（`iOS/DiagnosticLogView.swift:45-53`） | 未找到分享功能（仅剪贴板）（`Android/ui/DiagnosticLogScreen.kt:137-153`） | ✅ |
| P85 | 下拉刷新刷新列表（`iOS/DiagnosticLogView.swift:40-41`） | 额外 “刷新” 按钮（`Android/ui/DiagnosticLogScreen.kt:170-182`） | ➕ |
| P86 | 每条两行：LEVEL/[category]/time 一行，message 等宽字体第二行（`iOS/DiagnosticLogView.swift:55-76`） | 每条单行富文本：时钟、LEVEL、category、message（`Android/ui/DiagnosticLogScreen.kt:188-207`） | 🟡 |
| P87 | build 信息是 List 的 Section header（`iOS/DiagnosticLogView.swift:23-30`） | build 信息固定显示在列表上方（`Android/ui/DiagnosticLogScreen.kt:114-124,209-212`） | 🟡 |
| P88 | 日志入口在连接详情，以 `fullScreenCover` 呈现（`iOS/ConnectionDetailView.swift:54`） | 连接详情入口 + 全屏 Compose 页面（`Android/ui/AdaptiveRoot.kt:507-510`） | ✅ |
| P89 | 日志覆盖 open/scroll/sync/error/link 等应用事件（`iOS/AppModel.swift:394`、`iOS/DiagnosticLog.swift:35-46`） | 覆盖 link/request/enrollment/relay/discovery/conversation，但无 scroll/open 页面级记录（`Android/bridge/BridgeClient.kt:83-88`、`Android/bridge/LinkClient.kt:80-112`、`Android/bridge/Discovery.kt:66-131`） | 🟡 |

### 3.6 后台同步

| # | iOS 行为 | Android 现状 | 状态 |
| --- | --- | --- | --- |
| P90 | 开关默认 true，`@AppStorage("backgroundSync")`；开/关立即 schedule/cancel（`iOS/BackgroundSync.swift:15,20`、`iOS/ConnectionDetailView.swift:43`） | SharedPreferences 默认 true；开/关立即 schedule/cancel（`Android/CmuxViewModel.kt:255-256,313-317`） | ✅ |
| P91 | `BGAppRefreshTask`，最早 60 秒后，由 iOS 决定实际执行（`iOS/BackgroundSync.swift:14-28`、`ios/Info.plist:5-8`） | WorkManager 周期任务，最短 15 分钟，要求网络可用（`Android/background/BackgroundSyncWorker.kt:131-149`） | 🟡 |
| P92 | 进入后台时调度；后台任务醒来先重新调度下一次（`iOS/CmuxRemoteApp.swift:23,36-39`） | 只在连接成功或用户打开开关时调度；无前台/后台生命周期调度（`Android/CmuxViewModel.kt:748`、`Android/MainActivity.kt:11-38`） | 🟡 |
| P93 | 后台 pass：重拨所有 Mac → 全量 refresh → 取最近 12 条会话，读取运行中或有更新的会话正文（`iOS/AppModel.swift:374-395`） | 只读每台 Mac 的 sessions 与 feed 待处理数，不读会话正文（`Android/background/BackgroundSyncWorker.kt:89-127`） | ❌ |
| P94 | 无列表快照；首屏直接读网络或显示 loading（`iOS/SessionListView.swift:154`） | 写 `SessionSnapshotCache`（8 台、512 KiB），首帧展示会话与待处理计数（`Android/background/BackgroundSyncWorker.kt:53-87`、`Android/background/SessionSnapshotCache.kt:29-73,137-145`、`Android/CmuxViewModel.kt:827-846`） | ➕ |
| P95 | 不限制 Mac 数；最多读 12 条会话（`iOS/AppModel.swift:378-392`） | 最多 4 台 Mac，每台 20 秒、总预算 60 秒（`Android/background/BackgroundSyncWorker.kt:41,59-76,134-137`） | 🟡 |
| P96 | 某台读失败保留该 Mac 上次成功列表（`iOS/AppModel.swift:313-325`） | 读失败回退快照/上一份内存列表；全部失败且未超预算时 `Result.retry()`（`Android/CmuxViewModel.kt:957-989`、`Android/background/BackgroundSyncWorker.kt:79-86`） | 🟡 |
| P97 | 后台 pass 写一条 sync 诊断日志（读取条数/耗时）（`iOS/AppModel.swift:394`） | Worker 未写 Diagnostics 日志（`grep Diagnostics` 于 `BackgroundSyncWorker.kt` 无命中） | 🟡 |
| P98 | 说明写 “每次最多 3 个对话”，强调 iOS 决定执行时机（`iOSRes/en.lproj/Localizable.strings:317`） | 说明只说系统定期唤醒、同步运行中/有更新的对话，不写数量（`ARes/values-en/strings.xml:272`） | 🟡 |

### 3.7 安全存储

| # | iOS 行为 | Android 现状 | 状态 |
| --- | --- | --- | --- |
| P99 | 设备私钥存 Keychain `cmux-remote.identity`，`AfterFirstUnlockThisDeviceOnly`（`iOS/DeviceIdentityStore.swift:5-9`、`iOS/SecureDeviceStore.swift:24-29,45-47`） | 私钥为 32 字节 Ed25519，由 AndroidKeyStore 非导出 AES-256-GCM 密钥包裹后存 `identity/key.bin`（`Android/security/KeyVault.kt:17-34,58-93`） | 🟡 |
| P100 | Mac 授权（含私钥、grant）整体以 JSON 存 Keychain `cmux-remote.authorized`（`iOS/PairingStore.swift:5-31`、`iOS/SecureDeviceStore.swift:18-30`） | **`connections.json` 是普通应用私有 JSON，其中 `privateKey` 以 base64 明文保存**（`Android/data/ConnectionStore.kt:24-62`、`Android/protocol/ProtocolModels.kt:291-299`） | ❌ 安全 |
| P101 | 无生物识别要求，也不做用户认证解锁 | 同样无生物识别，`setUserAuthenticationRequired(false)`（`Android/security/KeyVault.kt:72`） | ✅ |
| P102 | 旧版单连接迁移为列表；无设备私钥迁移（`iOS/PairingStore.swift:13-21`） | 旧版单连接迁移为列表；另有旧明文 `identity.key` 迁移进 KeyVault（`Android/data/ConnectionStore.kt:35-38,97-104`） | 🟡 |
| P103 | 模拟器开发态用 0700 目录 + 0600 文件，不碰 Keychain（`iOS/SecureDeviceStore.swift:9-10,18-22,39-43`） | 无模拟器专用路径；统一走应用私有文件/Keystore | 🟡 |
| P104 | Keychain 写入失败抛 `keychain_failed`，并本地化提示（`iOS/SecureDeviceStore.swift:24-29`、`iOS/ErrorPresentation.swift:31`） | 解密/Keystore 失效时静默删除旧 wrapping key 并生成新身份，不向 UI 报错（`Android/security/KeyVault.kt:22-34`） | 🟡 |
| P105 | 无 “重置身份” 能力 | 有 `clearIdentity()`：删除 identity.key、Keystore 条目和连接文件（`Android/data/ConnectionStore.kt:110-115`、`Android/security/KeyVault.kt:43-48`） | ➕ |
| P106 | 中转 origin 属公开路由信息，存 UserDefaults（`iOS/PairingStore.swift:32-34`） | 同样存普通 SharedPreferences（`Android/CmuxViewModel.kt:385-390,438-447`） | ✅ |
| P107 | Keychain 条目设备专属、重启后首次解锁可用；无 iCloud 同步（`iOS/PairingStore.swift:59`、`iOS/SecureDeviceStore.swift:27`） | `allowBackup=false`，文件权限尽力设为仅 owner 可读写（`android/app/src/main/AndroidManifest.xml:19`、`Android/data/ConnectionStore.kt:57-62`、`Android/security/KeyVault.kt:95-110`） | ✅ |

### 3.8 错误呈现、稳定错误码、深链、无障碍与视觉

| # | iOS 行为 | Android 现状 | 状态 |
| --- | --- | --- | --- |
| P108 | `ErrorPresentation` 覆盖约 57 个稳定码，含网络/身份/授权/登记/输入/模型/任务/图片等（`iOS/ErrorPresentation.swift:17-68`） | `userMessage()` 只映射约 18 个码，大量码落到 Bridge 英文消息或裸码（`Android/CmuxViewModel.kt:1880-1908`） | ❌ |
| P109 | 未知码显示 `[code] + error.connection`，并写一条 `unhandled error code` 诊断（`iOS/ErrorPresentation.swift:61-67`） | 未知码优先显示服务端 sentence，否则显示裸码，无诊断记录（`Android/CmuxViewModel.kt:1905`） | 🟡 |
| P110 | `URLError` 区分超时与普通网络错误；POSIX 错误归网络错误（`iOS/ErrorPresentation.swift:18-21`） | 只特判稳定码 `timeout`；原始 `URLError`/`SSLException` 走通用 message/类名（`Android/CmuxViewModel.kt:1880-1908`） | 🟡 |
| P111 | `invalid_identity/invalid_signature/invalid_grant/host_changed` 都映射到身份错误；登记关闭/过期/找不到/已结束统一为登记错误（`iOS/ErrorPresentation.swift:27-28`） | 只映射 `host_changed`；`invalid_identity`、`invalid_grant`、`invalid_signature`、`request_not_found`、`request_finished` 未映射（`Android/CmuxViewModel.kt:1882-1904`） | ❌ |
| P112 | iOS 错误映射没有专门的 `revoked` / `invalid_certificate` 文案（`iOS/ErrorPresentation.swift:17-68`） | 有专门 `revoked` 与 `invalid_certificate` 本地化文案（`Android/CmuxViewModel.kt:1885,1888`、`ARes/values/strings.xml:51,54`） | ➕ |
| P113 | 有 `isConnectivity` 分类，把 URLError/POSIX/relay/bridge/`invalid_proof` 等视为可自动恢复（`iOS/ErrorPresentation.swift:5-16`） | 未找到等价分类函数；列表只有 “全部 Mac 都失败时一条通用错误”（`Android/CmuxViewModel.kt:995-1008`） | ❌ |
| P114 | 外层 scheme 未注册为系统深链（`ios/Info.plist` 无 `CFBundleURLTypes`） | Manifest 只有 LAUNCHER intent-filter，无 VIEW scheme（`android/app/src/main/AndroidManifest.xml:41-46`） | ✅ 双方均未实现 |
| P115 | DEBUG 下支持 `CMUX_REMOTE_TEST_ENROLLMENT_PATH`、`PAIRING_PATH`、`NEARBY_PATH`（`iOS/AppModel.swift:94-101,148-160`） | DEBUG intent extras：`force_relay`、`reset_identity`、`add_device`、`relay_origin`、`enroll_code`、`enroll_file`（`Android/MainActivity.kt:16-31`） | 🟡 |
| P116 | 配对页有 `pair.relay.refresh`、`pair.relay.origin`、移除按钮 label；页面框架有 `page.back`/`page.close`（`iOS/PairingView.swift:139,154,159`、`iOS/WhitePage.swift:24,31`） | 本域四个页面没有 `testTag`；仅有返回/补光 `contentDescription`（`Android/ui/PairingScreen.kt:107`、`Android/ui/QrScannerScreen.kt:289-291`） | ❌ |
| P117 | 大量语义化 label：刷新、移除中转、返回、关闭；combine/contain 状态条（`iOS/PairingView.swift:139,154`、`iOS/ConnectionStatusBar.swift:21,32`） | 返回/补光有 label，大多数图标 `contentDescription = null`，无 combine/selected 语义（`Android/ui/ConnectionDetailScreen.kt:191,287,314,371`） | 🟡 |
| P118 | 页面统一 `WhitePage`：safe-area 顶部栏、居中标题、左返回/右关闭、白底（`iOS/WhitePage.swift:13-38`） | 每个页面自绘 36dp 返回行，标题左对齐；配对页再单独画 Laptop 图标标题（`Android/ui/ConnectionDetailScreen.kt:126-148`、`Android/ui/DiagnosticLogScreen.kt:95-113`、`Android/ui/PairingScreen.kt:100-121`） | 🟡 |
| P119 | 卡片：白底、22pt 圆角、0.5 描边、shadow radius 14 / y 4、内边距 16（`iOS/FloatingSurface.swift:4-11`、`iOS/MobileDesign.swift:8-13`） | 卡片：白底、22dp 圆角、0.5dp 边框、shadow 6dp、内边距 16（`Android/ui/components/FloatingSurface.kt:17-35`、`Android/ui/theme/MobileDesign.kt:20`） | 🟡 |
| P120 | 按钮统一胶囊白底 + 0.5 描边 + shadow；prominent 用 accent 底白字；按下 0.65 透明度（`iOS/FloatingButtonStyle.swift:5-18`） | 配对页主按钮用 CircleShape accent/Ink；连接页 ActionButton 胶囊白底 + 0.5 边框 + 3dp elevation；无统一按钮样式（`Android/ui/PairingScreen.kt:136-146,240-248,283-295`、`Android/ui/ConnectionDetailScreen.kt:392-419`） | 🟡 |
| P121 | 字体使用系统语义：headline/title3/subheadline/footnote/caption；ID、证书、日志等宽（`iOS/ConnectionDetailView.swift:22,56-61`、`iOS/DiagnosticLogView.swift:69-71`） | Material3 titleLarge/titleMedium/bodyMedium/labelMedium；证书/identity/日志等宽，但附近发现 host id 用大写非等宽（`Android/ui/ConnectionDetailScreen.kt:291-296,337-353`、`Android/ui/PairingScreen.kt:396-399`） | 🟡 |
| P122 | Accent 为 RGB(0.20,0.36,0.96)=#335CF5；白底、浅色强制；绿色使用系统 green（`iOS/MobileDesign.swift:11-13`、`iOS/CmuxRemoteApp.swift:20`） | Accent #335CF5、Good #2F9E6B、Canvas 白，仅提供 light scheme（`Android/ui/theme/MobileDesign.kt:7-15`、`Android/ui/theme/CmuxTheme.kt:13-23`） | ✅ |
| P123 | 间距：页边 20 / 段间距 24 / 行距 12 / 控件高 44（`iOS/MobileDesign.swift:5-10`） | 相同（`Android/ui/theme/MobileDesign.kt:17-21`） | ✅ |
| P124 | 有明确动画：连接条 0.2s easeInOut、按钮按下透明度、sheet/fullScreenCover 过渡（`iOS/ConnectionStatusBar.swift:38`、`iOS/FloatingButtonStyle.swift:18`） | 本域无显式页面/状态过渡动画，只依赖 Material ripple（`Android/ui/ConversationScreen.kt:139-163`、`Android/ui/ConnectionDetailScreen.kt:120-255`） | 🟡 |
| P125 | 配对状态行：wifi/cloud 图标、ID 前 16 位等宽、右侧 chevron 或 approved seal（`iOS/PairingView.swift:164-174`） | 状态行：Laptop/Cloud 或 CheckCircle、ID 前 16 位大写非等宽、无 chevron（`Android/ui/PairingScreen.kt:375-403`） | 🟡 |

### 3.9 本域 Android 独有

- 独立 `Restoring` 启动态与居中转圈（`Android/CmuxViewModel.kt:41-43`、`Android/ui/AdaptiveRoot.kt:240`）。
- “已经配过对？重试已保存的连接”（`Android/ui/PairingScreen.kt:317-319`、`Android/ui/AdaptiveRoot.kt:247,569`）。
- “重置本机身份” 完整流程与确认弹窗（`Android/CmuxViewModel.kt:478-509`、`Android/ui/PairingScreen.kt:296-307,322-338`）。
- 连接详情 “传输” 卡片（局域网直连 / 通过中转）（`Android/ui/ConnectionDetailScreen.kt:171-184`、`Android/ui/AdaptiveRoot.kt:488`）。
- 连接详情 “密钥” 卡片（Keystore / 应用私有文件）（`Android/ui/ConnectionDetailScreen.kt:186-209`、`Android/security/KeyVault.kt:51-56`）。
- 移除 Mac 前的确认弹窗（`Android/ui/ConnectionDetailScreen.kt:257-278`）。
- 扫码页取景框、点按对焦、数码变焦、补光、顶部白色胶囊标题栏、前置/后置摄像头回退（`Android/ui/QrScannerScreen.kt:186-303,369-407,475-513,327-334`）。
- 诊断日志脱敏（32+ 字符密钥样式）与单条 512 字符截断（`Android/data/Diagnostics.kt:17-21,28-38,63`）。
- 诊断日志额外 “刷新” 按钮（`Android/ui/DiagnosticLogScreen.kt:170-182`）。
- `SessionSnapshotCache` 首帧会话列表与待处理计数（8 台 / 512 KiB）（`Android/background/SessionSnapshotCache.kt:29-73,137-145`、`Android/CmuxViewModel.kt:827-846`）。
- WorkManager 网络约束、4 台 Mac 上限、20s/台、60s 总预算、失败 `Result.retry()`（`Android/background/BackgroundSyncWorker.kt:38-87,131-149`）。
- DEBUG 启动参数 `force_relay` / `reset_identity` / `add_device` / `relay_origin` / `enroll_code` / `enroll_file`（`Android/MainActivity.kt:16-31`）。
- `revoked` 与 `invalid_certificate` 的专门本地化文案（`Android/CmuxViewModel.kt:1885,1888`、`ARes/values/strings.xml:51,54`）。
- 中转 origin 数量不设上限（`Android/CmuxViewModel.kt:386-390,416-447`）。
- 配对设备默认标识 `cmux Android` / `android`，并保留旧 Bridge 的 `iphone` 回退（`Android/bridge/Enrollment.kt:267-268`、`Android/CmuxViewModel.kt:593-597`）。
- 登记先直连 HTTPS、失败后才上中转 link 的传输路径（`Android/bridge/Enrollment.kt:165-239`）。
- 独立 Failed 页面显示稳定错误码 + 消息（`Android/ui/PairingScreen.kt:446-464`）。
- 旧明文身份 `identity.key` 自动迁移进 Keystore 包裹存储（`Android/data/ConnectionStore.kt:97-104`、`Android/security/KeyVault.kt:36-41`）。

## 4. 新建会话、项目、Feed 与问题回答

> 编号前缀 **F**。路径别名同第 2、3 节。

### 4.1 新建会话页

| # | iOS 行为 | Android 现状 | 状态 |
| --- | --- | --- | --- |
| F1 | 入口在列表标题菜单的 “New Conversation”，仅 `canStart` 时出现，另有工作区分组行内 `+`（`iOS/SessionTitleMenu.swift:28-30`、`iOS/SessionListView.swift:104-110`） | 标题菜单同名入口，另有表头独立 `+` 按钮和工作区分组 `+`（`Android/ui/SessionListChrome.kt:139-141`、`Android/ui/SessionListScreen.kt:255-259,307-315`） | 🟡 |
| F2 | 以 sheet 呈现，`AppNavigationStack` 内先选工作区再 push 目录页，关闭用右上角 X（`iOS/SessionListView.swift:178-182`、`iOS/StartSessionSheet.swift:20-24`） | 全屏条件页替换整个 shell，进入即加载工作区，返回用左上角 chevron（`Android/ui/AdaptiveRoot.kt:213-237`、`Android/ui/StartSessionScreen.kt:84-108`） | 🟡 |
| F3 | 目标 Mac 来自所有 `conversationStart` 授权 Mac，按 host+workspace 生成 `StartTarget`（`iOS/AppModel.swift:424-426`、`iOS/StartTarget.swift:6-11`） | 只从当前 `repository`（主 Mac 或最后打开的 Mac）读取工作区，无 “目标 Mac” 选择（`Android/CmuxViewModel.kt:1440-1448`） | ❌ |
| F4 | 多 Mac 时工作区行显示所属 Mac 名（`iOS/StartSessionSheet.swift:31`、`iOS/SessionListView.swift:179`） | 工作区 chips 仅标题，无 Mac 标识；聚合 map 还会丢失同 ID 工作区的 host 归属（`Android/ui/StartSessionScreen.kt:124-135`、`Android/CmuxViewModel.kt:1445`） | ❌ |
| F5 | 工作区为带 `macwindow` 图标和 chevron 的整行，必须显式点选（`iOS/StartSessionSheet.swift:29-33`、`iOS/StartRow.swift:9-16`） | 工作区为 `FlowRow` chips，打开页面后自动选择第一个工作区（`Android/ui/StartSessionScreen.kt:124-135`、`Android/CmuxViewModel.kt:1447-1448`） | 🟡 |
| F6 | 无工作区显示专用说明（`iOS/StartSessionSheet.swift:28`） | 显示 “No workspaces available.”（`Android/ui/StartSessionScreen.kt:121-123`） | ✅ |
| F7 | 进入后单独一页加载项目根目录，`.task` 首次读取并支持下拉刷新（`iOS/StartRootsView.swift:29-31`） | 选工作区后自动读取根目录并自动选中第一个根目录（`Android/CmuxViewModel.kt:1459-1465`） | 🟡 |
| F8 | 根目录行显示 basename + 完整路径，带 folder 图标和 chevron（`iOS/StartRootsView.swift:19-25`、`iOS/StartRow.swift:11-15`） | 根目录卡片显示完整路径（等宽字体），带 folder 图标和选中勾（`Android/ui/StartSessionScreen.kt:251-285`） | 🟡 |
| F9 | 无根目录显示 “工作区还没有项目文件夹” 的说明（`iOS/StartRootsView.swift:16-18`） | 显示 “No directories available.”；失败时还写死中文提示 “这个工作区没有可以新建会话的目录。”（`Android/ui/StartSessionScreen.kt:142-144`、`Android/CmuxViewModel.kt:1467`） | 🟡 |
| F10 | 根目录列表可下拉刷新（`iOS/StartRootsView.swift:29`） | 页面无刷新入口，只能重选工作区触发重读（`Android/ui/StartSessionScreen.kt:145-154`、`Android/CmuxViewModel.kt:1459-1470`） | ❌ |
| F11 | 可逐级进入子目录并选择任意相对路径启动（`iOS/StartFolderView.swift:41-52,59-61`） | 无子目录浏览；只调用 `/v2/workspaces/{id}/directories` 取根目录（`Android/data/BridgeRepository.kt:427-436`） | ❌ |
| F12 | 面包屑为导航标题 basename + `root.path + "/" + path` 等宽文字，最多 3 行中间截断（`iOS/StartFolderView.swift:14-19`） | 无路径输入框、无面包屑；启动时固定发 `path=""`（`Android/ui/StartSessionScreen.kt:118-155`、`Android/CmuxViewModel.kt:1488`） | ❌ |
| F13 | 子目录为空、超过 500 条截断、读取错误均有独立提示（`iOS/StartFolderView.swift:44,50-51`） | 无子目录列表，故无对应状态（`Android/ui/StartSessionScreen.kt:139-155`） | ❌ |
| F14 | 新建页没有搜索、最近、收藏入口（`grep recent/favorite/search` 于 `Start*.swift` 未找到） | 同样没有搜索、最近、收藏入口（`Android/ui/StartSessionScreen.kt:118-225`） | ✅ |
| F15 | Agent 用分段 Picker，枚举 `LaunchAgent.allCases`（claude/codex）（`iOS/StartFolderView.swift:20-22`、`Core/LaunchAgent.swift:4-5`） | Agent 用 chips，来自 `StartUi.agents = ["claude","codex"]`（`Android/ui/StartSessionScreen.kt:157-171`、`Android/CmuxViewModel.kt:122`） | 🟡 |
| F16 | 新建页不提供模型选择，只能选 Agent；模型切换在会话内（`iOS/StartSessionModel.swift:17-20`、`iOS/ConversationView.swift:575`） | 新建页同样不提供模型选择；模型切换在会话内（`Android/CmuxViewModel.kt:122-124`、`Android/ui/SessionActions.kt:42-90`） | ✅ |
| F17 | 首条消息为 2–6 行垂直输入框，按 Agent 显示 optional/required 占位和 Codex 提示（`iOS/StartFolderView.swift:23-29`） | 首条消息为 3–6 行 `OutlinedTextField`，固定占位、Codex 提示（`Android/ui/StartSessionScreen.kt:184-203`） | 🟡 |
| F18 | 首条消息无长度上限（`iOS/StartSessionModel.swift:19`） | 硬限制 4096 UTF-8 字节并显示实时字节数，超限直接拒绝输入（`Android/ui/StartSessionScreen.kt:51,178-189`） | ➕ |
| F19 | 主按钮 “Start here”；`outcome_unknown` 后变 “Check again”，并额外出现 “Open another terminal anyway”（`iOS/StartFolderView.swift:30-37`） | 只有 “Start”/“Starting…” 一个按钮，无 “检查结果/另开终端” 分支（`Android/ui/StartSessionScreen.kt:213-224`） | ❌ |
| F20 | 启动中显示带 “Opening a terminal…” 的 `ProgressView`（`iOS/StartFolderView.swift:38`） | 无 spinner，仅按钮文字变成 “Starting…”（`Android/ui/StartSessionScreen.kt:220-223`） | 🟡 |
| F21 | 可启动条件：非 starting，且 Codex 必须非空 prompt（`iOS/StartSessionModel.swift:20`） | 可启动条件：已选工作区/根目录、非 busy、Codex prompt 非空（`Android/ui/StartSessionScreen.kt:78-81`） | ✅ |
| F22 | 同参数重试复用 `pendingRequest` 的 operation 身份，`fresh=true` 才新开终端（`iOS/StartSessionModel.swift:41-51`） | 每次点击都生成新的 `operation_id`，无幂等复用（`Android/data/BridgeRepository.kt:439-447`） | ❌ |
| F23 | 校验回执 `accepted` 和 `surfaceID`，未接受则不宣称成功（`iOS/StartSessionModel.swift:49-51`） | 忽略 `accepted`，只解析 `surface_id`（`Android/CmuxViewModel.kt:1488-1489`） | ❌ |
| F24 | 特殊错误映射：`outcome_unknown` → 检查提示，`stale_binding` → 文件夹已失效提示，其他走通用错误（`iOS/StartSessionModel.swift:52-60`） | 统一走 `userMessage()`；根目录失败还会误报 “没有目录”（`Android/CmuxViewModel.kt:1509-1510,1466-1468`） | ❌ |
| F25 | 启动接受后列表显示 “Starting the agent…”；20 次×1.5s 刷新按 `surfaceID` 找会话并打开；`surfaceID` 为空则立即停止并显示 “终端已打开”（`iOS/SessionListView.swift:179-198`） | 启动页显示 “终端已经打开，正在等待会话出现…”；20 次×1.5s 刷新按 “新 id + workspace + surface” 找会话并自动打开；`surface` 为空时匹配该工作区任意新会话（`Android/CmuxViewModel.kt:1490-1508`） | 🟡 |
| F26 | 启动成功后立即 dismiss sheet，等待过程在列表上进行（`iOS/StartSessionSheet.swift:44`、`iOS/SessionListView.swift:179-181`） | 启动页一直停留到会话出现，找到后才关闭并进入会话；30 秒未出现则留在启动页提示（`Android/CmuxViewModel.kt:1490-1508`） | 🟡 |
| F27 | 成功后清空 prompt；失败保留 prompt（`iOS/StartSessionModel.swift:50,55`） | 成功后页面关闭故不关心；失败保留 prompt（`Android/CmuxViewModel.kt:1509-1510`） | 🟡 |
| F28 | 权限按 Mac：只有 `conversationStart` 的 Mac 才出现在 `startTargets`（`iOS/AppModel.swift:424-426`） | 只有全局 `_canStart`（连接主 Mac 的 scope）；旧 Bridge 回退还会主动去掉 `conversationStart`（`Android/CmuxViewModel.kt:747,584-599`） | ❌ |
| F29 | 启动目标和 `RemoteClient` 绑定，可在多 Mac 间选择（`iOS/StartTarget.swift:6-11`、`iOS/StartSessionSheet.swift:41-42`） | 启动总是走当前 `repository`（被最后打开的会话改写），没有 workspace→host 绑定（`Android/CmuxViewModel.kt:1023-1030,1441,1488`） | ❌ |
| F30 | 启动命令由客户端固定映射到 Agent；手机不提交任意命令行（`Core/LaunchAgent.swift:9-15`） | 手机同样只提交 agent/prompt，命令由 Mac 侧固定（`Android/data/BridgeRepository.kt:439-448`） | ✅ |

### 4.2 项目页

| # | iOS 行为 | Android 现状 | 状态 |
| --- | --- | --- | --- |
| F31 | 入口：会话工具栏菜单 “Files and changes”；工具引用文件可直接带路径进入（`iOS/ConversationView.swift:585,295-301,163`） | 入口：作曲家菜单 “Project changes”；工具引用通过 `onOpenReference` 带路径进入（`Android/ui/ConversationScreen.kt:367-368,970-979`、`Android/ui/AdaptiveRoot.kt:176`） | ✅ |
| F32 | 入口受 `projectRead` 能力控制；引用按钮也受控（`iOS/ConversationView.swift:585,295`） | 无 `ProjectRead` 能力检查，入口始终显示（`Android/ui/AdaptiveRoot.kt:167,196`） | ❌ |
| F33 | 初始无路径时显示改动列表；带初始路径时直接以 file 资源打开（`iOS/ProjectModel.swift:21`） | 打开时先列 changes，再自动选中第一条 change 并加载 diff（`Android/CmuxViewModel.kt:1200-1209`） | 🟡 |
| F34 | 有相对路径输入框，回车或 “Read file” 可读任意相对文件（`iOS/ProjectView.swift:20-24`） | 无路径输入框，只能读改动列表中的文件（`Android/ui/ProjectScreen.kt:61-72,188-235`） | ❌ |
| F35 | 三个资源按钮：Read file / Diff / Changed files，并可高亮当前资源（`iOS/ProjectView.swift:24-27`） | 无资源切换按钮，固定先 changes 后单文件 diff（`Android/ui/ProjectScreen.kt:188-290`） | ❌ |
| F36 | 路径为空时点 Diff 可看整仓工作区 diff（空 path 不传 query）（`iOS/ProjectModel.swift:47`） | 无整仓 diff，只能对单个 change 调 diff/file（`Android/ui/ProjectScreen.kt:68-69`、`Android/CmuxViewModel.kt:1220-1236`） | ❌ |
| F37 | 加载中显示顶部 `ProgressView`，加载开始时清空旧内容（`iOS/ProjectView.swift:28`、`iOS/ProjectModel.swift:39`） | 加载中显示居中 `WorkingIndicator`；刷新时保留旧文本直到新结果覆盖（`Android/ui/ProjectScreen.kt:116-119,226-228`、`Android/CmuxViewModel.kt:1223-1231`） | 🟡 |
| F38 | 错误以红色文本显示（`iOS/ProjectView.swift:29`） | 错误以 `MaterialTheme.colorScheme.error` 文本显示（`Android/ui/ProjectScreen.kt:105-112`） | ✅ |
| F39 | 改动为空显示 “No changed files.”（`iOS/ProjectView.swift:31`） | 显示 “This conversation has no uncommitted changes.”（`Android/ui/ProjectScreen.kt:198-206,252-262`） | ✅ |
| F40 | 改动行：状态等宽 caption、路径、重命名 `old → new`、右侧 chevron、最小 44 高（`iOS/ProjectView.swift:36-43`） | 改动行：状态徽标 + 路径，选中时背景高亮；无 `old → new`、无 chevron、无 44 最小高度（`Android/ui/ProjectScreen.kt:293-325`） | 🟡 |
| F41 | 解析并显示重命名源路径（`iOS/ProjectView.swift:40`、`Core/ProjectChange.swift:18-20`） | 解析时直接丢弃重命名源路径，模型中的 `added/removed` 也永远为 null（`Android/data/ProjectReader.kt:56-59,66`） | ❌ |
| F42 | 点击改动：删除态 `D` 看 diff，其余看 file（`iOS/ProjectView.swift:34`） | 点击改动：总是先 diff，失败再 file（`Android/CmuxViewModel.kt:1227-1230`） | 🟡 |
| F43 | 文件/diff 正文为等宽 footnote、可选中、自动换行（`iOS/ProjectView.swift:49`） | 正文为等宽 12sp、`SelectionContainer`、横向滚动且不换行（`Android/ui/ProjectScreen.kt:328-347`） | 🟡 |
| F44 | 内容为空显示 “No content to show.”（`iOS/ProjectView.swift:48`） | 无空内容提示，直接显示空白代码块（`Android/ui/ProjectScreen.kt:225-233,279-287`） | ❌ |
| F45 | 截断显示 “Content is truncated”（`iOS/ProjectView.swift:47`） | 显示 “Truncated”（`Android/ui/ProjectScreen.kt:349-356`） | ✅ |
| F46 | 复制/分享在正文下方 `ActionRow`，仅在内容非空时出现，带图标（`iOS/ProjectView.swift:50-55`） | 复制/分享在页头，以纯文字动作出现，只要 `text != null` 就显示（`Android/ui/ProjectScreen.kt:83-104,169-171`） | 🟡 |
| F47 | 无手动刷新按钮；前台恢复时自动 `reload()` 当前资源并保留路径（`iOS/ProjectView.swift:61-64`、`iOS/ProjectModel.swift:33`） | 页头有 Refresh，但调用 `openProject()` 会重新列 changes 并跳回第一条，丢失当前选中（`Android/ui/ProjectScreen.kt:171`、`Android/ui/AdaptiveRoot.kt:358`、`Android/CmuxViewModel.kt:1197-1214`） | 🟡 |
| F48 | 页面消失或进入后台时挂起读取，清掉 busy（`iOS/ProjectView.swift:59-63`、`iOS/ProjectModel.swift:31`） | 无读取挂起；离开页面后请求仍可完成（`Android/CmuxViewModel.kt:1200-1236`） | ❌ |
| F49 | 只有改动列表，无文件树（`grep tree/file tree/browser` 无命中） | 同样只有改动列表，无文件树（`Android/ui/ProjectScreen.kt:188-290`） | ✅ |
| F50 | 单列布局，改动列表与正文上下排列（`iOS/ProjectView.swift:18-19`） | 手机单列；折叠屏/平板为 240dp 改动列表 + 正文双栏（`Android/ui/ProjectScreen.kt:113-136,238-290`） | ➕ |
| F51 | 页标题固定 “Files and changes”（`iOS/ProjectView.swift:17`） | 页标题使用会话标题（`Android/ui/AdaptiveRoot.kt:349`） | 🟡 |
| F52 | 返回为浮动圆形 chevron，支持边缘返回手势（`iOS/WhitePage.swift:20-24,36`） | 页头 36dp 圆形 chevron；紧凑布局有 `BackHandler`，双栏布局无 `BackHandler`（`Android/ui/ProjectScreen.kt:155-160`、`Android/ui/AdaptiveRoot.kt:347,397-410`） | 🟡 |
| F53 | 只读展示，不提供编辑（`iOS/ProjectView.swift:49-55`） | 只读展示，不提供编辑（`Android/ui/ProjectScreen.kt:328-358`） | ✅ |
| F54 | 无项目页缓存（`iOS/ProjectModel.swift:11-15`） | 无项目页缓存（`Android/CmuxViewModel.kt:68-74`） | ✅ |

### 4.3 Feed / 待处理

| # | iOS 行为 | Android 现状 | 状态 |
| --- | --- | --- | --- |
| F55 | Feed 按单个 Mac 的 `RemoteClient` 打开；列表页每个 host 一个 Feed 入口（`iOS/SessionListView.swift:157`、`iOS/SessionTitleMenu.swift:20-26`） | 一个聚合 Feed 展示所有 Mac 的 feed，不标 host；会话内 Feed 也展示全量聚合（`Android/CmuxViewModel.kt:993-1004`、`Android/ui/AdaptiveRoot.kt:377`） | ❌ |
| F56 | 回答通过该 host 的 client 发往 `/v1/feed/{id}/reply`（`iOS/FeedModel.swift:22-26`、`iOS/FeedView.swift:48-50`） | 回答使用当前 `repository`，不追踪 item 来自哪个 Mac；多 Mac 下可能答到错误 Mac（`Android/CmuxViewModel.kt:1824-1830`） | ❌ |
| F57 | Feed 入口和回答受 `feedRead` / `canReplyFeed` 控制（`iOS/ConversationView.swift:586`、`iOS/FeedView.swift:48-50`） | 无 `feedRead`/`feedReply` 的 UI 门控，始终可打开和提交（`Android/ui/AdaptiveRoot.kt:377`、`Android/ui/FeedScreen.kt:45-52`） | ❌ |
| F58 | 待处理/全部事件用两个胶囊按钮，当前项为 prominent 且带 selected 无障碍特征（`iOS/FeedView.swift:18-21`） | 用一个胶囊按钮在 “Pending only” / “All events” 之间切换（`Android/ui/FeedScreen.kt:68-76`） | 🟡 |
| F59 | 空状态固定 “No pending decisions.”，历史模式也相同（`iOS/FeedView.swift:22-23`） | 空状态区分 “Nothing needs your answer right now.” / “No events yet.”（`Android/ui/FeedScreen.kt:78-85`） | 🟡 |
| F60 | 首次加载为空时显示 `ProgressView`（`iOS/FeedView.swift:22`） | 无加载指示；FeedScreen 无 loading 参数（`Android/ui/FeedScreen.kt:45-52`） | ❌ |
| F61 | 支持下拉刷新；前台期间订阅 `/v1/feed` 变化自动刷新（`iOS/FeedView.swift:61,64-67`） | FeedScreen 本身无下拉刷新；依赖 shell 的 live/30 秒轮询刷新（`Android/ui/FeedScreen.kt:86-122`、`Android/CmuxViewModel.kt:931-946`） | 🟡 |
| F62 | 分页未找到（`grep page/cursor/loadMore` 于 Feed 无命中） | 分页未找到（`Android/ui/FeedScreen.kt` 无命中） | ✅ |
| F63 | 读取错误和写入错误合并显示在卡片下方红字（`iOS/FeedModel.swift:13-15`、`iOS/FeedView.swift:59`） | FeedScreen 无 error 参数；提交失败写入 `_conversation.error`，Feed 页不可见；读取失败被 `runCatching` 静默成空列表（`Android/ui/FeedScreen.kt:45-52`、`Android/CmuxViewModel.kt:1832-1834,962-964`） | ❌ |
| F64 | 标题优先 `title` → `tool_name` → “Agent event”（`iOS/FeedView.swift:27`） | 标题优先 `title` → `tool_name` → 类型默认文案（`Android/ui/FeedScreen.kt:108,114,131`） | ✅ |
| F65 | 显示 `question_prompt` 原话（`iOS/FeedView.swift:29`） | `FeedItem` 不解析 `question_prompt`（`Android/data/BridgeRepository.kt:119-136,303-332`） | ❌ |
| F66 | plan 用 Markdown 渲染（`iOS/FeedView.swift:28`） | 待处理 exitPlan 的 plan 用纯 Text 显示；历史 RecordCard 才用 MarkdownText（`Android/ui/FeedForms.kt:328-339`、`Android/ui/FeedScreen.kt:139-142`） | 🟡 |
| F67 | `body` 以 callout 显示且可选中（`iOS/FeedView.swift:31`） | `body` 以 muted 文本显示（`Android/ui/FeedScreen.kt:135-137`） | 🟡 |
| F68 | `tool_input` 以等宽 caption 显示且可选中（`iOS/FeedView.swift:32`） | 仅在 permission 卡内以等宽 code 块显示 `toolInput`；RecordCard 不显示（`Android/ui/FeedForms.kt:204-215`、`Android/ui/FeedScreen.kt:128-166`） | 🟡 |
| F69 | `text`/`reason` 用 Markdown 渲染（`iOS/FeedView.swift:33`） | 不解析 `text`/`reason`（`Android/data/BridgeRepository.kt:119-136`） | ❌ |
| F70 | 工具结果：失败显示 “Tool failed” 红标，正文等宽可选中；`tool_result_truncated`/`tool_input_truncated`/`plan_truncated` 显示截断提示（`iOS/FeedView.swift:34-38`） | 工具结果仅按错误色显示文本；无 failed 标签、无截断字段（`Android/ui/FeedScreen.kt:143-150`） | 🟡 |
| F71 | `todos` 逐条显示完成/未完成圆圈（`iOS/FeedView.swift:40-44`） | 不解析并显示 todos（`Android/data/BridgeRepository.kt:119-136`） | ❌ |
| F72 | `decision.feedback` 独立显示（`iOS/FeedView.swift:39`） | 历史 RecordCard 显示 feedback（`Android/ui/FeedScreen.kt:162-164`） | ✅ |
| F73 | 非 pending 显示状态文案，并按本地化模式标题显示 decision mode（`iOS/FeedView.swift:52-54`、`iOS/FeedDecisionMode+Presentation.swift:4-30`） | 状态本地化，但 decision mode 直接拼接原始值（如 `bypassPermissions`）（`Android/ui/FeedScreen.kt:151-161`） | 🟡 |
| F74 | 非 pending 的 selections 逐行显示（`iOS/FeedView.swift:55`） | 历史 RecordCard 逐行显示 selections（`Android/ui/FeedScreen.kt:165`） | ✅ |
| F75 | 只有 `status == "pending"` 才显示问题/权限/计划控件；历史只做记录（`iOS/FeedView.swift:45-56`） | 按 `kind` 分发而不检查 status；历史中的 question/permission/exitPlan 仍显示可提交控件（`Android/ui/FeedScreen.kt:91-120`） | ❌ |
| F76 | 待处理未知 kind 显示 “This event has no supported reply action.”（`iOS/FeedView.swift:51`） | 未知 kind 落到 RecordCard，显示状态但无 “不可回答” 说明（`Android/ui/FeedScreen.kt:119,128-166`） | 🟡 |
| F77 | 权限决定主操作按策略取 `once` 或 `manual`，支持 deny（`iOS/FeedDecisionControls.swift:17-22`） | 固定 “Allow once” + “Deny”（`Android/ui/FeedForms.kt:221-242`） | 🟡 |
| F78 | 宽松模式用 Menu 展示，并在 Alert 中先解释效果再确认（`iOS/FeedDecisionControls.swift:23-36`） | 固定 “always/all/bypass” 下拉，带确认 Alert 和解释（`Android/ui/FeedForms.kt:244-311,503-519`） | 🟡 |
| F79 | 依据 `available_modes`、`source`、`tool_input_capabilities` 过滤不可交付模式（`Core/FeedDecisionPolicy.swift:6-33`） | 不读取 `available_modes/source/tool_input_capabilities`，固定展示三种宽松模式（`Android/ui/FeedForms.kt:503`、`Android/data/BridgeRepository.kt:303-332`） | ❌ |
| F80 | exitPlan 模式由策略决定，主操作为 `manual`，其余进 “More decisions”（`iOS/FeedDecisionControls.swift:17-29`、`Core/FeedDecisionPolicy.swift:9-10`） | exitPlan 固定展示 Execute plan / Auto accept / Continue after edits / Deep plan / Deny，全部直接提交且无策略过滤（`Android/ui/FeedForms.kt:353-405`） | ❌ |
| F81 | exitPlan 可填写可选 feedback（`iOS/FeedDecisionControls.swift:13-15`） | 计划卡可填写可选 feedback（`Android/ui/FeedForms.kt:341-351`） | ✅ |
| F82 | 多问题表单逐题渲染 header、prompt、选项说明、自定义输入（`iOS/FeedQuestionView.swift:25-56`） | 多问题表单逐题渲染 prompt、label、description、自定义输入；但 header 不解析（`Android/ui/FeedForms.kt:105-155`、`Android/data/BridgeRepository.kt:321-330`） | 🟡 |
| F83 | 选项 identity 独立于 label，保留 `id`、`label`、`description`（`Core/FeedQuestionOption.swift:9-12`） | 只保留 label，`id`/`description` 全部丢失（`Android/data/BridgeRepository.kt:326-327`、`Android/ui/FeedScreen.kt:97`） | ❌ |
| F84 | 单选/多选用自定义圆圈/勾；选项行最小 44 高（`iOS/FeedQuestionView.swift:30-45`） | 单选 `RadioButton`、多选 `Checkbox`，行高 `MobileDesign.Control`（`Android/ui/FeedForms.kt:424-471`） | 🟡 |
| F85 | 尊重 `allow_custom == false`，隐藏自定义回答输入（`iOS/FeedQuestionView.swift:49-55`） | 不读取 `allow_custom`；FeedScreen 固定 `allowCustom = true`（`Android/ui/FeedScreen.kt:99`、`Android/ui/FeedForms.kt:476-487`） | ❌ |
| F86 | 尊重 `allow_skip`，有可跳过题才显示 “Skip questions”（`iOS/FeedQuestionView.swift:63-66`） | 不读取 `allow_skip`；硬编码 `allowSkip = !multiSelect`，跳过按钮文案为单数 “Skip question”（`Android/ui/FeedScreen.kt:100`、`Android/ui/FeedForms.kt:175-184`） | ❌ |
| F87 | 必答判断：仅当所有问题都 `allow_skip == false` 时才要求每题都有答案（`iOS/FeedQuestionView.swift:20-22`） | 必答判断：任意一题 `allowSkip == false` 就要求该题有答案（`Android/ui/FeedForms.kt:94-97`） | 🟡 |
| F88 | 无可选项且全部为空时允许提交空答案数组（`iOS/FeedQuestionView.swift:61`） | `answersNothing` 在 “答案为空且存在选项” 时禁用提交（`Android/ui/FeedForms.kt:98-99,163-165`） | 🟡 |
| F89 | 提交中/无回答权限时禁用所有控件（`iOS/FeedView.swift:48-50`、`iOS/FeedQuestionView.swift:43`） | `FeedScreen.busy` 默认 false，两个调用点都没传；ViewModel 也无 in-flight 防重，可重复提交（`Android/ui/FeedScreen.kt:51-52`、`Android/ui/AdaptiveRoot.kt:376-381,426-432`） | ❌ |
| F90 | 历史中的问题只显示答案文本，不重新渲染表单（`iOS/FeedView.swift:52-55`） | 历史中的 question 用只读表单回显选项和 “Unanswered”（`Android/ui/FeedForms.kt:107-121`） | ➕ |
| F91 | 问题为空时仍渲染提交区；`questions.isEmpty` 时空表单行为由提交条件处理（`iOS/FeedQuestionView.swift:58-69`） | 问题为空显示 “No questions to answer.” 且不给提交（`Android/ui/FeedForms.kt:102-103`） | 🟡 |
| F92 | 卡片 identity 用 `item:`/`request:`/`event:` 稳定键（`Core/FeedEntry.swift:4-12`） | `LazyColumn` 用 `requestID` 作 key；多 Mac 聚合时相同 request id 可能重复并触发 key 冲突（`Android/ui/FeedScreen.kt:91`、`Android/CmuxViewModel.kt:993`） | ❌ |
| F93 | 待处理计数只统计 `status == "pending"`，按 host 聚合；标题取第一个有待办的 host 的首条（`Core/PendingFeed.swift:13-22`） | 待处理计数为所有 host pending 的简单数量；缓存数用 `max(pending.size, cachedPending)`（`Android/CmuxViewModel.kt:993-994`、`Android/ui/SessionListScreen.kt:242,268`） | 🟡 |
| F94 | 提醒条：铃铛图标、总数、“N waiting for you”、首条标题、chevron，隐藏于 0（`iOS/PendingReminder.swift:10-28`） | 提醒卡：数字圆圈、“%d pending”、首条标题、chevron；dense 模式隐藏标题（`Android/ui/SessionListScreen.kt:368-390`） | 🟡 |
| F95 | 多 Mac 时可展开 Menu 按 host 计数选择；单 Mac 直接打开（`iOS/PendingReminder.swift:11-16`） | 无按 host 展开菜单，点击直接进入聚合 Feed（`Android/ui/SessionListScreen.kt:268-277`） | ❌ |
| F96 | 提醒按当前 host 筛选后的 `shownLinks` 计算，并仅算 `feedRead` 的 Mac（`iOS/SessionListView.swift:56,230-232`） | 提醒不随 Mac tab 过滤，直接使用聚合 pending（`Android/ui/AdaptiveRoot.kt:288`、`Android/ui/SessionListScreen.kt:268`） | ❌ |
| F97 | 无持久化待处理计数缓存；靠 live feed 变化更新 `pending[hostID]`（`iOS/AppModel.swift:344-358,396-400`） | 用 `SessionSnapshotCache` 持久化每 host 的 pendingCount，启动时先展示缓存（`Android/background/SessionSnapshotCache.kt:30-36,70-78`、`Android/CmuxViewModel.kt:986-1002`） | ➕ |
| F98 | 标题菜单的 pending 入口按 host 细分（`iOS/SessionTitleMenu.swift:20-26`） | 标题菜单只有一个聚合 pending 计数入口（`Android/ui/SessionListChrome.kt:129-137`） | 🟡 |
| F99 | Feed 无事件类型筛选器，只有 pending/history（`iOS/FeedView.swift:18-21`） | 同样无事件类型筛选器，只有 pending/history 开关（`Android/ui/FeedScreen.kt:68-76`） | ✅ |

### 4.4 会话内问题回答

| # | iOS 行为 | Android 现状 | 状态 |
| --- | --- | --- | --- |
| F100 | 问题卡带 “Decisions” 标签和 `questionmark.bubble` 图标，外层 `FloatingSurface`（`iOS/MessageRow.swift:112-116,135`） | 问题卡为浅灰圆角 `Column`，无 “Pending” 标签（`Android/ui/ConversationScreen.kt:874-903`） | 🟡 |
| F101 | 一个请求多问题时，整张请求表单渲染在第一张卡上；后续问题卡在 pending 期间隐藏（`iOS/MessageRow.swift:108-111,118-122`） | 问题卡只显示单题；匹配到多问题请求时直接打开 Feed 页（`Android/CmuxViewModel.kt:1810-1821`） | ❌ |
| F102 | 通过 agent + session + prompt 精确关联 Feed request（`Core/ConversationQuestions.swift:26-38`、`iOS/ConversationModel.swift:625-630`） | 只按 prompt 在会话 feed 中找 pending 项，不校验 agent/session（`Android/CmuxViewModel.kt:1814-1816`） | ❌ |
| F103 | 卡内表单支持 header、选项说明、自定义回答、跳过、多选（`iOS/MessageRow.swift:122`、`iOS/FeedQuestionView.swift:25-66`） | 卡内只显示 prompt 和选项 label，点击即提交，无多选/自定义/跳过（`Android/ui/ConversationScreen.kt:885-898`） | ❌ |
| F104 | 选项行显示圆圈/勾，选中状态有 `.isSelected`（`iOS/FeedQuestionView.swift:30-45`） | 选项仅文本，选中时加 “✓” 前缀（`Android/ui/ConversationScreen.kt:886-898`） | 🟡 |
| F105 | 多选请求可在卡内多选后一次提交（`iOS/FeedQuestionView.swift:33-44`） | 无多选；每次点击只发一个 label（`Android/ui/ConversationScreen.kt:891-896`） | ❌ |
| F106 | 回答中 `answeringQuestion` 阻止重复提交（`iOS/ConversationModel.swift:632-634`） | 无 in-flight 状态，问题卡可连续点击重复提交（`Android/ui/ConversationScreen.kt:875-903`） | ❌ |
| F107 | 提交成功后清除 pending，并把该 request 的所有卡标记为已答、逐卡显示 “Answered: X”（`iOS/ConversationModel.swift:637-641`、`iOS/MessageRow.swift:127-129`） | 提交后 `reloadOpen()` + `refresh()`，依靠历史里的 `selectedOptionLabel` 显示选中项；无乐观已答状态（`Android/CmuxViewModel.kt:1829-1831`、`Android/ui/ConversationScreen.kt:507-514`） | 🟡 |
| F108 | 已无可回答请求且无已选答案时显示 “This question can no longer be answered here.”（`iOS/MessageRow.swift:130-133`） | 仅当 `selected == null && options.isEmpty()` 显示 “Answer in Pending”；有选项时仍可点击，随后可能被跳转到 Feed（`Android/ui/ConversationScreen.kt:899-901`、`Android/CmuxViewModel.kt:1817-1820`） | ❌ |
| F109 | 只有 `canReplyFeed` 时才把回答回调传给卡片（`iOS/ConversationView.swift:300`、`iOS/ConversationModel.swift:626`） | 回答回调无条件传入，未检查 `feedReply`（`Android/ui/AdaptiveRoot.kt:171`） | ❌ |
| F110 | 等待中的问题表单按行在可视边缘逐行模糊，避免整块纹理抖动（`iOS/FeedQuestionView.swift:8-11`、`iOS/MessageRow.swift:117`） | 无边缘模糊效果（`Android/ui/ConversationScreen.kt:874-903`） | ❌ |
| F111 | 回答后与 Feed 共用同一 request，Feed 刷新即可看到 resolved（`iOS/ConversationModel.swift:636-642`） | 回答后同样刷新会话 feed 与列表（`Android/CmuxViewModel.kt:1829-1831,1924-1934`） | ✅ |
| F112 | 问题卡有 `message.<id>` 容器标识，内部表单控件保留各自标识（`iOS/MessageRow.swift:41`、`iOS/FeedQuestionView.swift:43,54`） | 问题卡无 `testTag`/语义标识，仅整体可点击（`Android/ui/ConversationScreen.kt:874-903`） | ❌ |

### 4.5 启动流程（应用启动、连接恢复、会话恢复）

| # | iOS 行为 | Android 现状 | 状态 |
| --- | --- | --- | --- |
| F113 | 启动时无已存 Mac → 配对页；有已存 Mac → 会话列表（`iOS/CmuxRemoteApp.swift:18-19`） | `ShellState.Pairing`（无保存）或连接第一个主 Mac 后进入列表（`Android/CmuxViewModel.kt:552-573`、`Android/ui/AdaptiveRoot.kt:239-275`） | ✅ |
| F114 | `restorePairing()` 载入所有保存的 connection，为每个 Mac 建 `HostLink`（`iOS/AppModel.swift:92-108`） | `restore()` 把所有保存连接载入 `hosts`，但只 `connect(primary)`，live 也只建在主 Mac（`Android/CmuxViewModel.kt:557-572,905-911`） | 🟡 |
| F115 | 每个 Mac 独立客户端和独立 live/follow，多 Mac 状态统一发布（`iOS/AppModel.swift:344-370,419-428`） | 其他 Mac 仅通过 `refresh()` 的 HTTP 读取，非主 Mac 没有独立 live link；打开非主 Mac 也不重建 live（`Android/CmuxViewModel.kt:957-990,1023-1030`） | ❌ |
| F116 | 恢复时没有会话列表快照缓存，列表等待真实读取（`iOS/AppModel.swift:292-331`） | 启动先显示 `SessionSnapshotCache` 中的会话与 pendingCount，再由真实读取替换（`Android/CmuxViewModel.kt:757-758,827-844`） | ➕ |
| F117 | 场景 active：发现设备、监督连接、follow sessions；background：暂停 enrollment、调度 BG refresh（`iOS/CmuxRemoteApp.swift:20-33`） | 无 `scenePhase`/生命周期暂停逻辑（`grep onStop/onPause/ProcessLifecycle` 未找到）；live 与轮询随 ViewModel 生命周期运行（`Android/CmuxViewModel.kt:905-946`） | ❌ |
| F118 | 连接监督：网络路径变化重拨、断线后按退避重试、后台重试的 Mac 进入 `quietHosts` 不打扰 UI（`iOS/AppModel+Connection.swift:45-118`） | 仅 `LiveUpdates` 自身指数退避（1–30s）；无网络路径监听、无 quiet host、无统一重连排程；手动 `retryConnection()` 只 probe + reload（`Android/bridge/LiveUpdates.kt:30-92`、`Android/CmuxViewModel.kt:293-300`） | ❌ |
| F119 | 下拉刷新只重拨断开的 Mac，其余直接重读（`iOS/AppModel+Connection.swift:39-42`） | 列表下拉 `onRefresh` 直接 `refresh()`，不单独重拨断线 Mac（`Android/ui/SessionListScreen.kt:262-264`、`Android/CmuxViewModel.kt:948-1011`） | 🟡 |
| F120 | 后台 BGAppRefresh 最早 60 秒，重拨并读取运行中/变化的会话（`iOS/BackgroundSync.swift:16-18`、`iOS/AppModel.swift:374-394`） | WorkManager 周期最短 15 分钟，最多 4 个 Mac、60 秒预算；只读列表与 pending，不读会话（`Android/background/BackgroundSyncWorker.kt:32-35,134-137`） | 🟡 |
| F121 | 会话可恢复时显示 “Resume conversation” 按钮，需 `resumable` 且该 client 有 `conversationStart`（`iOS/ConversationView.swift:112-119`、`iOS/ConversationModel.swift:12-13`） | 显示 `ResumeBanner`，`onResume` 由全局 `canStart` 决定，不按会话所属 Mac 判断（`Android/ui/ConversationScreen.kt:190-191`、`Android/ui/AdaptiveRoot.kt:165`） | 🟡 |
| F122 | 恢复请求 `POST /v1/sessions/{id}/resume` 后刷新会话，错误显示在会话页（`iOS/ConversationModel.swift:519-527`） | `POST` resume 后 `refresh()`，错误写入会话页（`Android/CmuxViewModel.kt:1581-1596`） | ✅ |
| F123 | 启动会话后在列表显示等待提示并自动打开新会话（见 F25）（`iOS/SessionListView.swift:186-198`） | 启动页等待并自动打开（见 F25）（`Android/CmuxViewModel.kt:1490-1508`） | 🟡 |

### 4.6 布局与视觉

| # | iOS 行为 | Android 现状 | 状态 |
| --- | --- | --- | --- |
| F124 | 纯白画布、强制浅色（`iOS/WhitePage.swift:14-15,34`、`iOS/MobileDesign.swift:11-13`） | 白色 Canvas、固定 lightColorScheme（`Android/ui/theme/MobileDesign.kt:7-15`、`Android/ui/theme/CmuxTheme.kt:13-23`） | ✅ |
| F125 | 页面内边距 20、区块间距 24、行距 12、控件高 44、卡圆角 22（`iOS/MobileDesign.swift:5-10`） | PageInset 20、SectionGap 24、RowGap 12、CardRadius 22、Control 44（`Android/ui/theme/MobileDesign.kt:17-21`） | ✅ |
| F126 | 卡片白底、16 内边距、22 圆角、0.06 黑描边、radius 14/y4 阴影（`iOS/FloatingSurface.swift:4-11`） | 卡片白底、16 内边距、22 圆角、0.5dp 描边、6dp 阴影（`Android/ui/components/FloatingSurface.kt:17-35`） | 🟡 |
| F127 | 按钮为带 0.5 描边和阴影的白胶囊；主按钮 accent 白字；按下透明度 0.65、禁用 0.45（`iOS/FloatingButtonStyle.swift:8-18`） | 主按钮用 Material `Button` 的 accent 胶囊；次按钮用 `OutlinedButton`；无同等阴影/按压缩放（`Android/ui/StartSessionScreen.kt:213-224`、`Android/ui/FeedForms.kt:163-185,367-407`） | 🟡 |
| F128 | 输入框白底 16 圆角、0.5 描边、横向 16/纵向 12 内边距（`iOS/FloatingInput.swift:4-10`） | 使用 Material `OutlinedTextField`，多为默认描边；仅局部显式 14dp 圆角（`Android/ui/StartSessionScreen.kt:184-195`、`Android/ui/FeedForms.kt:477-486`） | 🟡 |
| F129 | 页头为浮动圆形返回/关闭按钮，标题居中 `headline`，两侧 44 占位（`iOS/WhitePage.swift:18-33`） | 页头为 36dp 圆形 chevron + 左对齐 `titleMedium`，新建页无关闭 X（`Android/ui/StartSessionScreen.kt:84-108`、`Android/ui/ProjectScreen.kt:150-172`、`Android/ui/FeedScreen.kt:56-77`） | 🟡 |
| F130 | 使用系统字体与 Dynamic Type，正文 `body`、辅助 `footnote/caption`、代码 `monospaced`（`iOS/StartRow.swift:12-15`、`iOS/ProjectView.swift:49`、`iOS/MessageRow.swift:28-31`） | 固定 Material 字号体系 22/17/16/14/12sp；项目正文 12sp/17 行高（`Android/ui/theme/CmuxTheme.kt:25-56`、`Android/ui/ProjectScreen.kt:337-345`） | 🟡 |
| F131 | Accent `(0.20,0.36,0.96)`，阴影/描边用黑色低透明度（`iOS/MobileDesign.swift:11-13`） | Accent `#335CF5`，并额外定义 Ink/Muted/Line/Soft/AccentSoft/Good/Code（`Android/ui/theme/MobileDesign.kt:7-15`） | 🟡 |
| F132 | 分组折叠有 `easeInOut 0.18` 动画（`iOS/SessionListView.swift:209-211`） | 分组折叠无显式动画，直接条件渲染（`Android/ui/SessionListScreen.kt:294-334`） | 🟡 |
| F133 | 导航 push/sheet 使用系统转场（`iOS/SessionListView.swift:37,155-182`） | 新建页、Feed、项目页均为条件整页替换，无转场动画（`Android/ui/AdaptiveRoot.kt:213-237,346-381`） | 🟡 |
| F134 | Feed 卡片间距 `sectionGap 24`（`iOS/FeedView.swift:17`） | Feed 卡片间距 12dp（`Android/ui/FeedScreen.kt:86-90`） | 🟡 |
| F135 | 项目正文为白底等宽文字，无代码块底色（`iOS/ProjectView.swift:49`） | 项目正文放在 Code 色圆角块中（`Android/ui/ProjectScreen.kt:334-348`） | 🟡 |
| F136 | 过滤/选择 chip 选中用主色文字 + 白色胶囊阴影（`iOS/SessionListView.swift:61-69`） | 过滤/选择 chip 选中用深色 Ink 胶囊 + 白字（`Android/ui/components/Common.kt:29-58`、`Android/ui/StartSessionScreen.kt:235-248`） | 🟡 |
| F137 | 改动行整行可点，最小高度 44（`iOS/ProjectView.swift:43`） | 改动行 8dp 内边距，无显式最小触控高度（`Android/ui/ProjectScreen.kt:294-301`） | 🟡 |
| F138 | 项目复制/分享是带图标的浮动按钮（`iOS/ProjectView.swift:51-54`） | 项目复制/分享/刷新是页头纯文字动作（`Android/ui/ProjectScreen.kt:169-186`） | 🟡 |

### 4.7 无障碍与本地化

| # | iOS 行为 | Android 现状 | 状态 |
| --- | --- | --- | --- |
| F139 | 大量稳定的 `accessibilityIdentifier`：`project.path`、`project.file`、`project.change.*`、`start.workspace.*`、`start.root.*`、`start.agent`、`start.prompt`、`start.here`、`feed.question.*`、`sessions.pending`、`sessions.start_notice`（`iOS/ProjectView.swift:21,44`、`iOS/StartSessionSheet.swift:32`、`iOS/StartRootsView.swift:24`、`iOS/StartFolderView.swift:22-36`、`iOS/FeedQuestionView.swift:43-65`、`iOS/PendingReminder.swift:28`、`iOS/SessionListView.swift:75`） | 未找到 `testTag`/自定义语义标识（`grep testTag` 于 Project/Start/Feed 无命中）；只有基础 `contentDescription`（`Android/ui/ProjectScreen.kt:155-159`、`Android/ui/StartSessionScreen.kt:89-99`、`Android/ui/FeedScreen.kt:61-63`） | ❌ |
| F140 | 当前 Feed 模式、问题选项、列表过滤用 `.isSelected` 暴露选中状态（`iOS/FeedView.swift:19-20`、`iOS/FeedQuestionView.swift:44`、`iOS/SessionListView.swift:69`） | 自定义 chip/选项卡无 selected 语义（`ChoiceChip` 仅变色）；Material `RadioButton`/`Checkbox` 自带语义（`Android/ui/StartSessionScreen.kt:235-248`、`Android/ui/FeedForms.kt:434-454`） | 🟡 |
| F141 | 返回/关闭/搜索/侧栏均有明确 accessibility label（`iOS/WhitePage.swift:23,30`、`iOS/SessionListView.swift:239-257`） | 返回/搜索/侧栏有 `contentDescription`；复制/分享/刷新为文字动作（`Android/ui/ProjectScreen.kt:159,169-171`、`Android/ui/SessionListScreen.kt:237-257`） | 🟡 |
| F142 | 新建会话所有文案来自本地化 key（含失败/截断/等待）（`iOS/StartFolderView.swift:20-39`、`iOS/StartRootsView.swift:14-26`、`iOSRes/en.lproj/Localizable.strings:290-320`） | 界面标签有资源；但启动通知在 ViewModel 写死中文（`Android/CmuxViewModel.kt:1467,1490,1508`；界面资源 `ARes/values-en/strings.xml:246-258`） | ❌ |
| F143 | Feed/项目状态文案完整本地化（含模式标题、效果解释、不可回答说明）（`iOS/FeedDecisionMode+Presentation.swift:4-30`、`iOSRes/en.lproj/Localizable.strings:145-200`） | Feed 状态和权限解释本地化；decision mode 原样回显、部分状态无说明（`Android/ui/FeedScreen.kt:151-161`、`Android/ui/FeedForms.kt:505-519`、`ARes/values-en/strings.xml:202-239`） | 🟡 |

### 4.8 未找到项及搜索词

| # | 项 | 核实结果 | 状态 |
| --- | --- | --- | --- |
| F144 | 文件树/目录树 | 两侧均未找到（`grep tree/file tree/browser` 无命中）；只有改动列表 | ✅ |
| F145 | 新建会话的搜索/最近/收藏 | 两侧均未找到（`grep search/recent/favorite/breadcrumb` 无命中） | ✅ |
| F146 | Feed 分页 | 两侧均未找到（`grep page/cursor/loadMore/next` 无分页参数） | ✅ |
| F147 | Android 网络路径监听/连接监督/quiet host/自动重连排程 | 未找到；仅有 `LiveUpdates` 内部退避（`Android/bridge/LiveUpdates.kt:30-92`） | ❌ |
| F148 | iOS 持久化 pending 计数缓存 | 未找到；仅内存 `pending[hostID]` | ✅ |
| F149 | Android 项目相对路径输入 | 未找到；`ProjectScreen.kt` 只有未使用的 `pathField` 局部变量（`Android/ui/ProjectScreen.kt:74`） | ❌ |
| F150 | Android Feed 错误展示 | 未找到；`FeedScreen` 参数表无 `error`（`Android/ui/FeedScreen.kt:45-52`） | ❌ |

### 4.9 本域 Android 独有

- 新建会话首条消息 4096 UTF-8 字节硬上限和实时字节计数（`Android/ui/StartSessionScreen.kt:51,178-189`）。
- 新建会话单页完成 “工作区 + 根目录 + Agent + 首条消息”，工作区和首个根目录自动选中（`Android/CmuxViewModel.kt:1447-1465`、`Android/ui/StartSessionScreen.kt:118-204`）。
- 项目页自适应双栏：固定 240dp 改动列表 + 正文（折叠屏/平板/横屏）（`Android/ui/ProjectScreen.kt:57,113-136,238-290`）。
- 项目页页头文字动作：Copy / Share / Refresh；刷新会重读 changes 并回到首个改动（`Android/ui/ProjectScreen.kt:141-186`、`Android/ui/AdaptiveRoot.kt:358`）。
- 项目正文代码块底色 + 横向滚动 + `LaunchedEffect` 切换文件时重置横向滚动位置（`Android/ui/ProjectScreen.kt:328-348`）。
- 跨 Mac 聚合 Feed 与聚合 pending 数（无 host 归属、无 host 子菜单）（`Android/CmuxViewModel.kt:993-1004`、`Android/ui/SessionListScreen.kt:268-278`）。
- 持久化每 host 的 pendingCount 快照，启动/读失败时显示缓存值（`Android/background/SessionSnapshotCache.kt:30-36,70-78`、`Android/CmuxViewModel.kt:986-1002`）。
- Feed 历史问题用只读表单回显选项，并标注 “Unanswered”（`Android/ui/FeedForms.kt:107-121`）。
- 计划审批卡固定提供 Execute plan / Auto accept / Continue after edits / Deep plan / Deny 五个快捷按钮（`Android/ui/FeedForms.kt:353-405`）。
- 问题/权限控件使用 Material `RadioButton`/`Checkbox`，自带无障碍语义（`Android/ui/FeedForms.kt:434-454`）。
- 平板/折叠屏 Tabletop 模式：会话 + 首个待处理问题 + 前两个选项的快捷回答（`Android/ui/TabletopScreen.kt:60,85-105`、`Android/ui/AdaptiveRoot.kt:449-468`）。
- 前台 live 更新之外还有 30 秒（列表）/15 秒（会话）慢轮询兜底（`Android/CmuxViewModel.kt:931-946`）。
- WorkManager 后台同步：15 分钟周期、最多 4 个 Mac、单 Mac 20 秒/总 60 秒预算（`Android/background/BackgroundSyncWorker.kt:32-35,134-137`）。
- 启动时先渲染持久化会话列表快照，再被真实读取替换（`Android/CmuxViewModel.kt:757-758,827-844`）。
- 列表按可用高度使用 dense 紧凑间距（`Android/ui/AdaptiveRoot.kt:211`、`Android/ui/SessionListScreen.kt:265,368-390`）。
- 列表底部常驻 host 状态行与刷新入口（`Android/ui/SessionListScreen.kt:392-415`）。
- 新建会话/启动等待的部分提示文案写死中文，而非资源本地化（`Android/CmuxViewModel.kt:1467,1490,1508`）。

## 5. 设计样式、自适应、可访问性与平台行为

> 编号前缀 **D**。路径别名同前；另 `iOSRes/`、`ARes/` 同第 3 节，`android/app/src/main/AndroidManifest.xml` 简写为 `Manifest`。

### 5.1 颜色与表面

| # | iOS | Android | 状态 |
| --- | --- | --- | --- |
| D1 | 画布纯白：`iOS/FloatingSurface.swift:8`、`iOS/WhitePage.swift:15`、`iOS/CmuxRemoteApp.swift:20` | `Android/ui/theme/MobileDesign.kt:7`、`Android/ui/theme/CmuxTheme.kt:16` | ✅ |
| D2 | 强调色 `Color(0.20,0.36,0.96)` = `#335CF5`：`iOS/MobileDesign.swift:11` | `MobileDesign.kt:12` = `#335CF5` | ✅ |
| D3 | 卡片白底、22pt 圆角、0.5pt 描边、阴影：`iOS/FloatingSurface.swift:7-10` | 白底、22dp、0.5dp 描边、`shadow(6.dp)`：`Android/ui/components/FloatingSurface.kt:23-34` | ✅ |
| D4 | 主文字用系统语义色 `.primary`（随浅色模式固定）：`iOS/FloatingIconStyle.swift:9`、`iOS/SessionListView.swift:215` | 固定 `Ink #15171C`：`Android/ui/theme/MobileDesign.kt:8` | 🟡 |
| D5 | 次要文字 `.secondary`：`iOS/SessionListView.swift:223`、`iOS/ConnectionStatusBar.swift:18` | 固定 `Muted #6D727C`：`Android/ui/theme/MobileDesign.kt:9` | 🟡 |
| D6 | 描边 `black.opacity(0.06)`：`iOS/MobileDesign.swift:12` | 描边 `Line #ECEEF2`：`Android/ui/theme/MobileDesign.kt:10` | 🟡 |
| D7 | 错误用系统 `Color.red`：`iOS/FloatingButtonStyle.swift:9`、`iOS/SessionListView.swift:87` | 用 M3 `colorScheme.error`（默认红，无显式 token）：`Android/ui/ConversationScreen.kt:150,632` | 🟡 |
| D8 | 成功用系统 `.green`：`iOS/HostFilterTabs.swift:81`、`iOS/ConnectionDetailView.swift:24` | 专属 `Good #2F9E6B`：`Android/ui/theme/MobileDesign.kt:14`、`Android/ui/components/Common.kt:62-67` | 🟡 |
| D9 | 强调浅底 `accent.opacity(0.085)`：`iOS/MessageRow.swift:31`；选中文字色 `accentColor` | `AccentSoft #E8EDFF`：`Android/ui/theme/MobileDesign.kt:13`；用户气泡 `SessionRow` 选中 `Android/ui/ConversationScreen.kt:725-733` | 🟡 |
| D10 | 会话行无选中底色（列表/详情分页） | 会话行选中 `AccentSoft` 背景：`Android/ui/components/SessionRow.kt:42` | ➕ |
| D11 | 工具卡片浅底 `Color(white:0.975)`：`iOS/ToolDetailCard.swift:42-44` | 工具/代码卡 `Soft #F6F7FA`，圆角 12/14：`Android/ui/ConversationScreen.kt:793,808` | 🟡 |
| D12 | 强制浅色：`iOS/CmuxRemoteApp.swift:20`、`iOS/SessionListView.swift:168`、`iOS/WhitePage.swift:34`、`iOS/ConversationView.swift:194`、`iOS/HistoricalImageView.swift:31` | 仅浅色 `lightColorScheme`：`Android/ui/theme/CmuxTheme.kt:13`；主题父级 `Theme.Material.Light`：`ARes/values/themes.xml:2` | ✅ |
| D13 | 无深色资源/深色切换 | 未找到 `values-night`；无 `darkColorScheme`、`isSystemInDarkTheme` | ✅ |
| D14 | 状态栏文字随浅色模式为深色（无显式配置） | `windowLightStatusBar=true`、透明状态/导航栏：`ARes/values/themes.xml:4-6` | 🟡 |
| D15 | 无专用错误/成功边框 token；仅文字/图标着色 | 同样无专用 token；使用 `Line`/M3 error | ✅ |

### 5.2 字体、字号字重、行高

| # | iOS | Android | 状态 |
| --- | --- | --- | --- |
| D16 | 系统字体（SF Pro）；等宽用 `.monospaced`：`iOS/MessageRow.swift:137` | `FontFamily.SansSerif` / `FontFamily.Monospace`：`Android/ui/theme/CmuxTheme.kt:26-54` | ✅ |
| D17 | 动态字体语义字号：title/headline/body/subheadline/footnote/caption | 自定义固定字号：titleLarge 22、titleMedium 17、bodyLarge 16、bodyMedium 14、labelMedium 12：`Android/ui/theme/CmuxTheme.kt:25-56` | 🟡 |
| D18 | 行高由系统字体度量自动决定 | 显式行高 28/23/23/20/16sp：`Android/ui/theme/CmuxTheme.kt:30,36,42,48,54` | 🟡 |
| D19 | 正文 `.body` 17pt：`iOS/MessageRow.swift:28`、`iOS/ChatComposer.swift:63` | 正文 `bodyLarge` 16sp：`Android/ui/theme/CmuxTheme.kt:38-43` | 🟡 |
| D20 | 标题常用 `.headline`/`.title2`/`.title3`：`iOS/SessionTitleMenu.swift:34`、`iOS/SessionSidebarView.swift:29` | `titleLarge` 22sp / `titleMedium` 17sp：`Android/ui/theme/CmuxTheme.kt:26-37` | 🟡 |
| D21 | 字重 semibold/medium 为主：`iOS/FloatingButtonStyle.swift:10`、`iOS/SessionTitleMenu.swift:34` | SemiBold/Medium：`Android/ui/theme/CmuxTheme.kt:28,34,52` | ✅ |
| D22 | 等宽代码/诊断：`iOS/ToolCodeBlock`、`.system(.caption, design:.monospaced)`：`iOS/DiagnosticLogView.swift:70` | `FontFamily.Monospace`，12sp/18sp：`Android/ui/ConversationScreen.kt:815-817`；诊断 11sp/15sp：`Android/ui/DiagnosticLogScreen.kt:118-120` | ✅ |
| D23 | 动态字体缩放：语义字号自动缩放；`@ScaledMetric`：`iOS/ChatComposer.swift:31`；`UIFontMetrics`：`iOS/SelectableTextView.swift:22`；但有 14 处固定 `.system(size:)` 不缩放（如 `iOS/FloatingIconStyle.swift:8`、`iOS/ConversationView.swift:592`） | 全部 sp 随 fontScale 缩放；但固定 dp 容器/按钮（36dp 返回、34dp 发送）不随字体增长：`Android/ui/ConversationScreen.kt:340,1011` | 🟡 |
| D24 | 固定点数字号：20/21/22pt 图标与 16pt 页脚图标：`iOS/SessionSidebarView.swift:34,37`、`iOS/ResponseFooter.swift:34` | 固定 sp：11/12/13/15/20/22sp：`Android/ui/components/TopBar.kt:57`、`Android/ui/DiagnosticLogScreen.kt:119`、`Android/ui/ConversationScreen.kt:988` | 🟡 |

### 5.3 间距、圆角、阴影、描边

| # | iOS | Android | 状态 |
| --- | --- | --- | --- |
| D25 | PageInset 20、SectionGap 24、RowGap 12、SurfaceInset 16、Control 44：`iOS/MobileDesign.swift:5-10` | PageInset 20、SectionGap 24、RowGap 12、Control 44：`Android/ui/theme/MobileDesign.kt:17-21`；卡片内 16：`Android/ui/components/FloatingSurface.kt:20` | ✅ |
| D26 | 卡片圆角 22：`iOS/MobileDesign.swift:9` | `CardRadius 22.dp`：`Android/ui/theme/MobileDesign.kt:20` | ✅ |
| D27 | 输入框圆角 16：`iOS/FloatingInput.swift:8` | 搜索/输入条为胶囊或 M3 `OutlinedTextField`，无统一 16dp 输入卡：`Android/ui/SessionListChrome.kt:66`、`Android/ui/ConversationScreen.kt:944`、`Android/ui/SessionActions.kt:105` | 🟡 |
| D28 | 用户气泡圆角 24、内边距 16/13：`iOS/MessageRow.swift:30-31` | 用户气泡圆角 20、内边距 14/11：`Android/ui/ConversationScreen.kt:726-733` | 🟡 |
| D29 | 工具详情卡圆角 22：`iOS/ToolDetailCard.swift:43` | 工具行/卡圆角 12/14：`Android/ui/ConversationScreen.kt:793,808` | 🟡 |
| D30 | 抽屉面板圆角 38：`iOS/SideDrawer.swift:31,43` | `PanelCornerRadius 38.dp`：`Android/ui/AppDrawer.kt:57,107-108` | ✅ |
| D31 | 卡片阴影 radius 14/y4/6%；按钮 radius 10/y3；图标 radius 12/y3：`iOS/FloatingSurface.swift:10`、`iOS/FloatingButtonStyle.swift:17`、`iOS/FloatingIconStyle.swift:18` | 卡片 `shadow(6.dp)`、抽屉 `16.dp` 黑 13%；按钮无自定义阴影：`Android/ui/components/FloatingSurface.kt:29`、`Android/ui/AppDrawer.kt:170-177` | 🟡 |
| D32 | 描边统一 0.5pt：`iOS/FloatingSurface.swift:9`、`iOS/FloatingButtonStyle.swift:16` | 统一 0.5dp：`Android/ui/components/FloatingSurface.kt:30` | ✅ |
| D33 | 主按钮蓝底白字胶囊、次按钮白底黑字胶囊、危险白底红字、禁用降透明度：`iOS/FloatingButtonStyle.swift:9-18` | 主按钮 `Button`、次按钮 `OutlinedButton`、危险 M3 error 文本；禁用走 Material alpha：`Android/ui/TabletopScreen.kt:100-111`、`Android/ui/ConversationScreen.kt:285-293` | 🟡 |
| D34 | 图标按钮 44×44 白色圆形/玻璃，按下 0.6、禁用 0.4：`iOS/FloatingIconStyle.swift:8-18` | `IconButton` 默认 48dp 命中区、无浮动圆底；部分自绘 20-36dp：`Android/ui/components/TopBar.kt:42-47`、`Android/ui/ConversationScreen.kt:340,361` | ❌ |
| D35 | 标题/列表间距 24：`iOS/SessionListView.swift:53,84` | 列表项间距 16（dense 10）：`Android/ui/SessionListScreen.kt:263-266` | ❌ |
| D36 | 组内会话缩进 34pt：`iOS/SessionListView.swift:122` | 组内会话无缩进：`Android/ui/SessionListScreen.kt:326-332` | ❌ |
| D37 | 页眉水平 20pt：`iOS/SessionListView.swift:259` | 页眉水平 8/16dp（与正文 20dp 不一致）：`Android/ui/SessionListScreen.kt:231`、`Android/ui/ConversationScreen.kt:334` | 🟡 |

### 5.4 材质、模糊、玻璃

| # | iOS | Android | 状态 |
| --- | --- | --- | --- |
| D38 | iOS 26 用系统 `glassEffect`，旧版白圆+阴影：`iOS/FloatingIconStyle.swift:13-18,30-31` | 无玻璃/模糊等价物，纯色 Surface：`Android/ui/components/FloatingSurface.kt:24-33` | ❌ |
| D39 | 会话头/底栏白色 0.95 半透明幕：`iOS/ConversationView.swift:83-85,122-123` | 无半透明/模糊头栏，纯白 `Canvas`：`Android/ui/ConversationScreen.kt:124,333-336` | ❌ |
| D40 | `HeaderContentEffect.EdgeBlur` 为空实现（已移除 shader 模糊）：`iOS/HeaderContentEffect.swift:5-7` | 无边缘模糊实现 | ✅ |
| D41 | 白底 `ignoresSafeArea`：`iOS/WhitePage.swift:15`、`iOS/SessionListView.swift:140` | Shell 白底 + `safeDrawing`：`Android/ui/AdaptiveRoot.kt:207-212` | 🟡 |

### 5.5 图标来源与尺寸

| # | iOS | Android | 状态 |
| --- | --- | --- | --- |
| D42 | SF Symbols（`chevron.left`、`line.3.horizontal`、`magnifyingglass`、`laptopcomputer` 等）：`iOS/WhitePage.swift:22`、`iOS/SessionListView.swift:242,256`、`iOS/HostFilterTabs.swift:35` | Material Icons Rounded（`ChevronLeft`、`Menu`、`Search`、`Computer` 等）：`Android/ui/components/TopBar.kt:9-12`、`Android/ui/components/SessionRow.kt:13-14` | 🟡 |
| D43 | 默认图标 20pt，浮动按钮 44pt：`iOS/FloatingIconStyle.swift:8-10`；小图标 12-22pt | 图标 15-22dp，部分 7dp 状态点：`Android/ui/components/SessionRow.kt:71,77`、`Android/ui/components/Common.kt:65`、`Android/ui/components/TopBar.kt:64` | 🟡 |
| D44 | 列表行尾部 `chevron.right`：`iOS/SessionListView.swift:226` | 列表行仅 WorkingIndicator，无 chevron：`Android/ui/components/SessionRow.kt:65-79` | ❌ |
| D45 | 会话头部 `ellipsis` 玻璃圆：`iOS/ConversationView.swift:592` | 20dp `MoreVert` 可点击图标：`Android/ui/ConversationScreen.kt:357-362` | 🟡 |
| D46 | 应用图标单一 1024×1024 通用图：`iOSRes/Assets.xcassets/AppIcon.appiconset/Contents.json:4-7`、`iOSRes/APP-ICON.md:3-6` | 自适应图标 + 各密度 PNG/圆形图标：`ARes/mipmap-anydpi-v26/ic_launcher.xml:2-5`、`ARes/mipmap-*/ic_launcher*.png` | 🟡 |
| D47 | 系统自动加圆角遮罩 | 无 Android 13 主题化单色图标（`ic_launcher.xml` 未找到 `<monochrome>`） | 🟡 |

### 5.6 导航栏、标题、页面结构

| # | iOS | Android | 状态 |
| --- | --- | --- | --- |
| D48 | `NavigationStack` + 原生 push/pop：`iOS/AppNavigationStack.swift:7-9` | 无 Navigation 组件，条件组合切换页面：`Android/ui/AdaptiveRoot.kt:239-469` | ❌ |
| D49 | 原生 push/pop 转场；连接/配对用 `fullScreenCover`、新建会话用 `sheet`：`iOS/SessionListView.swift:170-182`、`iOS/PairingView.swift:36-39` | 全屏条件替换，无转场、无 sheet：`Android/ui/AdaptiveRoot.kt:214-236,553-596` | ❌ |
| D50 | 隐藏系统导航栏，自绘浮动头：`iOS/WhitePage.swift:17-33`、`iOS/SessionListView.swift:141-144` | `NoActionBar` 主题 + 自绘标题行：`ARes/values/themes.xml:2`、`Android/ui/ConversationScreen.kt:333-384` | 🟡 |
| D51 | 列表标题是本地化 “Sessions” + chevron 菜单：`iOS/SessionTitleMenu.swift:32-37` | 标题硬编码 `"Cmux"`、22sp、无 chevron：`Android/ui/SessionListChrome.kt:111-118` | ❌ |
| D52 | 标题菜单含排序、待处理分主机计数、刷新、新建、添加 Mac：`iOS/SessionTitleMenu.swift:15-31` | 排序、待处理（总数）、刷新、新建、添加 Mac、连接详情：`Android/ui/SessionListChrome.kt:119-144` | 🟡 |
| D53 | 头部顺序：抽屉按钮、标题菜单、搜索，浮动玻璃圆：`iOS/SessionListView.swift:234-259` | 菜单、标题、搜索、加号，普通 IconButton：`Android/ui/SessionListScreen.kt:229-260` | 🟡 |
| D54 | 搜索框白底 16pt 圆角+描边，进入即聚焦：`iOS/SessionSearchField.swift:9-17`、`iOS/FloatingInput.swift:6-9` | 搜索框 `Soft` 胶囊、无描边、进入即聚焦：`Android/ui/SessionListChrome.kt:63-87` | 🟡 |
| D55 | 过滤胶囊白底+选中阴影+`.isSelected`：`iOS/SessionListView.swift:59-70` | `Pill` 选中为 `Ink` 深底，无选中语义：`Android/ui/components/Common.kt:36-57`、`Android/ui/SessionListScreen.kt:352-364` | 🟡 |
| D56 | 主机标签含连接/离线/绿点状态、工作区嵌套菜单：`iOS/HostFilterTabs.swift:30-82` | 主机胶囊恒为绿点，无状态、无工作区嵌套；工作区为独立胶囊：`Android/ui/SessionListChrome.kt:148-207` | ❌ |
| D57 | 抽屉是完整会话树：搜索、排序、主机/工作区分组、会话行：`iOS/SessionSidebarView.swift:25-66` | 抽屉仅工作区列表+计数+连接/添加 Mac 页脚，无会话行/搜索/排序：`Android/ui/SessionListScreen.kt:112-165` | ❌ |
| D58 | 抽屉页脚显示主机失败图标与连接入口：`iOS/SessionSidebarView.swift:70-85` | 页脚显示绿点+主机名+添加 Mac 文本：`Android/ui/SessionListScreen.kt:148-164` | 🟡 |
| D59 | 列表页脚无固定主机条 | 固定页脚显示绿点、主机名、MoreVert 刷新：`Android/ui/SessionListScreen.kt:347,392-415` | ➕ |
| D60 | 页面使用统一 `WhitePage`（14 处调用）：`iOS/WhitePage.swift:13-37` | 各页面重复自绘 36dp 返回头，无统一容器：`Android/ui/ProjectScreen.kt:141-173`、`Android/ui/DiagnosticLogScreen.kt:95-113`、`Android/ui/TextAndTiming.kt:243-275` | 🟡 |
| D61 | `TopBar` 无对应物 | `TopBar` 组件已定义但未使用；全项目 `TopBar(` 调用 0 次：`Android/ui/components/TopBar.kt:28` | ➕ |

### 5.7 返回手势、边缘滑动、抽屉物理动画

| # | iOS | Android | 状态 |
| --- | --- | --- | --- |
| D62 | UIKit 原生交互返回 + 隐藏导航栏后修复 delegate：`iOS/InteractivePopController.swift:26-45`、`iOS/InteractivePopInstaller.swift:4-9` | 无边缘返回手势，仅系统返回键 `BackHandler`：`Android/ui/AdaptiveRoot.kt:216,347`、`Android/ui/AppDrawer.kt:94` | ❌ |
| D63 | 根替换页自定义边缘返回：边缘 24、提交 56、阈值 12：`iOS/EdgeBackSwipe.swift:14-27`；`iOS/WhitePage.swift:36` | 未找到边缘返回（`grep EdgeBackSwipe/edge.*back` 仅 iOS） | ❌ |
| D64 | 抽屉左缘开启条 12pt：`iOS/SideDrawer.swift:50-55` | `EdgeStripWidth 12.dp`：`Android/ui/AppDrawer.kt:59-60,208-217` | ✅ |
| D65 | 抽屉宽 `min(440, 0.77×宽)`：`iOS/SideDrawer.swift:15` | `minOf(440.dp, maxWidth*0.77f)`：`Android/ui/AppDrawer.kt:97` | ✅ |
| D66 | 抽屉弹簧 `response 0.32 / damping 0.9`：`iOS/SideDrawer.swift:58,77,85` | 同参数换算 stiffness：`Android/ui/AppDrawer.kt:66-69,330-335` | ✅ |
| D67 | 位移跟手、松手提交阈值 25%，用 `predictedEndTranslation`：`iOS/DrawerDragState.swift:12-15`、`iOS/SideDrawer.swift:78-80` | 阈值 25%，速度投影 0.3s：`Android/ui/AppDrawer.kt:71-75,296-308` | 🟡 |
| D68 | 抽屉幕布白 40%，点击关闭：`iOS/SideDrawer.swift:32-40` | 白 40% scrim，点击/左拖关闭：`Android/ui/AppDrawer.kt:189-205` | ✅ |
| D69 | 抽屉手势仅横向，`minimumDistance 12`，非活跃 scene 取消：`iOS/SideDrawer.swift:68-72` | 横向优先，阈值 `max(12dp, touchSlop)`，取消流保持原状态：`Android/ui/AppDrawer.kt:247-249,269-275,296-308` | ✅ |
| D70 | Reduce Motion 读取 `accessibilityReduceMotion`，仅抽屉：`iOS/SideDrawer.swift:9,58` | 读取 `ANIMATOR_DURATION_SCALE==0`，仅抽屉：`Android/ui/AppDrawer.kt:91,330-344` | 🟡 |
| D71 | VoiceOver escape 关闭抽屉/页面：`iOS/SideDrawer.swift:60`、`iOS/WhitePage.swift:37` | 系统返回键关闭：`Android/ui/AppDrawer.kt:94`、`Android/ui/AdaptiveRoot.kt:216` | 🟡 |
| D72 | 未找到预测性返回相关实现 | `enableOnBackInvokedCallback=true`：`Manifest:20`；未找到预测性返回预览/动画（`grep PredictiveBack/BackEventCompat`） | ❌ |

### 5.8 键盘与焦点

| # | iOS | Android | 状态 |
| --- | --- | --- | --- |
| D73 | 搜索打开即聚焦：`iOS/SessionSearchField.swift:7,17` | 搜索打开即 `requestFocus`：`Android/ui/SessionListChrome.kt:55-57,75` | ✅ |
| D74 | 输入栏聚焦/多行时展开为全宽大输入区并动画：`iOS/ChatComposer.swift:29,34,37-59` | 输入框固定 `maxLines=4`，无聚焦展开：`Android/ui/ConversationScreen.kt:984-997` | ❌ |
| D75 | 键盘避让由 `safeAreaInset(bottom)` 自动处理：`iOS/ConversationView.swift:90-124`；交互式收起：`:420`；点击页面收起：`:283` | 内容区靠 `WindowInsets.safeDrawing`（含 IME）整体避让：`Android/ui/AdaptiveRoot.kt:212`；但抽屉面板本身无安全区（`Android/ui/AppDrawer.kt:153-163`），输入框不随聚焦展开，也无滚动/点击收起 | 🟡 |
| D76 | 焦点状态由 `FocusState` 驱动（搜索/输入栏）：`iOS/SessionSearchField.swift:7`、`iOS/ChatComposer.swift:9` | 仅搜索用 `FocusRequester`；输入栏无焦点状态：`Android/ui/SessionListChrome.kt:34-35` | 🟡 |

### 5.9 自适应布局（Compact/TwoPane/ThreePane/Tabletop）

| # | iOS | Android | 状态 |
| --- | --- | --- | --- |
| D77 | 手机单栏 Compact 基线：`iOS/SessionListView.swift:50-159` | `PaneLayout.Compact`：`Android/adaptive/PaneLayout.kt:8`、`Android/ui/AdaptiveRoot.kt:329-392` | ✅ |
| D78 | 未找到 `PaneLayout`/`TwoPane`/`ThreePane`/`Tabletop`/铰链实现（`grep` 仅 GeometryReader） | `TwoPane` 浏览器+详情：`Android/adaptive/PaneLayout.kt:10-14`、`Android/ui/AdaptiveRoot.kt:394-436`；浏览器宽 240–280/320–400：`Android/adaptive/PaneLayoutPolicy.kt:49-63` | ➕ |
| D79 | 无三栏 | `ThreePane` + 支撑栏（最近一次文件改动/diff）：`Android/adaptive/PaneLayout.kt:16-21`、`Android/ui/AdaptiveRoot.kt:438-447`、`Android/ui/TabletopScreen.kt:134-159` | ➕ |
| D80 | 无平板/折叠屏双栏；iPad 仅方向旋转，仍是单栏拉伸（`grep` 无 pane 逻辑） | `Tabletop` 半折姿态：上时间线/下输入与审批：`Android/adaptive/PaneLayout.kt:23-27`、`Android/ui/TabletopScreen.kt:33-79` | ➕ |
| D81 | 无铰链检测 | `FoldingFeature` → `HingeState`：`Android/adaptive/HingeState.kt:7-22`、`Android/adaptive/RememberHingeState.kt:24-56` | ➕ |
| D82 | 未找到共享断点代码；`docs/ADAPTIVE-MOBILE-PLAN.md:3,15-16` 明确 iOS 折叠适配暂缓 | 断点 600/720/1100/480 等：`Android/adaptive/PaneLayoutPolicy.kt:10-21,32-83`；单测覆盖 12 例：`android/app/src/test/.../PaneLayoutPolicyTest.kt:1` | ➕ |
| D83 | 项目页始终单栏：`iOS/ProjectView.swift:17-57` | 项目页按最短边 <600 选择 Compact/宽屏双栏：`Android/ui/ProjectScreen.kt:113-136` | ➕ |
| D84 | 新建会话始终单栏 sheet：`iOS/StartSessionSheet.swift:24-34` | 明确 “任何宽度单栏”：`Android/ui/StartSessionScreen.kt:53-56` | ✅ |
| D85 | iPhone 仅竖屏；iPad 四方向：`ios/Info.plist:19-29` | 无方向锁定，`resizeableActivity=true`：`Manifest:24` | 🟡 |
| D86 | 文档称多场景生成开启，但布局无多栏；选择状态在 `@State`：`iOS/SessionListView.swift:7-32` | 单 Activity；仅少量 `rememberSaveable`：`Android/ui/AdaptiveRoot.kt:22` | 🟡 |
| D87 | 安全区：`safeAreaInset` + `ignoresSafeArea`（15 处） | 7 处 `windowInsetsPadding(WindowInsets.safeDrawing)`；抽屉本体未加安全区：`Android/ui/AppDrawer.kt:153-163` | 🟡 |
| D88 | 抽屉背景/阴影覆盖整屏并补偿上下安全区：`iOS/SideDrawer.swift:17-18,42-48` | 抽屉无 inset，顶部硬编码 52dp：`Android/ui/SessionListScreen.kt:128` | ❌ |
| D89 | 无按高度压缩列表 | 高度 <560dp 时 `dense`，收紧列表间距/待处理卡：`Android/ui/AdaptiveRoot.kt:211`、`Android/ui/SessionListScreen.kt:265,369` | ➕ |
| D90 | 状态栏/刘海由系统安全区处理 | `enableEdgeToEdge` + `safeDrawing`：`Android/MainActivity.kt:14`、`Android/ui/AdaptiveRoot.kt:212` | 🟡 |

### 5.10 动画与反馈

| # | iOS | Android | 状态 |
| --- | --- | --- | --- |
| D91 | 原生导航转场；分组折叠 `easeInOut 0.18`：`iOS/SessionListView.swift:210` | 无导航转场；分组折叠瞬时（`actions.onToggleGroup` 直接改状态）：`Android/ui/SessionListScreen.kt:300` | ❌ |
| D92 | 运行指示器自绘 `TimelineView(.animation)` 0.9s 旋转、次要色描边、16pt：`iOS/WorkingIndicator.swift:4-16` | M3 `CircularProgressIndicator`、强调色、14dp、2dp 描边：`Android/ui/components/WorkingIndicator.kt:12-17` | 🟡 |
| D93 | 其他动效：缩放 `interactiveSpring`、滚动 `easeOut`、后台任务 `.snappy`、连接条 `easeInOut`：`iOS/ZoomableImage.swift:32`、`iOS/ClippedScroller.swift:44`、`iOS/BackgroundTasksBar.swift:19`、`iOS/ConnectionStatusBar.swift:38` | 除抽屉外未找到显式动画（`grep animate/AnimatedVisibility/Crossfade` 仅抽屉/滚动）：`Android/ui/AppDrawer.kt:115,314` | 🟡 |
| D94 | 无触感反馈实现（`grep Haptic/UIImpactFeedback` 无结果） | 无触感反馈实现 | ✅ |

### 5.11 无障碍（VoiceOver/TalkBack）

| # | iOS | Android | 状态 |
| --- | --- | --- | --- |
| D95 | 90 处 `accessibilityIdentifier`（如 `sessions.sidebar`、`chat.send`）：`iOS/SessionListView.swift:246,257`、`iOS/ChatComposer.swift:93` | `testTag` 0 处；无 UI 测试标识体系（`grep testTag` 无结果） | ❌ |
| D96 | 32 处显式 `accessibilityLabel`、`accessibilityValue`：`iOS/HostFilterTabs.swift:49,54`、`iOS/SessionTitleMenu.swift:37` | 主要靠 `contentDescription`；约 20 处图标 `contentDescription=null`：`Android/ui/ConversationScreen.kt:797,802`、`Android/ui/components/Common.kt:48,82` | 🟡 |
| D97 | `.isSelected`/`.isHeader` 共 10 处：`iOS/SessionListView.swift:69,86,100`、`iOS/HostFilterTabs.swift:24,50,54` | 未找到 `selected`/`heading()`/`stateDescription` 语义（`grep` 仅业务参数） | ❌ |
| D98 | 读屏分组/顺序：`.accessibilityElement(children:.combine/.contain)`：`iOS/ConnectionStatusBar.swift:21,32`、`iOS/MessageRow.swift:41`、`iOS/OutgoingPromptRow.swift:22` | 仅抽屉用 `clearAndSetSemantics` 隐藏/透传；无分组、无遍历顺序：`Android/ui/AppDrawer.kt:160,184,195,214` | ❌ |
| D99 | 运行中指示器有读屏标签 `chat.working`：`iOS/WorkingIndicator.swift:16` | 进度指示器无 `contentDescription`/live region：`Android/ui/components/WorkingIndicator.kt:13-17` | ❌ |
| D100 | 浮动图标 44pt 命中区，部分再扩大 `Circle().inset(-8)`：`iOS/SessionListView.swift:245`、`iOS/ConversationView.swift:558` | 大量 20/34/36dp 点击目标：`Android/ui/ConversationScreen.kt:340,361,1011`、`Android/ui/PairingScreen.kt:102`、`Android/ui/FeedScreen.kt:62` | ❌ |
| D101 | 装饰性 SF Symbol 常与文字组合并给出按钮标签：`iOS/ResponseFooter.swift:19-24` | 装饰图标多为 `null`，依赖相邻文字；状态点用 `semantics` 描述：`Android/ui/ToolCards.kt:214-219` | 🟡 |
| D102 | VoiceOver escape 动作：`iOS/WhitePage.swift:37`、`iOS/SideDrawer.swift:60` | 系统返回键等价：`BackHandler`（多处） | 🟡 |

### 5.12 本地化、日期与相对时间

| # | iOS | Android | 状态 |
| --- | --- | --- | --- |
| D103 | 语言：en + zh-Hans，开发区域 en：`iOSRes/*.lproj/Localizable.strings`、`ios/CmuxRemote.xcodeproj/project.pbxproj:392` | 默认资源为中文，另有 `values-en`；非中英设备会回落中文：`ARes/values/strings.xml`、`ARes/values-en/strings.xml` | 🟡 |
| D104 | 322 个字符串键，en/zh 完全一致（脚本比对 322=322，无差集） | 275 个字符串键，default/en 完全一致（275=275，无差集） | ✅ |
| D105 | 本地化键数量 322，覆盖更多界面文案 | 275 键，跨端覆盖少 47 键；且 `sessions_filter_pending` 未使用：`ARes/values/strings.xml:130` | ❌ |
| D106 | 366 处 `String(localized:)` | 303 处 `R.string.*` | 🟡 |
| D107 | 未找到硬编码用户可见英文/符号（除 `·`、`→` 等排版符） | 硬编码：`"Cmux"`（`Android/ui/SessionListChrome.kt:112`）、`"Studio"`（`Android/ui/SessionListScreen.kt:347,393`）、`"✕"`/`"↓"`（`Android/ui/ConversationScreen.kt:236,646`）、`"−"`/`"+"`（`Android/ui/QrScannerScreen.kt:261,271`）、URL 占位（`Android/ui/PairingScreen.kt:234`） | ❌ |
| D108 | 相对时间用系统 `.relative(presentation:.named)`，完全本地化：`iOS/SessionListView.swift:219` | 自建 “刚刚/分钟前/小时前/天前” 字符串，仅这 4 档：`Android/ui/AdaptiveRoot.kt:667-676`、`ARes/values/strings.xml:27-30` | ❌ |
| D109 | 日期时间用系统格式样式，随语言/地区：`iOS/ResponseFooter.swift:26-31`、`iOS/ToolDetailCard.swift:32-37` | 固定 `Locale.US` 模式 `HH:mm`/`MM-dd HH:mm`：`Android/ui/TextAndTiming.kt:59-60,304-309`；诊断 `HH:mm:ss.SSS`：`Android/ui/DiagnosticLogScreen.kt:63` | ❌ |
| D110 | 时长单位走本地化格式串：`iOS/ResponseRunLabel.swift:15-20`、`iOS/LiveRunLabel.swift:38-43` | 硬编码 `s`/`m`/`h` 且 `Locale.US`：`Android/ui/TextAndTiming.kt:288-301`、`Android/ui/ConversationScreen.kt:784` | ❌ |
| D111 | RTL：原生返回手势检查 `effectiveUserInterfaceLayoutDirection`：`iOS/InteractivePopController.swift:42` | `supportsRtl=true`：`Manifest:25`；但抽屉/手势均按 leading/正 x 假设，未找到 RTL 手势处理 | 🟡 |
| D112 | 权限用途说明本地化：`iOSRes/en.lproj/InfoPlist.strings:1-5`、`iOSRes/zh-Hans.lproj/InfoPlist.strings:1-5` | 系统权限弹窗文案由 OS 提供，无应用内用途串 | 🟡 |
| D113 | 显示名 “Cmux Remote” 本地化：`iOSRes/*.lproj/InfoPlist.strings:1`、`ios/CmuxRemote.xcodeproj/project.pbxproj:348` | `app_name` = “Cmux Remote”：`ARes/values/strings.xml:2`、`ARes/values-en/strings.xml:2` | ✅ |

### 5.13 启动页、应用图标、隐私与权限

| # | iOS | Android | 状态 |
| --- | --- | --- | --- |
| D114 | 生成式 Launch Screen（无自定义启动页资源）：`ios/CmuxRemote.xcodeproj/project.pbxproj:355,371` | 无 `windowSplashScreen*`/专用启动主题；使用系统默认启动画面（`grep` 无结果） | 🟡 |
| D115 | 单一 1024 通用 AppIcon：`iOSRes/Assets.xcassets/AppIcon.appiconset/Contents.json:4-7` | 自适应图标 + mdpi–xxxhdpi PNG + round 变体：`ARes/mipmap-anydpi-v26/ic_launcher.xml:2-5`、`ARes/mipmap-anydpi-v26/ic_launcher_round.xml:2-5` | 🟡 |
| D116 | 隐私清单 `PrivacyInfo.xcprivacy`（文件时间戳 API，无追踪/收集）：`iOSRes/PrivacyInfo.xcprivacy:5-23` | 无隐私清单等价文件；`allowBackup=false`：`Manifest:19` | 🟡 |
| D117 | 权限/用途：相机、麦克风、语音识别、本地网络、Bonjour：`ios/CmuxRemote.xcodeproj/project.pbxproj:350-353`、`ios/Info.plist:15-18` | INTERNET、网络状态、多播、录音、相机、相机特性非必需：`Manifest:4-16` | 🟡 |
| D118 | 系统相机/照片/文件选择器与权限弹窗：`iOS/ConversationView.swift:125-135`、`iOS/PairingView.swift:45-53` | CameraX 扫码运行时请求 CAMERA：`Android/ui/QrScannerScreen.kt:106-123`；语音请求 RECORD_AUDIO：`Android/speech/SpeechInput.kt:158-189`；Photo Picker/OpenDocument：`Android/ui/AdaptiveRoot.kt:101-106` | ✅ |
| D119 | 本地网络权限弹窗有用途说明与 Bonjour 服务：`ios/CmuxRemote.xcodeproj/project.pbxproj:350`、`ios/Info.plist:15-18` | Android 无本地网络运行时权限声明；使用多播/NSD | 🟡 |
| D120 | 钥匙串访问组：`ios/CmuxRemote.entitlements:4` | Keystore/私有文件，`allowBackup=false`：`Manifest:19` | 🟡 |

### 5.14 测试标识与测试覆盖

| # | iOS | Android | 状态 |
| --- | --- | --- | --- |
| D121 | 90 个 `accessibilityIdentifier` 支撑 XCUITest：`iOS/SessionListView.swift:246,257`、`iOS/ChatComposer.swift:67,76,93` | 0 个 `testTag`；无 `androidTest` 目录，因此无 Compose UI 测试 | ❌ |
| D122 | 23 个 UITest 文件、32 个测试函数：`ios/UITests/MobileGestureUITests.swift:1`、`ios/UITests/MobileDisclosureUITests.swift:1` 等 | 17 个 JVM 单测文件、93 个 `@Test`；仅 `PaneLayoutPolicyTest`（12 例）与 `MarkdownParseTest` 涉及 UI 边界 | ❌ |
| D123 | 设计/渲染单测：`ios/Tests/DrawerDragTests.swift:1`、`DrawerRenderingTests.swift:1`、`MobileNavigationTests.swift:1`、`DurationFormatTests.swift:1` | 无抽屉/导航/字体渲染测试；仅布局策略测试：`android/app/src/test/.../PaneLayoutPolicyTest.kt:1` | 🟡 |
| D124 | 截图测试/商店截图：`ios/UITests/MobileStoreScreenshotsUITests.swift:1` | 未找到截图测试（无 androidTest、无 Paparazzi/Roborazzi） | ❌ |
| D125 | 测试用 launchEnvironment/launchArguments（配对夹具、强制 zh-Hans）：`ios/UITests/MobileDisclosureUITests.swift:10-13` | Debug intent extras 注入配对码/重置身份/添加设备/中转：`Android/MainActivity.kt:16-30` | 🟡 |

### 5.15 其他平台行为

| # | iOS | Android | 状态 |
| --- | --- | --- | --- |
| D126 | 后台刷新 `BGAppRefreshTask`，标识 `cmux-remote.sync`，最早 60s：`iOS/BackgroundSync.swift:15-27`、`ios/Info.plist:5-12` | WorkManager 周期任务，最短 15 分钟、网络约束、最多 4 台 Mac/60s：`Android/background/BackgroundSyncWorker.kt:32-40,140-152` | 🟡 |
| D127 | 未使用本地/远程通知（无 UNUserNotification） | 未使用通知；无 POST_NOTIFICATIONS | ✅ |
| D128 | `scenePhase` 驱动恢复/暂停配对、前后台同步、连接监督：`iOS/CmuxRemoteApp.swift:20-33` | 单 Activity + ViewModel；无 scenePhase/前台生命周期钩子（`grep scenePhase/LifecycleEventObserver` 无结果） | 🟡 |
| D129 | `@AppStorage` 排序/后台同步、`@SceneStorage` 折叠状态：`iOS/SessionListView.swift:20,29`、`iOS/ConnectionDetailView.swift:17` | 状态集中在 ViewModel，极少 `rememberSaveable`：`Android/ui/AdaptiveRoot.kt:22` | 🟡 |
| D130 | 分享/选图：`PhotosPicker`、`fileImporter`、`ShareLink`、`UIPasteboard`：`iOS/ConversationView.swift:125-135`、`iOS/ResponseFooter.swift:19` | Photo Picker、OpenDocument、`ACTION_SEND`+FileProvider、ClipboardManager：`Android/ui/AdaptiveRoot.kt:101-126`、`Android/ui/ConversationScreen.kt:181` | ✅ |
| D131 | 连接异常为白色胶囊状态条（重连旋转/橙色 wifi/重试）：`iOS/ConnectionStatusBar.swift:10-38`、`iOS/ConversationView.swift:78-86` | 仅离线全宽 errorContainer 条，含重试文字；无重连状态条：`Android/ui/ConversationScreen.kt:139-163` | ❌ |
| D132 | 多 Mac 状态逐主机展示（connecting/unreachable/connected）：`iOS/HostFilterTabs.swift:63-82` | 主机胶囊恒绿；无逐主机状态：`Android/ui/SessionListChrome.kt:167-178` | ❌ |
| D133 | 下拉刷新 `.refreshable`：`iOS/SessionListView.swift:152` | `PullToRefreshBox`：`Android/ui/SessionListScreen.kt:262` | ✅ |
| D134 | 后台任务条可展开/查看详情：`iOS/BackgroundTasksBar.swift:19-44` | 后台任务行/详情 sheet：`Android/ui/ConversationScreen.kt:179-189`、`Android/ui/BackgroundTasks.kt` | ✅ |
| D135 | 深链/配对导入在页面内处理 | Debug 启动钩子支持 `enroll_code`/`enroll_file`/`relay_origin`：`Android/MainActivity.kt:24-30` | ➕ |

### 5.16 本域 Android 独有

1. 折叠/平板自适应布局：`Compact / TwoPane / ThreePane / Tabletop` 与共享断点（`Android/adaptive/PaneLayout.kt:7-28`、`Android/adaptive/PaneLayoutPolicy.kt:9-84`）。
2. 铰链/折叠姿态检测 `FoldingFeature` → `HingeState`（`Android/adaptive/HingeState.kt:7-22`、`Android/adaptive/RememberHingeState.kt:18-57`）。
3. Tabletop 半开布局：上半时间线、下半输入与待处理决策（`Android/ui/TabletopScreen.kt:33-159`）。
4. 三栏支撑面板（最近文件改动/diff）：`Android/ui/TabletopScreen.kt:134-159`、`Android/ui/AdaptiveRoot.kt:438-447`。
5. 项目页宽屏双栏（变更列表 + 文件内容）：`Android/ui/ProjectScreen.kt:113-136`。
6. 按窗口高度触发的 `dense` 紧凑列表（<560dp）：`Android/ui/AdaptiveRoot.kt:211`、`Android/ui/SessionListScreen.kt:365-369`。
7. 会话行选中底色 `AccentSoft`：`Android/ui/components/SessionRow.kt:42`。
8. 列表固定页脚（主机绿点、主机名、刷新）：`Android/ui/SessionListScreen.kt:347,392-415`。
9. 标题菜单内含 “连接详情” 入口：`Android/ui/SessionListChrome.kt:143`。
10. Material Ripple/IconButton/M3 组件体系与 `PullToRefreshBox`：`Android/ui/components/TopBar.kt:42-47`、`Android/ui/SessionListScreen.kt:262`。
11. 系统返回键 `BackHandler` 与 `enableOnBackInvokedCallback`：`Android/ui/AdaptiveRoot.kt:216,347`、`Manifest:20`。
12. WorkManager 周期后台同步：`Android/background/BackgroundSyncWorker.kt:32-40,140-152`。
13. Debug 启动 intent 测试钩子（配对码文件、强制中转、重置身份、添加设备）：`Android/MainActivity.kt:16-30`。
14. 自适应启动图标、圆形图标与多密度 PNG：`ARes/mipmap-anydpi-v26/ic_launcher*.xml`、`ARes/mipmap-*/ic_launcher*.png`。
15. 未使用的通用 `TopBar`/`TopBarIcon` 组件：`Android/ui/components/TopBar.kt:28-82`（全项目 0 调用）。
16. 项目页提供宽/窄两种正文实现 `WideProjectBody`/`CompactProjectBody`：`Android/ui/ProjectScreen.kt:120-136`。

## 6. Android 独有能力汇总

以下能力 iOS 当前没有对应实现（明细见各节末尾的小节）：

| # | 能力 | 证据 |
| --- | --- | --- |
| A1 | 折叠/平板自适应 `Compact / TwoPane / ThreePane / Tabletop`，断点 480/600/720/1100dp | `Android/adaptive/PaneLayoutPolicy.kt:9-84`、`Android/ui/AdaptiveRoot.kt:328-468` |
| A2 | 铰链姿态检测与半折叠吸附（Jetpack WindowManager `FoldingFeature`） | `Android/adaptive/HingeState.kt:7-22`、`Android/adaptive/RememberHingeState.kt:18-57` |
| A3 | Tabletop 半开：上半时间线、下半输入与待处理决策 | `Android/ui/TabletopScreen.kt:33-159` |
| A4 | 三栏支撑面板（最近 file_edit/diff） | `Android/ui/TabletopScreen.kt:134-159`、`Android/ui/AdaptiveRoot.kt:438-447` |
| A5 | 项目页宽屏双栏（240dp 改动列表 + 正文） | `Android/ui/ProjectScreen.kt:113-136` |
| A6 | 按可用高度 `dense` 紧凑列表（<560dp） | `Android/ui/AdaptiveRoot.kt:211`、`Android/ui/SessionListScreen.kt:265,368-390` |
| A7 | 列表常驻 host 页脚（绿点、主机名、刷新） | `Android/ui/SessionListScreen.kt:347,392-415` |
| A8 | 会话行选中底色 | `Android/ui/components/SessionRow.kt:42` |
| A9 | 首帧持久化快照（会话列表 + 每 host pending 计数） | `Android/background/SessionSnapshotCache.kt:29-73,137-145`、`Android/CmuxViewModel.kt:757-758,827-846` |
| A10 | WorkManager 后台同步（网络约束、4 台上限、20s/台、60s 总预算、失败重试） | `Android/background/BackgroundSyncWorker.kt:38-87,131-149` |
| A11 | 扫码页取景框、点按对焦、数码变焦、补光、前后摄像头回退 | `Android/ui/QrScannerScreen.kt:186-303,369-407,475-513,327-334` |
| A12 | “重置本机身份”完整流程 | `Android/CmuxViewModel.kt:478-509`、`Android/ui/PairingScreen.kt:296-307,322-338` |
| A13 | “已经配过对？重试已保存的连接” | `Android/ui/PairingScreen.kt:317-319`、`Android/ui/AdaptiveRoot.kt:247,569` |
| A14 | 连接详情 “传输”（直连/中转）与 “密钥”（Keystore/私有文件）卡片 | `Android/ui/ConnectionDetailScreen.kt:171-209` |
| A15 | 诊断日志脱敏与单条 512 字符截断 | `Android/data/Diagnostics.kt:17-21,28-38,63` |
| A16 | 新建会话首条消息 4096 UTF-8 字节硬上限与实时计数 | `Android/ui/StartSessionScreen.kt:51,178-189` |
| A17 | 跨 Mac 聚合 Feed / 聚合 pending 计数（同时是缺陷来源，见 F55） | `Android/CmuxViewModel.kt:993-1004` |
| A18 | 前台 live 之外 30s/15s 慢轮询兜底 | `Android/CmuxViewModel.kt:931-946` |
| A19 | Debug intent 钩子 `force_relay`/`reset_identity`/`add_device`/`relay_origin`/`enroll_code`/`enroll_file` | `Android/MainActivity.kt:16-31` |
| A20 | 独立 `Restoring` 启动态与 Failed 页 | `Android/ui/AdaptiveRoot.kt:239-275` |
| A21 | 计划审批五个快捷按钮；历史问题只读表单回显 | `Android/ui/FeedForms.kt:353-405,107-121` |
| A22 | Material 组件体系（Ripple、RadioButton/Checkbox 语义、PullToRefreshBox） | `Android/ui/components/Common.kt`、`Android/ui/SessionListScreen.kt:262` |

## 7. 建议实施顺序（待确认）

以下只是按“风险 → 用户可见 → 视觉/无障碍”的排序建议，未开始实施；等你确认清单和优先级后再动手。

### P0：正确性与安全（会造成错数据、丢消息或凭证风险）

1. **多 Mac 只有一条 live link、Feed 回答发到错误的 Mac**：`F55`、`F56`、`P57`、`F115`（`Android/CmuxViewModel.kt:905-912,1824-1830`）。先改成 per-host client + per-host feed。
2. **`connections.json` 明文保存 Mac 授权私钥**（`P100`）：改为 Keystore 包裹或 EncryptedFile。
3. **历史 Feed 事件仍可提交**（`F75`）、**busy 未传导致重复提交**（`F89`、`F106`）、**多问题/多选/自定义/跳过字段被丢弃**（`F83`、`F85`、`F86`、`F101`、`F105`）。
4. **图片-only 不能发送**（`C93`）、**`<pasted_content>` 未剥离**（`C1`）。
5. **待发送记录全局 key，跨会话串用**（`C145`），且结果未知时仍可再次发送（`C147`）。
6. **Android 无前后台/网络生命周期观察**（`P45`、`P55`、`P56`、`F117`），退后台不停读、回前台不重拨、换网不重连。
7. **错误码本地化覆盖不足**（`P108`、`P111`、`C151`）与硬编码中文/英文（`P13`、`P47`、`F142`、`D107`）。
8. **启动会话多 Mac 目标与幂等**（`F3`、`F22`、`F23`、`F28`、`F29`）：目前只认当前 Mac，重试会新开终端，且不校验 `accepted`。
9. **刷新/滚动锚点**（`C73`、`C78`、`C79`）：流式更新不跟随、上翻后跳位、发送后无 pinned prompt。

### P1：主要功能补齐（iOS 有、Android 缺）

1. 抽屉升级为完整会话树（搜索/排序/Mac/工作区分组/会话行）（`D57`、`42` 号条目）。
2. 列表：Mac 分段、组内缩进、行尾 chevron、相对时间自动刷新、状态筛选语义对齐（`D35`、`D36`、`D44`、`D56`、`1.2` 节 #10-#33）。
3. 对话：活动组独立页、工具卡完整页字段/状态/时间、图片挂到消息、图片草稿预览、语音草稿条、后台任务 Agent 对话与自动跟随（`C13`、`C35`、`C44`、`C102`、`C103`、`C118`、`C129`、`C134`）。
4. Markdown：表格列宽/对齐、代码块换行、标题语义（`C27`、`C29`、`C25`、`C21`）。
5. 新建会话：子目录浏览、相对路径、根目录下拉刷新、跨 Mac 目标、`outcome_unknown` 恢复（`F10`、`F11`、`F12`、`F19`、`F3`）。
6. 项目页：相对路径输入、Read/Diff/Changed files 三模式、整仓 diff、重命名 old → new（`F34`、`F35`、`F36`、`F41`）。
7. 连接：逐 Mac 连接详情、per-host 状态与 quiet 重试、网络恢复重拨、连接中胶囊条（`P53`、`P58`、`P76`、`D131`、`D132`）。
8. 配对：旧版 token 路径、取消向 Mac 发 cancel、轮询错误重试、等待页 clientID/倒计时（`P7`、`P31`、`P44`、`P46`）。
9. 后台同步：同步会话正文、退出后台时调度（`P93`、`P92`）。

### P2：视觉与交互细节

1. 统一页面容器（`WhitePage` 等价物）、标题居中、44dp 图标触控区（`D60`、`D100`、`D34`）。
2. 浮动按钮样式、玻璃/半透明头栏、按压反馈、导航转场与折叠动画（`D33`、`D38`、`D39`、`D49`、`D91`）。
3. 列表/Feed/项目间距与卡片样式对齐（`D35`、`F134`、`F135`、`F126`）。
4. 动态字体与字号体系（`D17`、`D19`、`D23`）。
5. 图标体系（SF Symbols → Material 的语义映射、chevron、状态图标）（`D42`、`D44`）。

### P3：可访问性、测试与本地化

1. `testTag` 体系与 Compose UI 测试（`D95`、`D121`、`D122`）。
2. `selected`/`heading`/`stateDescription` 语义与读屏分组（`D97`、`D98`、`D99`）。
3. 字符串键补齐（322 vs 275）、相对时间/日期/时长本地化（`D104`、`D105`、`D108`、`D109`、`D110`）。
4. 截图测试与真机验收（折叠姿态、Keystore、DeX、TalkBack）（`D124`）。
