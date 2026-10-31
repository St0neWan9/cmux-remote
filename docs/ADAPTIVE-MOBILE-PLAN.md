# Android 客户端与折叠屏 / 双栏（Duo）适配方案

状态：调研与设计提案，**未实现**。本文不表示任何平台、设备或商店验收已经通过。

- 日期：2026-10-29（第二版：加入 iPhone Duo / 小米 18 Fold 实机信息）
- 范围：现有 iOS 手机端的自适应改造（含 iPhone Duo）、Android 原生客户端的可行性、两端共享的协议合同与交付顺序
- 在线资料：本版通过 DeepSeek Search/Fetch 做了在线核对。Apple 官方规格与 Tech Talk 用于 iPhone Duo 的屏幕/尺寸/布局行为；小米 18 Fold 的发布信息来自多家媒体，具体参数仍以小米官方规格和真机为准。iOS 27.1 新 API 的精确签名以 Xcode 27.1 SDK 头文件和官方文档为准（第三方开发者文章只用于定位 API 名称）。仓库内事实均给出文件与行号。

---

## 0. 结论（先看这里）

| 决策 | 建议 |
| --- | --- |
| 当前执行顺序 | **Android / 小米 18 Fold 先行（2026-10-30 起）；iPhone Duo 暂缓，iOS 代码本轮不动**。先做 Android 工程、共用 `PaneLayoutPolicy`、小米 18 Fold 自适应壳（示例数据）；协议/配对在 A2 接入 |
| 后续 | Android 壳稳定后再做 iOS Duo 适配；两边继续共用同一套布局规则与断点，不共用 UI 代码 |
| Android UI | Kotlin + Jetpack Compose + Material 3，单 Activity；**不使用 Compose Multiplatform / Flutter / React Native 共享 UI** |
| 代码复用 | 不共享 UI，也不在第一步共享协议实现；先冻结**语言中立的协议合同 + 跨语言黄金向量 + 黑盒一致性测试**，Swift 与 Kotlin 各自实现 |
| “Duo” 定义 | 这里的 Duo 指 **iPhone Duo**：Apple 首款书本式折叠 iPhone（5.4" 外屏 + 7.6" 内屏，iOS 27.1）。产品上仍采用**双窗格 list-detail**；iPhone Duo 的内屏为 regular/regular，系统原生支持两栏/侧栏。Surface Duo 是另一台 Android 硬件，不是本文所指 |
| 断点 | `< 600pt/dp` 单栏；`600–719` 双栏（浏览器 240–280）；`720–839` 双栏（浏览器 320–400）；`>= 840` 双栏；`>= 1100` 且详情可用宽 `>= 480` 才出现第三栏 |
| 折叠屏策略 | 两端共用 `PaneLayoutPolicy`。Android：窗口宽度 + `FoldingFeature`；iOS 27.1：size class + `ArrangementView` / `NavigationSplitView`，必要时用 `onHingeChange` 与 `reservedRegions` 处理铰链/折痕。竖直折痕吸附分隔条，水平姿态进入 tabletop（输入区在下半屏） |
| 最大风险 | 协议细节跨语言漂移（canonical JSON、Base64、HPKE info、**证书 pin 是 DER 而非 SPKI**）、Android 后台限制、Bridge 的 `clientKind` 白名单目前只允许 `iphone` / `mac`；iPhone Duo 的 iOS 27.1 API 与 Xcode 27.1 工具链暂不在本轮 |
| 粗略估算 | 协议合同 1–2 人周；Android 核心 4–6；功能对齐 3–4；折叠屏打磨 2–3；发布 1–2；iOS Duo 4–5（暂缓）。当前 Android 先行阶段约 **10–15 人周**（估算，非承诺） |

**一句话**：把“自适应信息架构”设计一次，两端共用 `PaneLayoutPolicy` 和断点，但各自原生实现；当前先把 Android / 小米 18 Fold 的壳跑起来，iPhone Duo 不动。

**本轮只做第一刀**：A1（Android 工程 + 共用 `PaneLayoutPolicy` + 小米 18 Fold 自适应壳 + 示例数据 + 单元测试）。真机配对、协议、历史/发送在 A2 再接；不要因为壳能跑就声称已连接 Bridge。

---

## 1. 需求解读与边界

### 1.1 目标

- 在现有 iOS 客户端之外，提供一个功能对等的 Android 客户端。
- 支持书本式折叠屏（用户提到的“小米 18 Fold”，以及 Pixel Fold、Galaxy Z Fold、OnePlus Open 等）在**外屏 / 内屏 / 悬停 / 分屏 / 旋转**下的连续使用。
- iOS 同时支持 **iPhone Duo**：外屏单栏，内屏双栏（列表与对话并排），半开/Split View 连续可用，而不是把手机单栏硬拉宽。
- 先做 Android / 小米 18 Fold；iPhone Duo 的 iOS 改造暂缓，等 Android 壳稳定后再启动。

### 1.2 小米 18 Fold 的公开信息

小米 18 Fold 已于 **2026-09-07** 发布，9 月 10 日开售。媒体发布信息（以小米官方规格和真机为准）：

- 5.38" 外屏 + 7.58" 内屏，内外屏接近 √2:1 纸张比例；官方/媒体口径有 7.58" 与 7.6" 的差异，以真机 `WindowMetrics` 为准。
- 展开 163.8 × 117.8 mm，单边厚度 5.02 mm，折叠厚度 10.68 mm，重量 219 g。
- 首发玄戒 O3、澎湃 OS 4，最多六分屏 + 悬浮小窗，支持三指横滑、拖拽调整窗口比例；6000 mAh，67 W 有线 / 50 W 无线，10999 元起。

设计上仍按**书本式折叠屏**处理，具体参数在拿到真机后采集，不要写死型号：

- 外屏与内屏的 `WindowMetrics`（dp 宽高、密度、比例）；内屏按约 7" 级、√2 比例估算为 **约 700dp 宽**（横屏更宽），但必须实测。
- `FoldingFeature` 的 `bounds`、`orientation`、`state`、`isSeparating`、`occlusionType`；铰链区域宽度、折痕是否遮挡触控、悬停角度阈值。
- 澎湃 OS 4 的分屏 / 小窗 / PC 模式、应用连续性、后台限制、自动启动策略。
- 相机、Keystore（含 StrongBox）、mDNS 在该机型上的实际行为。

来源示例：PConline、IT之家、中国电子报、凤凰科技、9to5Google、Engadget 等对发布会的报道（2026-09-07/08）。

### 1.3 “Duo” = iPhone Duo

| 概念 | 结论 |
| --- | --- |
| **iPhone Duo** | Apple 首款书本式折叠 iPhone，2026-09-09 发布、10-23 开售；5.4" 外屏 + 7.6" 内屏，A20 Pro，iOS 27.1，国行 15999 元起 / 美国 1999 美元起 |
| 双窗格 / list-detail | 产品仍采用这个布局：窄屏单栏 + 抽屉，宽屏列表与对话并排。iPhone Duo 内屏原生 regular/regular，系统支持侧栏/两栏 |
| 微软 Surface Duo | 另一台 Android 硬件，不是本文的“Duo”；Android 端仍按 `FoldingFeature` 处理 |

iPhone Duo 的关键尺寸（Apple 官方规格）：

- 内屏 7.6"（7.58" 对角线）1878 × 2670 px，430 ppi；外屏 5.4"（5.36"）1398 × 2034 px，460 ppi。
- 展开 164.6 × 117.8 × 5.2 mm；闭合宽度 84.1 mm，厚度 11.3 mm；254 g。
- 按 3x 估算：内屏约 **626 × 890 pt**（竖屏）/ 890 × 626 pt（横屏），外屏约 **466 × 678 pt**。这是估算，必须用 `UITraitCollection` / `windowScene.screen` 实测；它意味着内屏竖屏宽度只有约 626pt，**双栏总阈值必须降到 600pt；720pt 只能作为浏览器宽度的分档，不能作为是否双栏的阈值**。
- 内屏不遵循 `UISupportedInterfaceOrientations`，布局必须看 size class，不能看方向；外屏仍像普通 iPhone（compact 宽 / regular 高）。
- 安全区在 Duo 上常常不对称；折叠/横向姿态时系统栏会变成侧边 rail（约 84pt），Split View 下窗口可能只有约 469pt 宽。

主要来源：

- Apple 技术规格：<https://support.apple.com/zh-cn/148588>
- Apple Tech Talk "Prepare your app for iPhone Duo"：<https://developer.apple.com/videos/play/tech-talks/111461/>
- iOS 27.1 新 API 整理：<https://dev.classmethod.jp/en/articles/ios27-1-iphone-duo-new-apis/>
- Expo iPhone Duo 适配指南：<https://expo.dev/blog/supporting-iphone-duo>
- 小米 18 Fold 发布报道：PConline、IT之家、中国电子报、凤凰科技、9to5Google、Engadget（2026-09-07/08）

### 1.4 不可越过的约束（来自 `AGENTS.md` 与 `docs/DESIGN.md`）

- 不修改、替换、重启、重签已安装的 cmux；不连接 provider API；不启动第二个 Agent 运行时；手机上不实现终端。
- Bridge 只暴露固定资源路由，不做通用 cmux RPC 代理；不做任意绝对路径读取。
- 授权模型不变：每台设备独立 Ed25519 身份、主人逐台批准、按工作区/能力授权、可单独撤销；扫码只承载短期登记窗口，不承载永久凭据。
- 凭证不进日志、fixture、Git；新错误必须有稳定 code，UI 只做本地化映射。
- Swift 6 并发检查、构造函数注入、有界请求/流、显式取消、一个文件一个主要类型继续适用于 iOS；Android 端以同样的纪律执行（协程、有界队列、显式取消、构造函数注入）。

---

## 2. 现状盘点

### 2.1 代码版图

| 部分 | 规模 | 说明 |
| --- | --- | --- |
| `Sources/CmuxRemoteCore` | 86 个 Swift 文件 | Sendable Codable DTO、JSON 值、纯策略、连接/Link 协议 |
| `Sources/CmuxRemoteClient` | 26 个 Swift 文件 | HTTPS 固定证书、WebSocket v3、发现、登记、传输 |
| `Sources/CmuxRemoteBridge` | 99 个 Swift 文件 | 本机 socket I/O、会话、转录、文件、TLS/WS 服务、中转 |
| `ios/Sources` | 120 个 Swift 文件，约 6,870 行 | SwiftUI 手机端 |
| `ios/UITests` | 23 个文件，约 1,286 行 | XCUITest + 隔离 fixture |
| 本地化 | 321 个键值对（文件 340 行） | `ios/Resources/en.lproj` 与 `zh-Hans.lproj` 键集一致 |
| iOS 构建 | Xcode 26，部署目标 iOS 18.0，Swift 6 | `ios/CmuxRemote.xcodeproj/project.pbxproj:337,353`。**iPhone Duo 的 iOS 27.1 API 需要 Xcode 27.1 + iOS 27.1 SDK**；可以保留 iOS 18 部署目标，用 `if #available(iOS 27.1, *)` 分支 |
| 设备族 | `TARGETED_DEVICE_FAMILY = "1,2"` | 已声明 iPhone + iPad；但 UI 是手机布局；iPhone Duo 已属于 iPhone 设备族，无需新增 family |
| 方向 | iPhone 仅竖屏；iPad 四向 | `ios/Info.plist:19-29` |

### 2.2 iOS 导航与状态

- 根视图在 `ios/Sources/CmuxRemoteApp.swift:15-19`：没有已批准 Mac 时显示 `PairingView`，否则显示 `SessionListView`。
- `AppModel` 是 `@State` 的 App 级模型（`CmuxRemoteApp.swift:7`），承载连接、会话、工作区、待处理项、侧栏开关等；**多窗口实际上已经开启**：生成器设置 `UIApplicationSceneManifest_Generation = YES`（`scripts/generate-ios-project.py:90`），产物里 `UIApplicationSupportsMultipleScenes = true`。三个 `.task`（`CmuxRemoteApp.swift:20,26,30`）会在每个场景各跑一遍，却操作同一个 `AppModel`。
- `SessionListView` 自己持有约 20 个 `@State`：搜索、过滤、排序、工作区、主机、会话选择、项目/Feed/连接页开关、启动会话目标等（`SessionListView.swift:7-32`）。这些是**每场景**状态；真正跨窗口共享的是 `AppModel.sidebarOpen` / `addingDevice`（`AppModel.swift:47,50`）以及缓存的 `ConversationModel` 草稿与读取状态（`AppModel.swift:435-442`、`ConversationModel.swift:65,267`）。
- 手机端是**抽屉 + 单栈 push**：
  - `SideDrawer` 包住列表（`SessionListView.swift:50`），抽屉宽度 `min(440, 屏幕宽 * 0.77)`（`SideDrawer.swift:15`）。
  - 会话用 `navigationDestination(isPresented:)` push（`SessionListView.swift:155`）；Feed 同理（`:157`）。
  - 连接详情、添加设备用 `fullScreenCover`（`:170-177`）。
- 每个入口创建原生 `NavigationStack`（`AppNavigationStack.swift:7-9`）；`InteractivePopInstaller` 替换系统 interactive pop 的 delegate，保留原生返回手势（`IOS-DESIGN-SYSTEM.md` 第 27-33 行）。
- 会话页是独立的 `ConversationView`：透明头部 + 浮动输入栏（`ConversationView.swift:68-117`），自己的推送目标（项目、Feed、图片、工具详情、运行时间，`:156-175`），以及针对滚动锚点的大量手工处理。

### 2.3 哪些东西可以直接复用

- **协议与模型**：`CmuxRemoteCore` 的 DTO、纯策略、签名/HPKE 实现是 Android 的“参考实现”，但需要先抽出语言中立合同。
- **视觉语言**：`MobileDesign.swift:5-13` 的 token（20pt 页边距、22pt 圆角、44pt 控件、蓝色强调）可以按 dp 复刻；白色画布 + 浮动表面 + 胶囊按钮是产品识别度。
- **页面结构**：配对、列表、会话、连接详情、项目、Feed、工具详情、图片、后台任务、待处理项，功能清单可直接变成 Android 的 parity matrix。
- **测试夹具**：`scripts/fixtures/PhoneUIFixture.swift` 用真实 Bridge 模块启动隔离后端；Android 可以复用同一套 HTTP/WS 合同，写一个 Kotlin/JVM 的 fake Bridge 或直接连隔离 fixture。
- **UI 标识符**：`sessions.sidebar`、`chat.composer`、`chat.send`、`sidebar.session.*` 等可以作为 Android `testTag` 的命名参考，便于两端跑同一组验收脚本。

### 2.4 缺口

| 缺口 | 证据 | 影响 |
| --- | --- | --- |
| 没有任何尺寸类 / 宽屏分支 | `grep horizontalSizeClass / GeometryReader` 只命中图片、抽屉、滚动测量 | iPad / iPhone Duo / 折叠屏现在只是“放大的手机” |
| 没有 iPhone Duo 姿态/铰链处理 | 代码没有 `onHingeChange`、`reservedRegions`、`ArrangementView`、`toolbarVerticalEdge` | 折痕/铰链两侧内容、侧边 rail、非对称安全区、Split View 会错位 |
| Xcode 26 不能编译 iOS 27.1 API | `README`/构建脚本当前是 Xcode 26 | 需要 Xcode 27.1 + Device Hub 做 Duo 验收；旧工具链只能跑兼容布局 |
| 选择状态在视图里 | `SessionListView.swift:7-32` | 无法在持久侧栏与详情之间共享选择；多窗口共享的是 `AppModel.sidebarOpen` / `addingDevice` 与缓存 `ConversationModel` 的草稿/读取状态，选择本身是每场景 `@State` |
| iPhone 仅竖屏 | `Info.plist:19-22` | iPhone 横屏 / 折叠外屏旋转无法进入双栏 |
| 抽屉数学是手机专用 | `SideDrawer.swift:15` | 宽屏抽屉过宽 / 阴影面板比例失真 |
| 多窗口已开启但共享模型 | 生成器 `UIApplicationSceneManifest_Generation = YES`（`scripts/generate-ios-project.py:90`）→ 产物 `UIApplicationSupportsMultipleScenes = true`；`AppModel` 为 App 级 `@State` | 两个窗口会共享 `sidebarOpen` / `addingDevice`；同一会话的 `ConversationModel` 草稿与 `suspendReads` 会被两个窗口互相影响 |
| 没有 Android 工程 | 仓库无 `android/`、无 Gradle / Kotlin 源 | 从零开始 |
| 本机 Android 工具链不全 | 有 `adb` / `sdkmanager` / `emulator`、platforms 34–36、android-35 arm64 镜像；无 Gradle、`kotlinc`、Android Studio | 需要先补工具链；不能把“能跑 adb”当成能构建 |
| Bridge 只接受两种 client kind | `ConnectionAuthority.swift:204`：`["iphone", "mac"]` | Android 以 `android` 登记会被拒；必须改 Bridge |
| Mac 设备图标只分 iPhone / 桌面 | `mac/Companion/DevicesSettingsView.swift:100,105` | Android 会显示成桌面电脑 |
| 没有机器可读的协议 schema / 黄金向量 | `docs/API.md`、`docs/CONNECTION-V2.md` 是叙述性文档 | Kotlin 实现只能“读 Swift 猜细节”，极易漂移 |

---

## 3. 跨端策略对比

### 3.1 候选方案

| 方案 | 做法 | 主要优点 | 主要代价 |
| --- | --- | --- | --- |
| **A. 原生双端 + 共享协议合同** | SwiftUI 保持；Android 用 Kotlin/Compose 重写 UI 与协议；共享 spec、JSON 向量、黑盒一致性测试 | UI/手势/折叠屏最原生；安全边界各自用平台最佳实践；iOS 无需重构 | 两份 UI、两份协议实现；需要严格的合同测试防漂移 |
| B. KMP 共享 core | 把协议/加密/模型抽成 Kotlin Multiplatform 模块，Swift 通过 KMP 调用 | 协议只实现一次；长期漂移最小 | 要把现有 Swift Core/Client 迁到 Kotlin 或维护两套；iOS 构建引入 Gradle/KMP；Swift 6 并发与 Sendable 边界复杂 |
| C. Compose Multiplatform | Android + iOS 共用 Compose UI | 一套 UI | 要替换 6.8k 行高度打磨的 SwiftUI；滚动锚点、原生返回、Keychain、后台、VoiceOver 都要重做；iOS 观感风险高 |
| D. Flutter / React Native | 一套跨端 UI | 开发快、生态大 | 与 C 类似，且加密/证书固定/折叠屏 API 需要大量插件；安全与商店风险更高 |
| E. Rust/C 协议核心 | 协议/加密用 Rust，两端 native UI 通过 FFI 调用 | 协议内核唯一、可审计 | FFI、构建链、团队熟悉度；现有 Swift 实现要重写或长期并存；首版收益不足以抵消成本 |

### 3.2 加权评分

权重按本项目现状设定：复用现有代码 15、安全/协议正确 15、UI/手势保真 15、折叠屏/自适应 15、交付速度 10、长期漂移 10、iOS 改动风险 10、CI/工具链 5、商店/开源 5。分数 1–5，越高越好。

| 方案 | 复用 | 安全 | UI | 自适应 | 速度 | 漂移 | iOS 风险 | CI | 商店 | 加权分 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| **A 原生双端 + 合同** | 3 | 5 | 5 | 5 | 3 | 3 | 5 | 4 | 5 | **85 / 100** |
| B KMP core | 4 | 5 | 5 | 5 | 2 | 5 | 2 | 3 | 5 | 83 / 100 |
| E Rust core | 3 | 5 | 5 | 5 | 2 | 5 | 2 | 2 | 5 | 79 / 100 |
| C Compose Multiplatform | 1 | 4 | 2 | 3 | 3 | 3 | 1 | 3 | 4 | 51 / 100 |
| D Flutter / RN | 1 | 3 | 2 | 3 | 2 | 3 | 2 | 4 | 4 | 49 / 100 |

**推荐 A**。B 的纸面分数接近，但它隐含一次高风险重构：要么把现有 Swift Core/Client 迁到 Kotlin（iOS 端重新验证签名、HPKE、固定证书、取消语义），要么维持两套协议实现——那正是 A 已经在做的事。E 更适合作为未来的“协议内核加固”选项，而不是首版路径。

**什么时候重新考虑 B/E**：

- Android 上线后，两端协议实现出现两次以上同源 bug；或
- 出现第三个客户端（Web / 桌面 / 可穿戴）；或
- 需要把协议交给独立安全审计，且希望只有一份可审计实现。

### 3.3 推荐仓库布局

```text
android/                         # 新 Gradle 工程，独立构建
  settings.gradle.kts
  gradle/libs.versions.toml
  app/                           # 单 Activity + AppContainer + AdaptiveHost
  core/protocol/                 # 纯 Kotlin/JVM：DTO、canonical JSON、签名、错误码
  core/crypto/                   # Tink Ed25519 / HPKE、Keystore 包装（不依赖 OkHttp/Android UI）
  core/transport/                # OkHttp HTTPS + WebSocket v3、固定证书 TrustManager、选路、分块、relay directory
  core/discovery/                # NsdManager、QR 载荷解析、DiscoverySource 接口（不含 HTTP）
  core/data/                     # DataStore、MutationLedger、ConversationCache、repository
  core/navigation/               # 跨 feature 的目的地接口（不依赖 feature 实现）
  core/ui/                       # 设计 token、通用组件、图片加载
  core/testing/                  # fake Bridge、fake DiscoverySource、黄金向量 runner 的 JVM 入口
  feature/pairing/
  feature/sessions/
  feature/conversation/
  feature/project/
  feature/feed/
  feature/settings/
  spec/                          # 语言中立合同与黄金向量（与 Android 工程分离）
    README.md
    canonical-json.md
    crypto.md
    routes.md
    errors.md
    schema/*.json
    vectors/*.json
  conformance/                   # 黑盒一致性测试（Swift + Kotlin 都能跑）
```

- 依赖边：`app → feature/* → core/{ui,navigation,data,transport,discovery,crypto,protocol}`；`core/transport → core/{protocol,crypto}`；`core/data → core/{protocol,transport,discovery}`；`core/discovery` 不依赖 `core/transport`。**`core/crypto` 不依赖 OkHttp**；固定证书的 `X509TrustManager` 放在 `core/transport`。
- feature 之间不直接依赖实现；`conversation → project/feed/settings` 的跳转通过 `core/navigation` 接口。
- `app` 里的 `AppContainer` 提供构造函数注入；Compose 用 `ViewModelProvider.Factory` + `CreationExtras` 创建 ViewModel，不把 `AppContainer` 塞进全局单例。
- `android/core/protocol` 不依赖 Android SDK，可在 JVM 上跑单元测试与一致性测试。
- `spec/` 不是代码生成器；首版手写 schema 和向量，避免引入一套需要维护的代码生成链。若两端 DTO 开始漂移，再考虑从 schema 生成 Kotlin/Swift 模型。
- `conformance/` 只启动**隔离 Bridge + fixture**，不连接真实 cmux / provider；与现有 `scripts/fixtures/PhoneUIFixture.swift` 的纪律一致。

---

## 4. 统一的自适应信息架构

这一节是两端共同的“设计源”。先定信息架构与断点，再分别映射到 SwiftUI / Compose。

### 4.0 共用布局规则（两端唯一版本）

两端共用**同一套布局决策**，但不共用 UI 代码。把它实现成一个纯函数 `PaneLayoutPolicy`，输入窗口和铰链信息，输出窗格：

```text
输入:
  widthDp, heightDp
  hinge: none | vertical(separating, bounds) | horizontal(separating, bounds)
  hingeState: flat | halfOpened

输出:
  Compact
  TwoPane(browserWidthDp, detailWidthDp, gapDp)
  ThreePane(browserWidthDp, detailWidthDp, supportingWidthDp, gapDp)
  Tabletop(topHeightDp, bottomHeightDp, gapDp)
```

固定规则：

| 条件 | 结果 |
| --- | --- |
| `min(width, height) < 600` | `Compact`：单栏 + 抽屉；会话 push。普通手机横屏（914×411）也走这里 |
| `min(width, height) >= 600` 且 `width >= 600` | 进入双栏判断；`width` 决定各栏宽度 |
| `600 <= width < 720` | `TwoPane`；`browser = clamp(width × 0.4, 240, 280)`；`detail = width - browser - gap`，且 `detail >= 360` |
| `720 <= width < 840` | `TwoPane`；`browser = clamp(width × 0.4, 320, 400)`；`detail >= 360` |
| `840 <= width < 1100` | `TwoPane`；浏览器按 320–400，对话获得剩余宽度 |
| `width >= 1100` 且 `width - browser - 360 >= 480` | `ThreePane`；第三栏 320–420，优先放项目/Feed/工具详情/图片 |
| 竖直分离铰链 | 分隔条吸附 `hinge.bounds`；`gap = hinge.width`；两侧都不小于 360/240；放不下就回落 `Compact` |
| 水平分离铰链 + halfOpened | `Tabletop`：上时间线、下审批/输入；`gap = hinge.height`；内容不跨折痕 |
| 其他 | 忽略 fold 信息，按宽度计算 |

**为什么用最短边而不是当前宽度**：普通手机横屏的宽度可以到 914dp，但它的最短边只有 411dp，仍然应该保持单栏；折叠屏内屏最短边约 673dp，才进入双栏。这样不用写机型分支，也不会让手机横屏误变成双栏。

**优先级：先普通手机，后折叠屏。**

1. 先用普通直板手机（360–430dp 宽）把 `Compact` 单栏、抽屉、push、滚动、输入栏跑通；这是 Android 首版必须满足的基线。
2. 再用 600–839dp 的折叠屏内屏验证 `TwoPane`；小米 18 Fold 内屏约 700dp，应得到约 280 / 420 的两栏。
3. 最后验证外屏（`Compact`）、半开（`Tabletop`）、系统六分屏/小窗里的窄窗（回落 `Compact`）。

平台适配只负责把系统信息喂给同一个 policy：

| 信息 | Android | iOS 27.1 |
| --- | --- | --- |
| 窗口宽高 | `BoxWithConstraints` / `WindowMetrics` | `GeometryReader` / `windowScene.screen` |
| 窗口类 | `WindowSizeClass` + 宽度 | size class + 宽度 |
| 折痕/铰链 | `FoldingFeature.bounds/orientation/state/isSeparating` | `reservedRegions(kind: .division)` + `onHingeChange` |
| 两栏壳 | 自绘 `Row` + `PaneLayoutPolicy` | `ArrangementView` / `NavigationSplitView`（或 fallback `HStack`） |
| 安全区/系统栏 | `WindowInsets.safeDrawing` | `safeAreaInsets` / `toolbarVerticalEdge` |

**不是设备专用布局**：不写“小米分支”“Duo 分支”。小米 18 Fold、iPhone Duo、iPad、普通手机、Split View 都走同一张表；差异只来自窗口宽度和 hinge 输入。

### 4.1 断点与窗口类

| 窗口类 | 宽度（dp/pt） | 典型设备 | 产品布局 |
| --- | --- | --- | --- |
| Compact | 最短边 `< 600` | 普通手机竖屏/横屏（如 411×914、914×411）、折叠屏外屏、iPad 窄分屏 / Stage Manager 窄窗、iPhone Duo Split View 单窗（约 469pt） | 单栏 + 抽屉；对话 push |
| Medium | `600–839` | iPhone Duo 内屏竖屏（约 626pt）、折叠屏内屏（约 7–8 英寸）、iPad 1/2 分屏、小平板 | 双栏：浏览器 240–400（600–719 取 240–280；720+ 取 320–400），详情至少 360 |
| Expanded | `>= 840` | iPhone Duo 内屏横屏（约 890pt）、iPad 全屏、横向大折叠、桌面 / freeform | 双栏；`>= 1100` 且详情可用宽 `>= 480` 时可加第三栏“支持面板” |
| Supporting | `>= 1100` 且 `总宽 - 浏览器 - 支持面板 >= 480` | iPad Pro 横屏、桌面窗口 | 浏览器 + 对话 + 支持面板（项目 / Feed / 工具详情 / 图片） |

**产品阈值**：双栏条件是“总宽 `>= 600` 且详情 `>= 360`”，浏览器宽度取 `clamp(总宽 × 0.4, 240, 400)`。iPhone Duo 内屏竖屏约 626pt，正好落进双栏；它的 Split View 单窗约 469pt，落回单栏。平台窗口类只是输入，不是布局结论。

说明：

- 这里的宽度是**窗口可用宽度**，不是屏幕物理宽度。折叠屏外屏即使物理尺寸不小，只要可用宽度 `< 600` 就按 Compact 处理。
- iOS 没有 Material 的 medium/expanded 枚举；用可用宽度 + `horizontalSizeClass` 组合判断。**iPhone Duo 内屏是 regular/regular，外屏是 compact 宽 / regular 高；内屏不遵循 `UISupportedInterfaceOrientations`，必须用 size class 而不是方向。**
- Android 使用 `WindowSizeClass`（`androidx.window.core.layout` 或 Material 3 Adaptive 的 `WindowAdaptiveInfo`），但**不要只看设备类型**；同一台折叠屏在展开/合上时窗口类会变。
- 断点是产品决策，不是平台默认值；后续可以根据真机数据微调，但不要为单个机型写死。

### 4.2 三种规范布局

**Compact（现状保持）**

```text
┌─────────────────────────────┐
│  ☰       标题 / 菜单     🔍 │  ← 浮动头部
│  [Mac 标签] [工作区胶囊]    │
│  [待处理提醒]               │
│  [过滤: 全部/运行中/...]    │
│                             │
│  工作区分组                 │
│    ├ 会话 1                 │
│    ├ 会话 2                 │
│                             │
│  [Mac 连接状态]             │
│  [+ 添加 Mac]               │
└─────────────────────────────┘
   ☰ → 左侧抽屉（工作区/会话）
   点会话 → push 会话页
```

**Medium（600–1099：双栏，浏览器可折叠）**

```text
┌───────────────┬─────────────────────────────┐
│ 浏览器        │ 详情                        │
│               │                             │
│ Macs / 工作区 │ 会话头部（标题/模型/菜单）  │
│ 搜索          │                             │
│ 会话列表      │ 消息时间线                  │
│ 待处理提醒    │                             │
│ 连接状态      │                             │
│               │ [浮动输入栏]                │
└───────────────┴─────────────────────────────┘
  浏览器宽 240–400（600–719 取 240–280；720+ 取 320–400）
  详情最小 360；浏览器可折叠为 0，详情占满
```

**支持面板布局（>= 1100）**

```text
┌──────────┬──────────────────────┬──────────────┐
│ 浏览器   │ 对话                 │ 支持面板     │
│ 340–400  │ 自适应，正文最大 900 │ 320–420      │
│          │                      │ 项目 / Feed  │
│          │ 时间线 + 输入栏      │ 工具详情/图片│
└──────────┴──────────────────────┴──────────────┘
  >= 1100 且对话可用宽 >= 480 才显示第三栏；否则只有两栏
  支持面板由项目/Feed/工具详情入口打开，可关闭
```

**为什么不在 600–1099 就上三栏**：600 减去浏览器 240 后只剩 360 给对话；产品层级也只有一个“浏览器”（Mac → 工作区 → 会话），没必要拆成两级常驻栏。三栏只在 `>= 1100` 且详情可用宽 `>= 480` 时出现。

### 4.3 Duo / 折叠屏规则

| 形态 | 判断 | 布局 |
| --- | --- | --- |
| 竖直分离铰链（书本式展开） | `FoldingFeature.orientation == VERTICAL && isSeparating` | 双栏分隔条**吸附到铰链 bounds**；内容不跨过铰链；浏览器宽度取铰链左边界，详情取右边界；若一侧 `< 320`，改用单栏并优先放在较宽一侧 |
| 水平分离铰链（tabletop / 半折） | `orientation == HORIZONTAL && isSeparating` | 会话单栏：时间线在上半屏，输入栏 / 待处理操作在下半屏；列表仍可按宽度决定是否双栏；不把消息跨铰链绘制 |
| 半开但非分离（折痕/姿态） | `state == HALF_OPENED && !isSeparating` | 布局按宽度正常计算；避免把关键按钮、输入框放在折痕附近；可用铰链 bounds 做内边距 |
| 无铰链大屏（iPad / 平板） | 无 `FoldingFeature` | 按 4.1 的宽度断点；不加假铰链、不画折痕 |
| 外屏 / 内屏切换 | 窗口宽度与 `WindowLayoutInfo` 变化 | 保持选择、滚动位置、草稿、展开卡片；只重排布局，不重建 `ConversationModel` / ViewModel |

**iOS / iPhone Duo（iOS 27.1）**：Apple 已经提供折叠相关的布局 API，不能再按“iOS 没有铰链 API”设计。精确签名以 Xcode 27.1 SDK 头文件/官方文档为准：

- `ArrangementView`（SwiftUI；UIKit 有对应物）提供 primary/secondary 两个视图，`.split` 在展开/半开时沿折痕分栏，`.overlay` 叠加；系统负责分栏和折叠重排。适合把“浏览器 / 对话”直接交给系统。
- `NavigationSplitView` / `UISplitViewController` 在 Duo 上完全自适应：折叠时收成一栏，展开时并排，并自动避开折痕。Apple 的 Tech Talk 明确推荐标准导航。
- `onHingeChange { old, new in ... }` 给出 `hinge.status`（`.closed` / `.partiallyOpen` / `.fullyOpen`）与角度，用于 tabletop/悬停；`reservedRegions(kind: .division)` 给出折痕区域，`.occlusion` 给出摄像头/灵动岛等遮挡区域。
- 系统栏在折叠/横向姿态会变成侧边 rail（约 84pt）；用 `toolbarVerticalEdge` 读取 rail 在哪一侧，用 `toolbarVerticalBehavior` / `axisBehavior` 决定是否采用垂直栏。不要假设左右 inset 对称。
- Split View 下窗口可能只有约 469pt 宽；必须按窗口宽度回落到单栏。
- 内屏不遵循 `UISupportedInterfaceOrientations`，布局只看 size class；外屏仍是 compact 宽 / regular 高。
- 不要引用 `UIScreen.main`：双屏设备上它是歧义的；用 `windowScene.screen`、`traitCollection.displayScale` 或场景 bounds。

**iOS 的降级路径**：如果暂时不升到 iOS 27.1 SDK，或要支持 iOS 18–27.0，保留自绘 `HStack` 双栏作为 fallback；在 27.1 上优先用 `ArrangementView` / `NavigationSplitView`。两条路径共享同一套 `PaneLayoutPolicy` 和状态，不能让布局分支决定数据状态。

**Surface Duo**：运行 Android，通过 `FoldingFeature` 的双屏边界实现同样的“竖直吸附”规则；不要把 Surface Duo 当成 iPhone Duo。

### 4.4 状态与导航

把状态拆成四层，两端同名同义：

| 状态 | 内容 | 生命周期 |
| --- | --- | --- |
| `ConnectionState` | 每个 Mac 的 `RemoteClient`、授权、链路状态、待处理项 | 应用级（跨场景共享） |
| `BrowserState` | 主机过滤、工作区过滤、搜索、排序、分组折叠、滚动位置 | 每个窗口 / 场景 |
| `DetailState` | 当前选中的 `HostedSession` 身份、详情内导航栈（会话 → 项目 / Feed / 图片 / 工具详情 / 运行时间）、每个会话的模型缓存 | 每个窗口 / 场景 |
| `ShellState` | 当前窗口类、浏览器是否折叠、支持面板内容、抽屉是否打开 | 每个窗口 / 场景 |

关键规则：

1. **会话身份是 `hostID + session.id`**，不是列表下标。列表刷新、切换排序、折叠/展开都不能改变当前选择。
2. **选择提升到 Shell**，不再由 `SessionListView` 的局部 `@State` 独占。Compact 下选择会话仍然 push；Medium/Expanded 下选择会话只更新详情栏，不 push 一个盖住列表的页面。
3. **每个窗口一份 `BrowserState` / `DetailState` / `ShellState`**；连接与授权共享。Android 用 `ViewModel`（Activity 级）或 `rememberSaveable`。iOS 注意：`@AppStorage` / `@SceneStorage` 是 `DynamicProperty`，不能塞进 `@Observable` 模型；持久化留在 Shell/View 层，用 `Binding` 或注入的读写闭包。`sortMode` 建议保持全局（`@AppStorage`），折叠状态保持每场景（`@SceneStorage`），并保留现有 `"\n"` 连接格式，避免升级丢状态。
4. **折叠/旋转不重建会话模型**：模型按 `hostID + session.id` 缓存在应用级（与现有 `AppModel.conversationModels` 一致），布局变化只改变容器。但同一会话的 `ConversationModel` 不应被两个窗口同时当作“自己的”草稿/读取所有者；多窗口时草稿按窗口分开，或明确只允许一个窗口编辑。
5. **列表刷新不自动切换会话**：选中的会话消失时，详情栏显示“会话已结束/不可用”，保留返回列表的入口，不静默跳到另一个会话。
6. **详情内导航栈独立**：在宽屏下，项目 / Feed / 工具详情 / 图片优先进入支持面板；没有支持面板时 push 在详情栏内。Compact 仍走现有 push。
7. **返回语义**：
   - Compact：详情 push → 返回列表；列表根 → 关闭抽屉 / 退出。
   - Medium/Expanded：详情内 push → 返回对话；对话根 → 焦点回到浏览器（不退出应用）；浏览器根 → 退出。
   - Android 必须支持 predictive back：在详情栏返回时给出“回到列表”的预览，不要直接退出。
8. **深链**（如果后续增加）：只携带 host 身份与会话 ID，不携带凭据；先校验已保存授权，再选中；未知/已撤销的会话显示错误，不自动打开。
9. **多窗口**：iOS **现在就支持多场景**（生成器产物 `UIApplicationSupportsMultipleScenes = true`），但共享 App 级 `AppModel`。P1 必须二选一：在生成器显式设 `INFOPLIST_KEY_UIApplicationSupportsMultipleScenes = NO` 先关掉；或把 `sidebarOpen` / `addingDevice` / 草稿 / 读取所有权移入场景状态，并把 `CmuxRemoteApp` 的三个 `.task` 改成单所有者。P3 再正式支持 Stage Manager 多窗口 / Android 多实例。多窗口共享连接，但选择、滚动、草稿按窗口隔离。
10. **窗口类切换的迁移**：Compact→双栏时，如果当前正 push 会话，关闭 push 并把会话设为详情选择；双栏→Compact 时，如果已有选择，push 一次该会话。两端都要有这条测试，避免旋转后回到空白页或重复 push。

### 4.5 折叠 / 尺寸变化的连续性清单

在真机上逐项验收：

- [ ] 会话运行中折叠/展开：时间线不跳到底部，除非用户本来就在底部。
- [ ] 输入框有草稿时折叠/展开：草稿、光标、键盘状态不丢（前提是状态已提升到 Shell，不是视图分支私有 `@State`）。
- [ ] 展开的 activity group / 工具卡片保持展开或按规则收起，不因重排而闪回。
- [ ] 图片预览 / 项目页 / Feed 在支持面板与 push 之间切换时，返回路径正确。
- [ ] 抽屉只在 Compact 出现；从 Compact 拖到 Medium 时抽屉关闭，浏览器常驻。
- [ ] 旋转 / 分屏拖动过程中不出现内容绘制在铰链下。
- [ ] 键盘弹出时，输入栏不被铰链或系统栏遮挡；tabletop 下输入栏在下半屏。
- [ ] 多窗口下两个窗口的选中会话互不影响。
- [ ] Compact→双栏→Compact 往返后，当前会话仍被选中且只 push 一次；不出现空白详情或重复返回栈。

### 4.6 交互与可访问性

- **抽屉只在 Compact**：Medium/Expanded 用常驻浏览器 + 折叠按钮；不要把 `SideDrawer` 的 77% 宽度数学带到大屏。
- **边缘返回手势**：Compact 保留现有左缘返回；双栏下边缘手势只作用于详情栈，不与浏览器滚动/选择冲突。
- **拖放**（可选，P4）：把会话行拖到详情栏打开；把图片从其他应用拖入输入栏作为附件。首版可以不做，但布局要为拖放留出命中区域。
- **键盘**：iPad / Android 外接键盘至少支持：`Esc` 返回、`⌘/Ctrl+F` 搜索、`⌘/Ctrl+Enter` 发送、`⌘/Ctrl+1/2/3` 切换栏焦点。快捷键不能绕过授权检查。
- **指针 / 触控板**：按钮 hover 态、44×44pt / 48×48dp 命中区、滚动条可见性。
- **读屏**：浏览器与详情栏的焦点顺序、标题 heading、运行中状态的 live region；铰链两侧内容不要被读屏当成连续段落。
- **字体缩放**：动态字体 / Android fontScale 放大到 200% 时，按钮不截断、卡片不被固定高度裁切；长路径、指纹、设备名允许换行。
- **本地化**：英文 / 简体中文键集一致；新增布局相关文案（如“收起列表”“支持面板”）必须同时进入两端资源。

### 4.7 组件映射

| 组件 | Compact | Medium | Expanded | SwiftUI | Compose |
| --- | --- | --- | --- | --- | --- |
| 根壳 | 单栏 + 抽屉 | 双栏 | 双栏 + 支持面板 | `AdaptiveShell` 自绘（`HStack`） | `AdaptiveScaffold` 自绘（`Row` + `PaneLayoutPolicy`） |
| 浏览器 | 抽屉内容 | 常驻左栏 | 常驻左栏 | `SessionBrowserPane`（从 `SessionSidebarView` + 列表抽取） | `SessionBrowserPane` |
| 会话列表 | 主页 | 浏览器下半部 | 浏览器下半部 | 复用 `SessionListView` 的行/分组子视图 | 复用行组件 |
| 会话 | push 全屏 | 右栏 | 中栏 | `ConversationView` | `ConversationScreen` |
| 输入栏 | 底部浮动 | 右栏底部 | 中栏底部 | `ChatComposer` | `ChatComposer` |
| 项目 / Feed / 图片 / 工具详情 | push | 右栏 push 或支持面板 | 支持面板 | 现有页面 + `SupportingPane` | 对应 screen + `SupportingPane` |
| 连接详情 | `fullScreenCover` | 支持面板 / sheet | 支持面板 / sheet | `ConnectionDetailView` | `ConnectionScreen` |
| 配对 | 全屏 | 全屏 / sheet | 全屏 / sheet | `PairingView` | `PairingScreen` |
| 抽屉 | 现有 `SideDrawer` | 不用 | 不用 | `SideDrawer` | `ModalNavigationDrawer` |
| 设计 token | 20pt / 22pt / 44pt | 同左 | 同左 + 最大内容宽 | `MobileDesign` | `MobileTheme`（dp/sp） |

### 4.8 视觉 token 适配

保持“全白画布 + 浮动表面”，只增加宽屏约束：

| token | Compact | Medium / Expanded |
| --- | --- | --- |
| 页边距 | 20 | 24–32（浏览器内 20） |
| 卡片圆角 | 22 | 22 |
| 控件高度 | 44 | 44（Android 48 命中区） |
| 对话正文最大宽 | 无（占满） | 680–900，居中 |
| 输入栏最大宽 | 无 | 与正文同宽 |
| 浏览器宽 | 抽屉 `min(440, 77%)` | 320–400，可折叠 |
| 支持面板宽 | 无 | 320–420 |
| 卡片阴影 | 现有 | 保持；不要在深色/大屏上加灰色底 |

---

## 5. iOS 改造方案（P1）

### 5.1 原则

- **Compact 行为不变**：现有 iPhone 外屏/竖屏的抽屉、push、返回手势、滚动锚点全部保留；自适应只是“多一个壳”，不是重写会话页。
- **先抽状态，再拆视图**：把 `SessionListView` 里的选择/过滤/搜索状态抽成 `SessionBrowserModel`，否则双栏无法共享选择。
- **P1 先做系统 API spike，再决定壳**：iPhone Duo / iOS 27.1 提供了 `ArrangementView` 和自适应的 `NavigationSplitView`，Apple 的 Tech Talk 推荐标准导航。现有页面隐藏导航栏、自绘浮动头部，和系统侧栏/垂直工具栏可能冲突；所以 P1 用同一组视图分别试：
  1. `ArrangementView(primary: 浏览器, secondary: 对话).arrangementViewStyle(.split)`；
  2. `NavigationSplitView { 浏览器 } detail: { 对话 }`；
  3. 自绘 `HStack` + 每栏 `NavigationStack`（iOS 18–27.0 fallback，或系统壳无法保留浮动头部时）。
  用 Device Hub 的折叠/旋转/Split View 姿态对比后选定一个，不要让三种壳并存到生产。**`HSplitView` 是 macOS-only，iOS 不能用**。
- **铰链/折痕用 iOS 27.1 API，不再假设没有**：`onHingeChange` 读 status/angle，`reservedRegions(kind: .division/.occlusion)` 读折痕/摄像头区域；`ArrangementView` 默认沿折痕分栏。自绘壳必须自己避开 `reservedRegions`，不能把内容画到折痕上。
- **侧边 rail 与非对称安全区**：折叠/横向姿态系统栏会变成约 84pt 的侧边 rail；用 `toolbarVerticalEdge` 读取在哪一侧，内容容器按左右 inset 分别处理。不要用 `UIScreen.main`。
- **工具链**：iPhone Duo 的 iOS 27.1 API 需要 **Xcode 27.1 + iOS 27.1 SDK + Device Hub**；当前仓库是 Xcode 26。可以保留 iOS 18 部署目标，用 `if #available(iOS 27.1, *)` 分支；旧系统走 fallback。
- **多窗口已经开启，P1 必须显式处理**：生成器产物 `UIApplicationSupportsMultipleScenes = true`。要么在 `scripts/generate-ios-project.py` 里显式关掉，要么把场景状态与任务所有权拆开；不能假设“第一版只有一个窗口”。iPhone Duo 的 Split View 是系统多任务，不是多场景，但仍会改变窗口宽度。

### 5.2 新增 / 修改的文件

| 文件 | 作用 |
| --- | --- |
| `ios/Sources/MobileWindowClass.swift` | 由可用宽度 + size class 计算 `.compact/.medium/.expanded`；纯值类型，可单测 |
| `ios/Sources/AdaptiveShell.swift` | 根壳：根据窗口类选择 Compact 单栏或双栏；持有 `BrowserState` / `DetailState` / `ShellState` |
| `ios/Sources/SessionBrowserModel.swift` | 从 `SessionListView` 抽出的 `@Observable`：query/filter/sort/workspace/host/collapsed/selection |
| `ios/Sources/SessionBrowserPane.swift` | 浏览器栏：Mac 标签、待处理提醒、过滤、分组列表、底部连接状态；复用现有行视图 |
| `ios/Sources/ConversationPane.swift` | 详情栏容器：空状态、`ConversationView`、详情内导航栈 |
| `ios/Sources/SupportingPane.swift` | 第三栏：项目 / Feed / 图片 / 工具详情 / 连接详情；`>= 1100` 且详情可用宽 `>= 480` 才出现 |
| `ios/Sources/AdaptiveSplitView.swift` | 自绘双栏 / 三栏 + 分隔条 + 折叠动画（fallback；不要用 macOS 的 `HSplitView`） |
| `ios/Sources/DuoLayoutSupport.swift` | iOS 27.1 适配层：`ArrangementView` / `NavigationSplitView` 选择、`onHingeChange`、`reservedRegions`、`toolbarVerticalEdge`、availability 分支；纯适配，不承载业务状态 |
| 修改 `CmuxRemoteApp.swift` | 根视图从 `SessionListView` 改为 `AdaptiveShell`；`AppModel` 仍在 App 级；三个 `.task` 的所有权要明确 |
| 修改 `SessionListView.swift` | 保留 Compact 路径；把状态迁到 `SessionBrowserModel`；宽屏时由 Shell 使用浏览器栏 |
| 修改 `ConversationView.swift` | 宽屏隐藏 `chat.back`、增加“收起列表”按钮；正文/输入栏最大宽；`ConversationPane` 里用 `.id(hostID + ":" + session.id)` 或去掉 `@State`，避免切换会话时复用旧 model |
| 修改 `Info.plist` | 外屏仍可保持 iPhone 竖屏；**内屏不遵循 `UISupportedInterfaceOrientations`**，布局只看 size class。多窗口开关在生成器里，不在这个 plist |
| 修改 `scripts/generate-ios-project.py` | 只在需要改 build settings 时动它：多窗口开关、scene manifest；新 Swift 文件由 glob 自动进 target。Xcode 27.1 / iOS 27.1 SDK 的构建参数在这里或 `build-ios.sh` 固定 |
| 不要手改 `ios/CmuxRemote.xcodeproj` | 它是生成物；`scripts/build-ios.sh` / `scripts/test-ios-navigation.sh` 每次先跑生成器，手改会被覆盖 |

### 5.3 实施顺序

1. **窗口类与 token**：新增 `MobileWindowClass`，用 `GeometryReader` 的 `size.width`、`horizontalSizeClass` 与（iOS 27.1）`reservedRegions` 计算；在 320/375/430/466/**626**/720/744/834/**890**/1024/1366 宽度下写单测。`MobileDesign` 增加 `maxConversationWidth`、`browserWidth`、`supportingWidth`；600–719 的浏览器取 240–280，720+ 取 320–400。
2. **抽浏览器状态**：把 `SessionListView.swift:7-32` 的状态按“成对”迁移，而不是只迁 query/filter：
   - `selectedConversation` + `selectedHostName`（改成 `hostID + session.id` 身份）；
   - `showConversation`（驱动 push）、`showFeed` + `feedHostID`、`showConnection` + `connectionHostID`；
   - `showStart` + `startFrom`、`awaiting` + `startNotice`（启动会话的等待/通知属于 Shell，不应被视图分支销毁）；
   - `query` / `filter` / `workspaceID` / `hostFilter` / `sortMode` / `collapsedKeys`；
   - 两个独立的 `showSearch`（`SessionListView.swift:7` 与 `SessionSidebarView.swift:15`）；
   - `AppModel.sidebarOpen` / `addingDevice`（跨窗口共享，必须移入 ShellState 或按场景拆）；
   - `allowsEdgeOpening` 由上述状态派生，不再单独存。
   `@AppStorage` / `@SceneStorage` 保留在 Shell/View 层（它们是 `DynamicProperty`，不能塞进 `@Observable`）；保留现有 `"\n"` 折叠键格式。主页 `collapsed` 默认全展开、抽屉 `expanded` 只展开第一个项目，这两个语义要统一，否则双栏与抽屉会表现不一致。先跑旧 UI 测试，证明无回归。
3. **抽浏览器视图**：`SessionSidebarView` 的契约是**不可变 discovery 快照**（`SessionSidebarView.swift:4`：never a live store under lazy rows），不要把它直接换成由 `@Observable` 驱动的 live model。抽屉继续接收快照入参；只有双栏的 `SessionBrowserPane` 读模型。`SessionListView` 的列表主体可以复用行/分组子视图，但两种折叠语义先统一。
3b. **iPhone Duo spike（在定壳之前）**：用 Xcode 27.1 + Device Hub 的 iPhone Duo 模拟器，依次试：
   - `ArrangementView { SessionBrowserPane } secondary: { ConversationPane }.arrangementViewStyle(.split)`；
   - `NavigationSplitView { SessionBrowserPane } detail: { ConversationPane }`，用 `.toolbar(.hidden)` / 自定义 header 试保留现有浮动样式；
   - 自绘 `HStack` + 两栏 `NavigationStack`（fallback）。
   每个方案都测：外屏 compact、内屏竖屏 626pt、内屏横屏 890pt、半开姿态、Split View 469pt、侧边 rail 84pt、折痕/摄像头 `reservedRegions`。选定后把选择记录在本文档的 P1 结果里，不要三种都留在生产代码。
4. **根壳**：`AdaptiveShell` 必须在 **Compact 分支与双栏分支之上**持有 browser model、selection、awaiting/startNotice、cover targets；不要写成两个互斥根分支、各自把状态留在 `SessionListView` 的 `@State` 里，否则切换窗口类会销毁查询、焦点、启动等待任务。更稳的做法是单一视图树，只换布局容器。
   - Compact（<600，含外屏与 Split View 469pt）：`SideDrawer` + `AppNavigationStack { SessionListView }`（原路径）。
   - 双栏（600+）：优先用 3b 选定的系统壳；fallback 是 `HStack { SessionBrowserPane; Divider; ConversationPane }`；每栏自己的 `AppNavigationStack`。
   - 选择会话：Compact 设置 push；双栏设置 `detail.selectedSession`，不 push。
5. **详情栏**：`ConversationPane` 在无选择时显示空状态（“选择会话”），有选择时构造/复用 `ConversationModel`。`ConversationView` 内部是 `@State private var model`（`ConversationView.swift:8,60-62`），同一结构位置换选中会话会复用旧 model；必须加 `.id(hostID + ":" + session.id)`，或改成 `let model` / `@Bindable`。项目/Feed/图片/工具详情在 `>= 1100` 且对话可用宽 `>= 480` 时进入支持面板，否则在详情栈 push。`chat.back` 在双栏隐藏，改为“收起列表”或焦点回浏览器；现有 UI 测试依赖 `chat.back`，见第 10 步。
6. **抽屉与手势**：双栏不创建 `SideDrawer`，避免 77% 数学；浏览器折叠用动画宽度 0/240–400；`InteractivePopInstaller` 只在详情栈内启用；边缘手势不与浏览器滚动冲突。抽屉在 Compact 下仍用快照入参，不要因为抽了模型就改成 live 绑定。
7. **Stage Manager / 旋转 / 折叠 / 滚动锚点**：宽度变化时只重算窗口类；`ConversationModel` 不重建。iPhone Duo：
   - 用 `onHingeChange` 读 `status` / 角度；半开时把输入栏放低半屏（tabletop），不要让时间线跨折痕。
   - 用 `reservedRegions(kind: .division)` 避开折痕，`.occlusion` 避开内屏摄像头/灵动岛；自绘壳必须显式处理，系统壳通常自动处理。
   - 用 `toolbarVerticalEdge` 判断侧边 rail 在哪一侧；左右 inset 分别计算，不要 `left == right` 或 `UIScreen.main`。
   - Split View 469pt 回落到单栏；内外屏切换保持选择/草稿/滚动。
   `ConversationView` 的几何测量只覆盖高度与内容高度（`ConversationView.swift:188,246-248,360-362`），跟随触发只挂在 `timelineItems.last?.id` / `latestMessageText` / `preview`（`:403-408`），`bottomVisible` 在行变高时会把 `atLatest` 置 false（`:466-473`），`settleAtBottom` 只在 last-id 变化和 `onAppear` 调用（`:319-329`）。因此**变窄导致行变高后，最新内容会落到输入栏下方且不再恢复跟随**。修正：宽/高变化时，如果 `atLatest` 就 `settleAtBottom`；否则记录当前首个可见行并 `scrollTo(anchor: .top)`；布局稳定后重算 `pageTail`。不要“临时关闭 atLatest 跟随”，那方向相反。补一条 `MobileScrollAnchorUITests` 的 iPhone Duo 旋转/折叠用例，断言最新行仍在输入栏上方且不出现 `chat.latest`。
8. **多窗口**：iOS 已经开启多场景（生成器 `UIApplicationSceneManifest_Generation = YES`，产物 `UIApplicationSupportsMultipleScenes = true`）。P1 二选一：
   - 在 `scripts/generate-ios-project.py` 显式设 `INFOPLIST_KEY_UIApplicationSupportsMultipleScenes = NO`，先关掉；或
   - 正式支持：把 `sidebarOpen` / `addingDevice` 移入 ShellState，把 `CmuxRemoteApp` 的三个 `.task` 改成单所有者（每个场景只跑自己的监督任务），并让同一 `ConversationModel` 的草稿/读取所有权按窗口隔离。
   P3 再完成 Stage Manager 多窗口 / Android 多实例；连接与授权仍共享。
9. **iPhone 外屏/横屏**：iPhone Duo **内屏不遵循 `UISupportedInterfaceOrientations`**，布局只看 size class；外屏仍像普通 iPhone，可保持竖屏。P1 用 Device Hub 测内屏竖屏/横屏/半开；普通 iPhone 是否放开横屏仍按 P1.5 评估，不要为了 Duo 改掉外屏行为。
10. **测试**：现有 UI 测试硬依赖 Compact 标识符与 push（`MobileGestureUITests.swift:14-15,20`、`MobileOpenConversationUITests.swift:19,27`、`MobileStoreScreenshotsUITests.swift:18,21` 等），而宽屏会隐藏 `chat.back`；`scripts/run-ios-navigation-tests.py:34` 没有按设备/测试过滤，在 iPad/iPhone Duo 上跑全套会在双栏模式误报。做法：
    - 给旧测试加“强制 Compact”启动参数，或在宽屏目的地上跳过依赖 push 的用例；
    - 新增 iPhone Duo 自适应测试：Xcode 27.1 Device Hub 的 iPhone Duo 模拟器，覆盖外屏/内屏竖屏/内屏横屏/半开/Split View；固定任务专用设备，不并行克隆；
    - Stage Manager / Device Hub 的连续拖动与铰链角度无法用 XCUITest 稳定脚本化，作为人工验收；
    - 宽度变化后的滚动断言放进 `MobileScrollAnchorUITests`，不要依赖 `ConversationView` 的私有 `settleAtBottom`（`:319`，没有测试模式）。

### 5.4 关键风险

| 风险 | 说明 | 缓解 |
| --- | --- | --- |
| 手势冲突 | 抽屉边缘手势、系统返回、滚动、浏览器折叠按钮争夺边缘 | 双栏不启用抽屉；详情栈保留系统返回；浏览器折叠用显式按钮 + 可选拖拽分隔条 |
| 滚动锚点 | 宽度变化导致行变高时，`ConversationView` 的 `bottomVisible` 会把 `atLatest` 置 false，最新内容落到输入栏下方且不再恢复跟随（`:466-473`） | 布局变化时按 `atLatest` 选择 `settleAtBottom` 或“保持首个可见行”重锚；布局稳定后重算 `pageTail`；补 iPad 旋转用例。不要冻结跟随 |
| `SessionListView` 状态耦合 | 约 20 个 `@State` 与视图强绑定，且成对出现（cover targets、awaiting、两个 showSearch、相反折叠语义） | 先按成对状态抽到 Shell，再拆视图；旧测试先行；一次只迁一组 |
| 视图分支销毁状态 | Compact 与双栏两个根分支切换会销毁 `SessionListView` 的 query/focus/awaiting，启动会话等待任务被取消 | Shell 在分支之上持有 browser model/selection/awaiting，或保持单一视图树只换布局 |
| iPad 商店展示 | 现在虽是 iPad 设备族，但 UI 是手机布局；改为双栏后需要 iPad 截图与审核说明 | P1 末尾更新 `docs/images`、TestFlight 说明、隐私/商店文案 |
| 多窗口已开启 | 产物 `UIApplicationSupportsMultipleScenes = true`；`AppModel.sidebarOpen` / `addingDevice` / 缓存 `ConversationModel` 草稿与读取被共享 | P1 显式关闭（生成器）或按场景拆状态/任务所有权；P3 再完成多窗口。不能假设单窗口 |
| iOS 27.1 API / 工具链 | 当前 Xcode 26；`ArrangementView` / `onHingeChange` / `reservedRegions` 需要 Xcode 27.1 + iOS 27.1 SDK；第三方文章给出的签名未在 SDK 头文件核对 | P1 先装 Xcode 27.1，用 `#available(iOS 27.1, *)`；所有 API 名称以头文件为准；旧系统保留 fallback |
| 系统壳与浮动头部冲突 | `NavigationSplitView` / `ArrangementView` 的侧栏、垂直工具栏可能和自绘浮动头部/隐藏导航栏冲突 | P1 用 3b 的 spike 对比三种壳；不能保留旧视觉就选 `ArrangementView` + 自绘头部；不要三种并存 |
| 侧边 rail / 非对称安全区 | 折叠/横向姿态系统栏变成约 84pt 的 rail；Split View 下 rail 可能在左侧或右侧，窗口约 469pt | 按 `toolbarVerticalEdge` 和左右 inset 分别布局；浮层按 `insets.right/left + 16`；测 Split View |
| iPhone Duo 首批质量 | 媒体报告内屏沿折痕开裂、部分第三方应用未适配、内外屏切换异常；Apple 承认少量设备问题 | 真机/Device Hub 做折痕、半开、连续开合、Split View 测试；不要把模拟器通过当成真机通过；保留 iOS 27.1 fallback 路径 |

### 5.5 iOS 验收

- [ ] iPhone 外屏（约 466pt）/ 普通 iPhone 竖屏：现有 23 个 UI 测试文件全通过；抽屉、push、返回、滚动、图片、工具详情无回归。
- [ ] iPhone Duo 内屏竖屏（约 626pt）：浏览器 + 对话双栏；选择后不 push 覆盖列表；连续选两个会话内容切换。
- [ ] iPhone Duo 内屏横屏（约 890pt）：双栏/侧栏；系统垂直 rail 与左右 safe area 正确；不出现内容压到 rail 或折痕。
- [ ] 折叠/展开/半开（tabletop）运行中：最新行不跳到输入栏下方；草稿、滚动、展开卡片保持；输入栏不跨折痕。
- [ ] `reservedRegions(kind: .division/.occlusion)`：折痕、内屏摄像头、灵动岛区域没有交互控件。
- [ ] Split View（约 469pt 宽）：回落到单栏；rail 在左/右都能正确布局；内外屏切换不丢选择。
- [ ] 壳的方案已定：`ArrangementView` / `NavigationSplitView` / 自绘 HStack 三选一，记录 Device Hub 姿态截图与选择理由。
- [ ] Xcode 27.1 构建通过；iOS 18–27.0 fallback 构建通过。
- [ ] iPad 全屏/分屏/Stage Manager：双栏、旋转、支持面板；选择、草稿、滚动保持。
- [ ] 键盘：外接键盘快捷键；软键盘弹出时输入栏不被遮挡；动态字体 200% 不截断。
- [ ] VoiceOver：浏览器/详情焦点顺序；运行中状态可播报；空状态有说明。
- [ ] 截图：Compact / Medium / Expanded 各一组，英文 + 简体中文。

---

## 6. Android 实现方案（P2+）

### 6.1 推荐技术栈

| 层 | 选择 | 说明 |
| --- | --- | --- |
| 语言 | Kotlin 2.x | 具体版本在 P2 开始时锁定并记录（**待核实**） |
| 最低版本 | 建议 `minSdk 29`（Android 10） | 兼顾 TLS 1.3、现代窗口/后台 API 与覆盖率；`compileSdk` / `targetSdk` 取发布时最新（**待核实** Play 要求）。若必须覆盖 Android 8/9，需要单独验证 TLS、Keystore 与自适应行为 |
| UI | Jetpack Compose + Material 3 | 单 Activity、Compose Navigation、`enableEdgeToEdge()` |
| 自适应 | `androidx.window`（`WindowInfoTracker`、`FoldingFeature`）+ Material 3 Adaptive 的 `WindowAdaptiveInfo` | 窗口类/姿态用官方 API；pane 布局首版自绘 `Row/Column`，由纯 `PaneLayoutPolicy` 输出宽度/铰链 gap。`ListDetailPaneScaffold` / `SupportingPaneScaffold` 只作无铰链平板备选，不能吸附铰链 |
| 并发 | Kotlin Coroutines + Flow | 连接用单 actor 式类 + `Mutex`；有界 `Channel`；显式取消 |
| JSON | `kotlinx.serialization` 解码 + 自写 `CanonicalJSON` 编码 | **签名/摘要必须用自写 canonical writer**，不能用默认 encoder |
| 加密 | Google Tink（Ed25519、HPKE、AEAD）+ Android Keystore 包装 | Ed25519 私钥以 Tink keyset 存储，用 Keystore AES-GCM 包装；StrongBox 可用时优先。**必须确认 Tink 支持 RFC 9180 authenticated（sender auth）模式**；若只支持 base 模式，改用 BouncyCastle 或经审计的实现，绝不能退化为 base 模式——那会失去主机/客户端身份绑定。Tink 的 HPKE API/版本与 Android 支持范围**待核实** |
| TLS / WS | OkHttp（`X509TrustManager` 自定义 pin、WebSocket 子协议） | **不能直接用 `CertificatePinner`**：协议 pin 是 DER 证书 SHA-256，不是 SPKI |
| 发现 | `NsdManager`（`_cmux-remote._tcp`）+ 二维码 / 粘贴 v2 登记 JSON / relay 兜底 | mDNS 在部分机型/网络不可靠；必须保留 QR 与非 bearer 的手动入口 |
| 扫码 | CameraX + ML Kit bundled barcode（或 ZXing 变体） | ML Kit 离线模型不依赖 Play Services，但仍有 Google 依赖；F-Droid 版本用 ZXing |
| 持久化 | DataStore（连接/relay）、文件或 Room（操作账本、会话缓存） | 账本必须 fsync、容量有界、损坏时 fail closed；不备份 |
| 后台 | WorkManager（best-effort）+ 前台生命周期 | 不承诺常驻 WebSocket；首版不做 FCM（会引入服务端，违反“无开发者服务器”） |
| 语音 | `SpeechRecognizer` + `EXTRA_PREFER_OFFLINE`，并检查 on-device 支持 | `EXTRA_PREFER_OFFLINE` 只是偏好，不保证本地识别；必须先查询 `RecognitionSupport` / on-device 可用性，不可用就隐藏麦克风，绝不回退到云端识别 |
| DI | 手写 `AppContainer`（构造函数注入） | 与 Swift 的 composition root 一致；不引入 Hilt 以降低构建复杂度 |

### 6.2 模块与分层

模块树以 **3.3 的仓库布局为唯一版本**，不在这里重复。这里只强调 Android 特有的三条规则：

- 一个文件一个主要类型；与 Swift 的 “one major type per file” 保持一致。
- 依赖方向：`app → feature → core`；`core` 不依赖 `feature`；`protocol` 不依赖 `transport`；`crypto` 不依赖 OkHttp；固定证书 TrustManager 在 `transport`。
- feature 间跳转通过 `core/navigation` 接口；ViewModel 由 `AppContainer` 提供的 `ViewModelProvider.Factory` 构造，使用构造函数注入。

### 6.3 协议移植（详细合同见第 7 节）

Android 必须实现与 Swift 完全一致的：

- Ed25519 身份、公钥 Base64、identity ID = SHA-256(raw 32-byte public key) 十六进制。
- 签名输入 = UTF-8 `cmux-remote/2/<domain>\n` + **sorted-key、不转义斜杠**的 JSON；Data 字段用标准 Base64。
- 请求证明：`Authorization: "CmuxV2 " + Base64(JSON(SignedValue<RequestProof>))`；`uri` 是 percent-encoded path + 排序后的 query；`bodySHA256` 是原始 body 字节的 SHA-256；时间戳为 epoch 秒；nonce 每次新 UUID。
- v1 路径 → v2 线上路径的重写；失败时 `invalid_proof` 只允许丢 epoch 重试一次。
- Link v3：proposal/acceptance 签名域、HPKE `P256_SHA256_AES_GCM_256`、transcript/info 字符串、`SealedLinkPacket` 首包带 encapsulated key、后续不允许重置上下文。
- 固定证书：LAN 只信任保存的 leaf DER SHA-256 + 主机/端口；禁止重定向；relay 使用系统 PKI + HPKE。
- WebSocket 子协议 `cmux-remote.v3`；LAN `/v3/link` 不允许 query；二进制帧；2.1MB 包上限。OkHttp 不像 `URLSessionWebSocketTask.maximumMessageSize` 那样内置消息上限，必须在 `onMessage` 里自行拒绝超过 2.1MB 的帧并关闭链路。
- HPKE 上下文是有状态的：同一方向的 `seal` / `open` 必须严格串行，不能并发调用；把 cipher 关在一个 `Mutex` / actor 里，发送队列按序写帧。
- 请求/响应：8 个并发请求、16 个订阅、20s 单请求 deadline、64KiB 分块、4 块未确认窗口、慢消费者断开、8MB 响应上限。

**建议**：先写 `spec/` 与黄金向量，再写 Kotlin 实现。否则 Kotlin 端会以“看起来对”的方式实现出一个只有真机配对才会暴露的协议 bug。

### 6.4 Android 传输与安全实现要点

#### 证书固定

- `HostIdentity.certificateSHA256` 是**叶子证书 DER 的 SHA-256**（`PinnedSessionDelegate.swift` 明确 `SecCertificateCopyData` 后哈希），不是公钥 SPKI。
- Bridge 生成的是**自签证书**（`Sources/CmuxRemoteBridge/BridgeState.swift:21` 一类 `openssl req -x509 -subj /CN=cmux-remote`，没有 SAN）。因此 LAN 路径**不能做 CA 链校验，也不能依赖系统主机名校验**；链校验必然失败。正确语义与 iOS 一致：只比对 leaf DER 的 SHA-256，并校验保存的 host/port。
- OkHttp 的 `CertificatePinner` 默认 pin SPKI，**不能直接用**。实现：
  - `PinnedTrustManager`：取 leaf `certificate.encoded`，SHA-256，与保存值常量时间比较；**跳过 CA 链校验**；不匹配即抛错。
  - `PinnedHostnameVerifier`：OkHttp 在 TrustManager 之后仍会调用它；它拿不到“pin 已成功”的内部状态，所以必须**自己重新比对同一 leaf DER pin 和保存的 host/port**。绝不是 `HostnameVerifier { _, _ -> true }`，也不是全局宽松。
  - 这两个对象只装在 **LAN 客户端**上；relay 客户端用系统 PKI + 默认 hostname verifier，业务内容由 HPKE 保护。
  - 重定向一律拒绝（`followRedirects(false)` / 拦截器返回空）；失败抛稳定 code（`host_changed` / `invalid_certificate`），不降级到系统信任。
- 测试四组：自签/IP 正常通过、错误证书拒绝、错误 host 拒绝、302 不跟随。relay 路径另测系统 PKI 与 HPKE。

#### 密钥存储

- 生成 Ed25519 私钥（Tink `Ed25519PrivateKey`），将 keyset 序列化后用 Android Keystore 的 AES-GCM 密钥加密，密文存私有文件/DataStore。
- Keystore 密钥设置 `setUserAuthenticationRequired(false)`（与 iOS 一致，不要求每次解锁）；如后续要 App 锁，另加生物识别门，不改变协议。
- `android:allowBackup="false"`，并提供 `dataExtractionRules` 排除连接/密钥/账本/缓存；避免云备份把设备身份克隆到第二台设备。
- StrongBox 可用时优先；不可用则普通 Keystore；**不要静默降级**：记录实际 backing（StrongBox / TEE / 软件），StrongBox 密钥在使用期失效时按“身份不可用”处理，而不是悄悄换一把钥匙继续连。
- **身份重置流程**：包装密钥丢失 / Keystore 重置 / 恢复备份导致 keyset 不可解时，只能生成**新的 Ed25519 身份并重新登记**；不能复用旧 clientID。Mac 上的旧 `android` client 仍会存在，设备列表会出现第二个同名设备：新设备显示“需要批准”，旧设备由主人撤销/遗忘。Android 端要把这种情况显示成可操作的“重新配对”，不能无限重试旧 grant。
- 测试：删除 app 数据、换机、恢复备份、Keystore 重置、StrongBox 失效；每种情况都要有明确 UX，不能静默把旧身份当成新身份。
- Root / 模拟器无法提供与 iOS Keychain 同等级的非导出保证，文档必须如实说明；不要声称“硬件不可导出”。

#### 网络配置

- `android:usesCleartextTraffic="false"`；`networkSecurityConfig` 禁止明文。
- 不信任用户安装的 CA 用于 LAN pin（pin 本身绕过 CA）；relay 使用系统信任，用户 CA 可能看到 TLS 外层，但 HPKE 保护业务内容。
- 所有请求有 deadline；POST 失败不自动重试；`outcome_unknown` 交给操作回执查询。

#### 二维码与深链

- 首版只做应用内扫码，不注册外部 `VIEW` intent / 深链，减少导出组件攻击面。
- QR 内容解析后先校验主机签名、窗口有效期、TLS pin，再发起登记；不把 QR 当 bearer token。
- 相机权限按需申请；拒绝后仍可粘贴 v2 登记 JSON / 附近设备 / relay 目录。
- 剪贴板不自动读取；手动粘贴需要用户操作。

### 6.5 发现与配对

- 需要的权限：`INTERNET`、`ACCESS_NETWORK_STATE`；使用 `MulticastLock` 时加 `CHANGE_WIFI_MULTICAST_STATE`；如果直接读 Wi-Fi 状态再加 `ACCESS_WIFI_STATE`；扫码用 `CAMERA`；如果后续加本地通知再加 `POST_NOTIFICATIONS`。Android 13+ 的 `NEARBY_WIFI_DEVICES` 是否适用于所选 NSD 路径要按 targetSdk 核实。不要申请与功能无关的存储/位置权限。**Android 16+ 可能引入本地网络访问权限（`ACCESS_LOCAL_NETWORK`）**：需在目标 SDK 上核实并申请，否则 LAN 直连会失败、只剩 relay（**待核实**）。
- `NsdManager` 浏览 `_cmux-remote._tcp`；Android 12+ 的 mDNS 行为、`WifiManager.MulticastLock`、企业 Wi-Fi / 访客网络隔离都需实测（**待核实**）。
- 生命周期：注册 `ConnectivityManager.NetworkCallback`；Wi-Fi/蜂窝切换、网络丢失、访客网隔离后清空过期发现结果并重启 browse；退后台停止 browse，回前台重启；单个 resolve 用串行队列（并发会 `FAILURE_ALREADY_ACTIVE`），带超时和有限重试；结果去重、有界。
- 可测试性：把发现抽象成 `DiscoverySource` 接口，由 `AppContainer` 注入；JVM/Compose 测试用 fake source，真机/AVD 用 NsdManager。参考 iOS 的 `CMUX_REMOTE_TEST_NEARBY_PATH` 注入方式，不要让 UI 测试依赖真实局域网。
- 发现结果只作为可达性提示；首次信任仍需 QR 或显式确认主机身份（与 iOS 一致）。
- relay 目录：`RelayDirectoryClient` 的同一合同；host-signed entry 逐个验证，不因为来自 relay 就信任。
- 配对状态机与 iOS 对齐：扫码 → 登记请求 → 等待主人在 Mac 批准 → 保存 grant → 连接；拒绝/过期/撤销都显示稳定错误码的本地化文案。
- 二维码解析优先支持 v2 `cmux-remote://enroll...`；legacy `PairingLinkCodec` 是共享 bearer，Android 首版不默认支持。若扫到 legacy，提示它需要 Bridge 显式开启、不可按设备撤销，并走单独确认（见 7.1a）；不要把它混进 v2 登记状态机。

### 6.6 后台与通知

- 应用退到后台：取消订阅与前台轮询；不保持长连接。
- 回到前台：先重连/读取，再订阅；与 iOS 的 `AppModel+Connection` 策略一致。
- `WorkManager` 只做 best-effort 同步（系统最小周期约 15 分钟，**待核实**），不保证及时性；结果不写敏感内容到通知。
- 首版不接 FCM：FCM 需要一个受信任的服务端/Google 项目，与“没有开发者服务器、没有账号”的产品边界冲突。如果未来要做“后台审批通知”，单独设计，不把持久 WebSocket 当推送。
- HyperOS / MIUI 的省电策略可能杀死后台任务；文档如实说明“后台同步是 best-effort”，不承诺。

### 6.7 自适应实现

- 单 `MainActivity`，`enableEdgeToEdge()`；`android:resizeableActivity="true"`；不要用 `android:configChanges` 强行阻止重建（Compose 会重组，ViewModel 保留）。
- `WindowInfoTracker.getOrCreate(context).windowLayoutInfo(activity)` → `collectAsState`；同时用 `calculateWindowSizeClass(activity)` / `currentWindowAdaptiveInfo()`。
- `PaneLayoutPolicy`（纯 Kotlin）输入：窗口宽高、hinge bounds/orientation/state、是否 tabletop；输出：`Compact` / `TwoPane(browserWidth, detailWidth, gap)` / `ThreePane(...)`。这个类可做 JVM 单测，不依赖 Compose。
- 布局：
  - Compact：`ModalNavigationDrawer` + 单 `NavHost`。
  - Medium/Expanded：**首版自绘 `Row` + `PaneLayoutPolicy`**；浏览器 240–400（600–719 取 240–280，720+ 取 320–400）；详情 `weight(1f)`。不使用 `ListDetailPaneScaffold` / `SupportingPaneScaffold` 作为主壳：它们自带 pane 导航与宽度策略，不能可靠吸附 `FoldingFeature.bounds`，还会和单 `NavHost` 的返回栈冲突。它们只作为“无铰链平板”的备选，不进入折叠屏路径。
  - 支持面板：仅当 `总宽 >= 1100` 且对话可用宽 `>= 480` 时，自绘第三栏；否则项目/Feed/工具详情在详情栈 push。
  - Tabletop：垂直 `Column`，时间线 `weight(1f)`，输入栏在铰链下方；列表仍按宽度决定是否显示。
- 分隔条：自绘 1dp 线 + 8dp 拖拽命中区（可选）；竖直铰链时把 gap 设为铰链宽度，内容不进入 gap。
- 返回：`NavHost` / `NavBackStackEntry` 负责详情 push 的返回；需要预测动画时用 `PredictiveBackHandler`，**`BackHandler` 只负责拦截，不产生预测动画**。详情根时把焦点移回浏览器并清空选择（可选）；浏览器根时交还系统退出。`android:enableOnBackInvokedCallback="true"`。
- **窗口类切换的状态迁移**：Compact→双栏时，如果当前正 push 一个会话，关闭该 push 并把会话设为 `detail.selection`；双栏→Compact 时，如果已有 `detail.selection` 且此前在双栏显示详情，push 一次该会话，避免重复 push 或空白详情。返回栈不能因为旋转而丢会话。
- ChromeOS / Samsung DeX / 桌面 / freeform 窗口按 Expanded 处理；鼠标、触控板、键盘按 4.6 的规则，不另做一套布局。
- 配置变化：`rememberSaveable` 保存查询/过滤/折叠状态；选中会话用稳定 ID 保存；`ViewModel` 持有数据与连接，不持有 Activity context。

**小米 18 Fold 的实测重点**（公开信息，最终以真机为准）：

- 5.38" 外屏 + 7.58" 内屏，展开 163.8 × 117.8 mm，219 g，5.02 mm；内屏按 √2 比例估算约 **700dp 宽**（横屏更宽），必须用 `WindowMetrics` 实测。
- 澎湃 OS 4 的最多六分屏 + 悬浮小窗、三指横滑、拖拽调整比例；要测我们的双栏在系统六分屏/小窗里是否仍可用，以及外屏→内屏切换是否保持会话/草稿。
- 重点验证：`FoldingFeature` 的折痕 bounds、悬停角度、分屏/小窗下的窗口宽度、后台限制、Keystore/StrongBox、mDNS。不要在代码里写“小米专用”分支；用窗口宽度和 `FoldingFeature` 判断。

### 6.8 设计系统映射

| iOS | Android |
| --- | --- |
| `Color.white` 画布 | `Surface(color = Color.White)` + `WindowInsets` 全屏 |
| `FloatingSurface`（22pt 圆角、轻阴影） | `Modifier.shadow(14.dp, RoundedCornerShape(22.dp))` + 白底 + 0.5dp 描边 |
| `FloatingButtonStyle`（胶囊） | `Button` + `RoundedCornerShape(50)`；主操作蓝底白字 |
| `FloatingIconStyle`（44×44 圆） | `IconButton` + 48dp 命中区 + 白色圆底 |
| `FloatingInput`（16pt 圆角） | `OutlinedTextField` 自绘容器，16dp 圆角 |
| 系统动态字体 | `sp` + `fontScale`；不要用固定 `dp` 当字号 |
| 浅色固定 | 强制 light theme（与 iOS `.colorScheme(.light)` 一致）；不跟随系统深色 |
| 触感 | 可选 `HapticFeedback`；不改变功能 |

Android 应保留平台习惯：ripple、predictive back、TalkBack、系统分享/文件选择器；不要为了“像 iOS”而移除这些。

### 6.9 功能对等矩阵

| 功能 | iOS 现状 | Android P2 | Android P3/P4 | 备注 |
| --- | --- | --- | --- | --- |
| 配对：扫码 / 附近 / 粘贴 v2 登记 / relay 目录 | 有 | ✅ | | QR + NSD + v2 登记粘贴；legacy token 不默认支持 |
| 多 Mac 列表 / 工作区 / 过滤 / 搜索 / 排序 | 有 | ✅ | | 同一信息架构 |
| 会话历史 / 分页 / 预览 | 有 | ✅ | | 同一 API |
| 发送 / 停止 / 硬停止 | 有 | ✅ | | 操作账本一致 |
| 操作回执查询 | 有 | ✅ | | 失败后只查 `GET /v2/operations/...`，不自动重发 |
| Feed 待处理 / 问题 / 权限 / plan | 有 | ✅ | | 同一 DTO |
| 模型切换（Claude / Codex） | 有 | | ✅ | 依赖 agent 自身命令，不在手机执行 |
| 新会话 / 恢复会话 | 有 | | ✅ | `conversationStart` |
| 项目文件 / diff | 有 | | ✅ | 路径策略在 Bridge |
| 后台任务 / 任务详情 | 有 | | ✅ | 同一路由 |
| 工具完整记录 | 有 | | ✅ | 分页 |
| 历史图片 / 缩放 | 有 | | ✅ | 图片走 session reference |
| 图片附件发送 | 有 | ✅ | | Photo Picker + 解码后重编码（去掉 EXIF/GPS），每张 <= 512 KiB、最多 4 张 |
| 语音输入 | iOS on-device | | ✅（条件） | Android 识别器可用性不一；不可用则隐藏 |
| 重命名会话 | 有 | | ✅ | |
| 后台刷新 | BGTaskScheduler | △ 仅 cache warm | | WorkManager 取到的数据只用于回前台立即显示；无通知、不承诺及时性，不作为 P2 出口条件 |
| 多窗口 | 无（P3） | | ✅ | |
| 折叠屏姿态 | iOS 27.1 系统有 `ArrangementView` / `onHingeChange` / `reservedRegions`；App 待适配 | ✅ | | Android `FoldingFeature`；iOS 27.1 系统 API + fallback |
| 通知 | 无 | 不做 | 待定 | FCM 需要服务端，另行设计 |

### 6.10 Android 测试与工具

- JVM：`core/protocol` 单测 + 黄金向量；`PaneLayoutPolicy` 单测；操作账本 / 缓存 / 错误码映射。
- Robolectric：少量 Android 框架依赖的单元测试（DataStore、资源）。
- Compose UI：列表/会话/配对/Feed 的可组合测试；在 360 / 600 / 840 / 1200dp 下截图。
- 截图回归：Paparazzi 或 Roborazzi（**待核实**当前版本兼容性）；至少覆盖 Compact / Medium / Expanded / 深色（即使产品只做浅色，也验证不崩）。
- 折叠屏：`androidx.window.testing` 的 `WindowLayoutInfoPublisherRule` 模拟 `FoldingFeature`；`Gradle Managed Devices` 跑 Pixel Fold / 平板 AVD；真机仍需单独验收。
- 仪器测试：Keystore、NSD、CameraX、文件选择器、预测性返回。
- 性能：大历史（几千条）、1MiB 请求、8MiB 响应、图片解码；Macrobenchmark 启动/滚动。
- 可访问性：TalkBack 扫描、fontScale 200%、对比度、焦点顺序。
- 本机工具链：当前只有 `adb` / `sdkmanager` / `emulator`、platforms 34–36、android-35 arm64 镜像和两个现有 AVD；**没有 Gradle / Kotlin / Android Studio**。P2 开始前安装并固定版本，创建任务专用 AVD，不修改用户现有 AVD。UI/仪器测试只使用本任务创建的 AVD 或真机。

### 6.11 发布

- **渠道矩阵要先定**，否则签名/包名会返工：
  - Play：App Bundle + Play App Signing；`applicationId` A；上传密钥私有。
  - GitHub Releases APK：如果与 Play 同 `applicationId` 但用不同 key 签名，**不能覆盖安装/更新 Play 版**；要么只发 Play，要么用独立 `applicationId`（如 `….github`）并明确这是另一条安装线。
  - F-Droid：需要 FLOSS 依赖；ML Kit 版不适用，需 ZXing 变体；同样建议独立 `applicationId` / 签名，并满足可复现构建要求（**待核实**）。
- `applicationId` 候选：`com.cmuxremote.mobile` 一类；确认商标、开发者账号、Play 包名唯一性后再定。iOS bundle id 含连字符，不能直接复用。
- `targetSdk` / `compileSdk` 在 P2 开始时就锁定并记录；edge-to-edge、predictive back、`dataExtractionRules`、本地网络权限的行为都跟 targetSdk 绑定，不能拖到发布前才改。
- 版本号：`versionCode` 单调递增；`versionName` 与 iOS 不必相同，但发布说明要对齐。
- 商店材料：Android 大屏截图、折叠屏截图、隐私政策、Data safety（相机/照片/网络）、无分析 SDK 声明。
- 小米应用商店：可选；需要单独开发者资质与审核，不阻塞首版。
- 新个人 Play 开发者账号可能有 closed testing 人数/天数门槛（**待核实**）；P5 的 1–2 人周是工程估算，不含这段日历等待。

---

## 7. 协议合同与共享测试（P0）

### 7.1 必须冻结的细节

| 主题 | 现状（Swift 参考） | Kotlin 必须一致 |
| --- | --- | --- |
| 签名输入 | `IdentityCryptography.bytes`：`"cmux-remote/2/" + domain + "\n"` + `JSONEncoder(.sortedKeys, .withoutEscapingSlashes)` | 自写 canonical JSON；键排序、无斜杠转义、UTF-8、无多余空白；**非 ASCII（如中文主机名）按 UTF-8 原样输出，不转 `\uXXXX`**。注意：即使域名为 `link3-*`，前缀仍是 `cmux-remote/2/` |
| `Data` 编码 | Foundation `JSONEncoder` 默认 Base64 字符串 | 标准 Base64（带 padding、无换行） |
| 可选字段 | Swift `JSONEncoder` 省略 `nil` optional | Kotlin 必须**省略**而不是输出 `null`（`explicitNulls = false` 或自写 writer）；这是最常见的签名不一致来源 |
| 身份 ID | SHA-256(raw 32-byte Ed25519 public key) → 小写 hex | 同左；公钥以 Base64 传输；host 身份还要校验 id 与公钥一致、`certificateSHA256` 为 64 位 hex、name 非空且 <=128 字节 |
| 请求证明 | `RemoteClientRuntime.authorized`：`CmuxV2 ` + Base64(JSON(SignedValue<RequestProof>)) | 同左；`uri` 为 percent-encoded path + 排序 query；`bodySHA256` 是原始 body 字节的 SHA-256；GET 的 body 视为空字节（不是 `null` 的字符串）；`nonce` 每次新 UUID，时间戳为 epoch 秒且只接受 ±60s |
| URI 编码 | Swift `URLComponents.percentEncodedPath` + `percentEncodedQuery`；空格为 `%20`，query 按 key 排序 | 逐字节一致；用黄金向量覆盖空格、中文、`+`、`/`、`:`、`?`、`&`、`=`。不要用 `HttpUrl`/表单编码再拼一次 query，否则签名 URI 不同 |
| 路径重写 | 客户端 `/v1/...` → 线上 `/v2/...` | 同左；不得自行改路由 |
| 版本协商 | `/v2/identity` announcement `version == 2`；Link proposal/acceptance `version == 3`；WebSocket 子协议 `cmux-remote.v3` | 同左；未知版本 fail closed，不降级到 legacy/v1 |
| 登记 | `EnrollmentRequest` 字段：hostID / windowID / requestID / clientID / clientPublicKey / clientName / clientKind / nonce / scope / expiresAt；签名域 `enrollment-request`；bootstrap/host/status/grant 分别用 `bootstrap` / `host` / `enrollment-status` / `grant` | 同左；`expiresAt` 为 epoch 秒；clientKind 用 `"android"`；请求不可重签后复用 |
| Link v3 提案 | `LinkClientHandshake`：P-256 临时密钥、签名域 `link3-proposal`、时间戳 ±60s | 同左 |
| Link v3 接受 | `LinkAcceptance`：host 签名、proposalDigest、epoch、nonce | 同左；验证 host 身份与证书 pin |
| HPKE | `LinkCipher`：`P256_SHA256_AES_GCM_256`；transcript = `bytes(proposal, "link3-transcript-client")` + `bytes(acceptance, "link3-transcript-host")`；客户端**发送** info = `"cmux-link/3/" + digest + "/client-host"`，**接收** info = `"cmux-link/3/" + digest + "/host-client"`（服务端相反）。sender auth 使用的是本次握手的**临时 P-256 私钥**，不是 Ed25519 身份私钥 | 同左；首包带 encapsulatedKey，之后禁止重置；方向写反会导致握手成功但解密失败 |
| 证书 pin | `PinnedSessionDelegate`：leaf DER SHA-256，host/port 精确 | 自定义 TrustManager；不是 SPKI |
| WebSocket | 子协议 `cmux-remote.v3`；LAN `/v3/link`；二进制帧 | 同左 |
| Link 帧 | `request/response/subscribe/event/cancel/ack`；`data <= 1 MiB`；`uri <= 16 KiB` | 同左；字段名与可选性一致。**以代码为准：当前 `LinkFrame` 没有 `blob` kind**；`docs/WEBSOCKET-RELAY.md` 中的 `blob` 仍是设计，不要按它实现 |
| 分块 | 响应 `index/final`，最多 4 块未确认，乱序/超前 ACK 断开 | 同左 |
| 链路时序 | LAN dial deadline 8s、relay 15s、心跳 25s、pong 10s、单请求 20s（`WebSocketTransport` / `LinkClientConnection`） | 同左；数字以当前代码为准 |
| 错误 | `{"error":{"code","message"}}`；稳定 code | 只按 code 本地化；不解析 message 做逻辑 |
| 操作账本 | 共享 ledger：按设备 + operation UUID，16,384 个 key / 16 MiB；不自动驱逐；损坏/满/写失败 fail closed；POST 不自动重试 | 同左；Android 需 fsync 后再放行 dispatch，重启后不重放未完成意图 |
| 操作回执 | `GET /v2/operations/:operation_id` 返回 `{operation_id, state: accepted|outcome_unknown, recorded_at}`；要求原设备当前 capability/workspace；不存在为 `operation_not_found`，**不存在不等于没执行** | 同左；Android 发送/停止/Feed 失败后只查回执，不自动重发；回执 UI 不得把“查不到”说成“没执行” |
| 图片 | 上传：`send.attachments` 最多 4 张、每张 <=512 KiB、合计 <=640 KiB、仅 PNG/JPEG、每边 <=4096 px 且 <=8 MP，整体 body <=1 MiB；下载：`GET /v2/sessions/:id/image?reference_id&generation` 返回 JPEG <=512 KiB、最长边 1600 px、`no-store`/`nosniff`，`history.images` 绑定 generation | 同左；解码后重编码并去掉 EXIF/GPS；只按 reference ID 取图，不提交主机路径 |
| relay | `X-Cmux-Relay-Permit` / `X-Cmux-Relay-Join`；`RelayJoin(hostID, clientPublicKey, permitDigest)` 签名域 `relay3-join`，`permitDigest = digest(bytes(admission, "relay3-permit-envelope"))`；`relay3-hint` 用于路由提示 | 同左；permit 不是授权；relay 只提供传输可达性 |

**Canonical JSON / URI 规范必须写死，不能只写“排序、无斜杠转义”**：

- 转义表：`"`、`\`、`\b`、`\f`、`\n`、`\r`、`\t` 用短转义；其余 `< 0x20` 用 `\u00XX`；非 ASCII 按 UTF-8 原样；U+2028 / U+2029、emoji、非 BMP 字符必须用 Swift 生成的黄金向量逐字节确认，不靠猜。
- 数字：签名 DTO 只用整数；输出十进制、无前导零、无 `.0`；禁止把 `Int` 写成 `Double`，禁止浮点。
- 键排序：按 Swift `JSONEncoder(.sortedKeys)` 的比较语义；签名 DTO 的键限定 ASCII，避免 Unicode 排序差异。嵌套对象递归排序。
- 可选字段：省略，不输出 `null`；空数组/空字符串保留。
- URI：path/query 的 percent-encoding 用黄金向量固定；空格 `%20`，不是 `+`；query 只按 key 排序，重复 key 不支持；不对已编码字符串二次编码。
- 每个规则都要有一个“故意写错就失败”的向量，而不是只覆盖正常路径。

### 7.1a 登记状态机与 legacy 边界

Android 的登记不能只按“扫码 → 请求 → 等待”实现，必须冻结下面这条状态机（与 `Sources/CmuxRemoteClient/EnrollmentClient.swift` / `EnrollmentBootstrapClient.swift` 一致）：

1. `GET /v2/enrollment/bootstrap`：**未授权**请求，但必须先固定 TLS leaf；响应是 host 签名的 `EnrollmentBootstrap`（域 `bootstrap`），包含 host 身份、证书 pin、endpoint、窗口 ID、过期时间与可选 relay admission。窗口 `expiresAt - now <= 600s`；过期/签名错/身份错立即失败。
2. 用设备 Ed25519 身份开一条 link v3（`/v3/link`）到该 host；link 层要求请求里的 `clientID` 与握手身份一致（Bridge 的 `verifyChannelIdentity`）。**登记请求也走这条链，不是裸 HTTPS 表单。**
3. `POST /v2/enrollment/request`，body 为 `SignedValue<EnrollmentRequest>`，域 `enrollment-request`；字段见 7.1。`clientKind = "android"`，`clientName = "cmux Android"`。
4. 轮询 `POST /v2/enrollment/status`（域 `enrollment-status`），必须带同一个 `requestID` / `nonce`；主人拒绝、取消、过期都不返回 grant。批准后返回 `SignedValue<EnrollmentGrant>`（域 `grant`），scope 必须是请求 scope 的子集；持久化前验证签名、hostID、clientID、requestID、nonce。
5. `POST /v2/enrollment/cancel` 取消本设备的待批准请求；断线/退后台不能把“未批准”误判为“已批准”。
6. **旧 Bridge 能力回退**：旧 Bridge 不认识 `conversationStart` 时会在登记期间关闭链路；客户端要像 iOS 的 `previousPhoneCapabilities` 一样，去掉该能力重新登记一次，不能把链路关闭当成网络错误无限重试。
7. relay 登记 permit 绑定 `windowID/expiresAt`；批准后的 permit 绑定 client 公钥。permit 只给传输准入，grant 才是资源授权。

**legacy 边界**：`PairingLinkCodec` 的 `PairingConfiguration{host,port,token,certificateSHA256}` 里的 `token` 是**共享 bearer**，不是 v2 登记。本文的“无永久凭据”只适用于 v2 QR / 附近设备 / relay 目录。Android 首版建议：
- 支持 v2 登记（扫码 / 粘贴 v2 登记 JSON / 附近 / relay）；
- **不支持** legacy token 手动输入；如果产品确实要支持，必须把它标成“显式 legacy、共享授权、不可按设备撤销”，单独做安全评审，并从“按设备撤销”的承诺里排除。

### 7.2 黄金向量（建议最小集）

`spec/vectors/` 下每个文件都是可被 Swift 与 Kotlin 同时读取的 JSON：

1. **identity**：固定 seed → Ed25519 公钥、Base64、identity ID、签名。
2. **canonical-json**：含斜杠、中文、控制字符、U+2028/U+2029、emoji、非 BMP、空数组、省略的 nil、大整数、嵌套对象、Data 字段的 DTO → 精确字节（hex/UTF-8）与 SHA-256。另含“错误写法必须失败”的负向量。
3. **request-proof**：固定 epoch/host/client/method/uri/body/nonce/timestamp → 精确签名与 `Authorization` 头；URI 覆盖空格、`+`、`%`、中文、`:`、`/`、`?`、`&`、`=`，以及重复 key 被拒绝。
4. **link-handshake**：固定客户端临时密钥与 host 密钥 → proposal 字节、acceptance 校验、transcript digest、HPKE info 字符串（两个方向）。
5. **certificate-pin**：一张自签无 SAN 的测试证书 → DER SHA-256；错误证书、错误 host、302 都必须拒绝。
6. **link-frame**：合法/非法帧的校验结果（超大 data、非法 kind、错误 UUID、乱序 ACK）。
7. **error-codes**：每个稳定 code 的 HTTP 状态与是否可重试。
8. **routes**：路由、所需能力、方法、请求/响应 schema 引用。
9. **enrollment**：bootstrap → request → status → grant 的完整签名链；过期/拒绝/取消/旧 Bridge 去 `conversationStart` 重登记。
10. **operation-receipt**：accepted / outcome_unknown / operation_not_found 的客户端处理；不存在不等于未执行。
11. **image-limits**：4 张 / 512 KiB / 640 KiB / 4096 px / 8 MP / 1 MiB body；下载 512 KiB / 1600 px / JPEG / no-store。

HPKE 本身有随机性，黄金向量不要试图固定密文；固定**握手 transcript / info / 密钥派生输入**，再用跨端握手测试验证双方能互相解密。

### 7.3 一致性测试

- 启动隔离 Bridge + fixture（复用 `scripts/fixtures/PhoneUIFixture.swift` 或 Kotlin 版 fake Bridge）。
- Swift conformance runner：用现有 `RemoteClient` 跑一组固定请求/订阅。
- Kotlin conformance runner：用 `core/transport` 跑同一组。
- 断言：相同输入产生相同签名/摘要/Authorization；双方都能完成登记、连接、读取、发送、停止、订阅、撤销。
- 测试不得连接真实 cmux / provider；不得把真实转录、密钥、token 写入 fixture。

### 7.4 Bridge 必须改的地方（不扩大授权）

| 位置 | 现状 | 改动 |
| --- | --- | --- |
| `Sources/CmuxRemoteBridge/ConnectionAuthority.swift:204` | `["iphone", "mac"].contains(request.clientKind)` | 接受 `"android"`；仍拒绝未知 kind |
| `mac/Companion/DevicesSettingsView.swift:100,105` | `kind == "iphone" ? "iphone" : "desktopcomputer"` | `android` 显示手机图标；`mac` 显示桌面 |
| Mac 审批文案 / 本地化 | 可能写死 “iPhone” | 改为“设备”或按 kind 显示；中英文键集一致 |
| `ios/Sources/AppModel.swift:78` | 登记名 `"cmux iPhone"`、kind `"iphone"` | 不变；Android 端用 `"cmux Android"`、`"android"` |
| `docs/API.md` / `docs/CONNECTION-V2.md` | 叙述性合同 | 增加 Android client kind、`spec/` 指针、跨语言要求 |

**不改**：能力集合、路由、授权检查、操作账本语义、证书 pin 规则、relay 规则。Android 不获得比 iPhone 更多的权限。

---

## 8. 安全与授权评审

| 风险 | 场景 | 缓解 | 阻塞发布？ |
| --- | --- | --- | --- |
| client kind 被拒 | Android 用 `android` 登记，Bridge 拒绝 | 改白名单；加登记测试 | 是 |
| 身份克隆 | Android 备份/换机把私钥复制到第二台设备 | `allowBackup=false` + dataExtractionRules；密钥用 Keystore 包装；文档说明 root 限制 | 是 |
| 证书 pin 语义错 | 用 OkHttp `CertificatePinner`（SPKI）导致 pin 永远不匹配或错误放行 | 自定义 TrustManager 比较 DER SHA-256；测试错误证书/错误主机 | 是 |
| 重定向泄露 | 请求被 302 到别的 host，Authorization 被转发 | 禁止重定向；不跟随 | 是 |
| 明文回退 | 网络配置允许 cleartext，或异常时降级 | `usesCleartextTraffic=false`；失败即失败 | 是 |
| 重放 | nonce/epoch 处理错误 | 与 Swift 同一合同；黄金向量 + 黑盒重放测试 | 是 |
| 结果未知重复写 | 发送超时后自动重试 | 只查 `operation_id` 回执，不自动重发；与现有账本一致 | 是 |
| 导出组件劫持 | 多余的 `intent-filter` / 导出 Activity | 只导出 launcher；首版无深链；`exported=false` | 是 |
| 二维码/剪贴板 | 恶意 QR、自动读剪贴板 | 校验签名/有效期/pin；剪贴板需用户操作 | 是 |
| 日志泄露 | 诊断日志记录 Authorization/body/query | 只记录方法、路由、耗时、错误码；有界 | 是 |
| 截图/最近任务 | 聊天内容出现在系统最近任务 | 首版不默认 `FLAG_SECURE`（会影响截图/分享）；作为隐私选项后续评估 | 否 |
| 多窗口泄露 | 两个窗口共享敏感选择 | 每窗口独立状态；连接共享但授权检查仍按请求 | 否 |
| 撤销延迟 | 链路打开后设备被撤销 | Bridge 在每次读取/写入/订阅发布前重查 grant；客户端收到 unauthorized 后停止 | 是 |
| 慢消费者 | 大响应/订阅积压 | 有界队列、64KiB 分块、4 块窗口、断开重同步 | 是 |

测试要求（与 `AGENTS.md` 对齐，另加 Android 专项）：

- stale binding、outcome-unknown 写入、转录半行/替换、证书 pin 不匹配、路径穿越、replay gap。
- Android：Keystore 不可用/重置、备份恢复、task hijacking、导出组件、错误 CA、NSD 不可用、进程死亡后账本恢复。

---

## 9. 交付计划

### 9.0 当前实现状态（2026-10-30）

**A2 第一版已接入 Bridge（验证于隔离 fixture，未接真实 cmux）**

- 传输：Android 走 **HTTPS + v2 请求证明**（`Authorization: CmuxV2`），LAN 直连，只信任配对时保存的 Bridge 自签 leaf 证书（DER SHA-256）。**不引入 HPKE**：`/v3/link` 的 HPKE 只用于 WebSocket 订阅，登记与资源请求在 HTTPS 上同样受签名保护。订阅（WebSocket）留到 A3。
- 密码学：BouncyCastle Ed25519；canonical JSON 与 Swift 逐字节一致（7 个向量测试），签名互相可验。
- 登记：`GET /v2/enrollment/bootstrap` → `POST /v2/enrollment/request` → 轮询 `status` → 校验 host 签名 grant → 保存。`clientKind = "android"`。
- 资源：`/v2/sessions`、`/v2/sessions/:id/history`、`/v2/sessions/:id/preview`、`send`、`interrupt`、`/v2/feed`、`/v2/feed/:request/reply`（含 `kind`）。
- 存储：`filesDir/connection/paired.json`（校验签名后才使用）与 `identity.key`；目录与文件权限仅本用户。
- 失败语义：不自动重试 POST；`outcome_unknown` 交回执查询；feed 读失败不阻塞会话列表。
- Bridge 改动：`ConnectionAuthority` 接受 `"android"` 这一 client kind；Mac 设备列表对 android 显示手机图标。

**A3 已接入（同日）**

- 链路（**已启用**）：`/v3/link` WebSocket + RFC 9180 authenticated HPKE，改用 **BouncyCastle 的 HPKE**（`bcprov-jdk18on` 自带 RFC 9180，含 auth 模式），与 CryptoKit 逐字节互通——用 CryptoKit 直接解开了 Kotlin 生成的包作为证据。手写的 HKDF 版本已删除。
- 修通过程中确认的三个协议细节，写进合同避免重犯：① `proposalDigest`/transcript 摘要算的是**整个签名信封** `{value, signature}`，不是内层 value；② Link 帧必须用 **WebSocket 二进制帧**发送，文本帧会被 Bridge 直接断开；③ `P256_SHA256_AES_GCM_256` 的 AEAD 0x0002 是 **AES-256-GCM（32 字节密钥）**。
- 订阅必须带自己的 `CmuxV2` 请求证明；事件只表示“资源变了”，客户端随即重读。
- 中转：relay origin + host 签名的 admission permit 已实现并校验；链路先拨 LAN，失败再拨 `wss://<origin>/v3/relay/<hostID>?role=client`（带 `X-Cmux-Relay-Permit` / `X-Cmux-Relay-Join`，join 用本设备密钥签名）。**中转下所有资源读取都走链路**（relay 只转发 `/v3/link`），响应按 64 KiB 分块并逐块 ACK。
- 旧 Bridge 兼容：登记若返回 `invalid_enrollment`（旧版只认 `iphone` / `mac`），用 `iphone` 种类重试一次；新 Bridge 仍登记为 `android`。
- 新鲜度：链路为主，前台轮询兜底（会话 15 秒、列表 30 秒），随页面取消。设备上实测：追加一条转录后 3 秒内出现在会话页。
- 图片：选择/发送（重编码为 JPEG，单张 ≤512 KiB、每边 ≤4096px、≤8MP），历史图片按 `reference_id + generation` 读取并按 512 KiB 上限校验。
- 项目：改动列表、diff、文件内容（只读、路径由 Bridge 约束）。
- 会话操作：模型菜单（读取 Mac 上的真实模型列表）、重命名、恢复会话、后台任务详情。
- 密钥：身份私钥改由 Android Keystore 的 AES-256-GCM 密钥包裹；旧版明文 key 会被收进 vault 后删除，身份不变。
- 新建会话：选工作区、目录（Bridge 返回的允许根）、Agent 与首条消息；`POST /v2/workspaces/:id/sessions` 后只等**新出现**的会话，不会误开旧会话。
- 后台任务：会话页显示正在跑的任务，点开读 `/v2/sessions/:id/tasks/:task_id`。
- 重连：前台期间列表每 12 秒、会话每 4 秒拉一次；页面关闭即取消，不自动重发写操作。

验证（本机模拟器 + 隔离 fixture，均未接触真实 cmux 或 Agent）：

- `PaneLayoutPolicyTest` 12 项、`CanonicalJsonTest` 7 项、`ProjectReaderTest` 9 项、`BridgeIntegrationTest` 5 项，共 33 项通过（另有 1 项发向量测试默认跳过）。
- `BridgeIntegrationTest` 走真实协议：登记 → 主人批准 → 会话 → 历史 → 发送 → 停止 → Feed 回答；加密链路握手并收到变更通知；另一个 key 的设备是独立 client。
- 设备上人工确认：配对成功进入双栏；打开会话读到历史；输入并发送后收到 fixture 回复；运行态显示停止按钮，点按后会话回到空闲；待处理卡片显示真实数量与标题，点开可回答。
- 设备上还验证过：真实图片预览、项目 diff、模型菜单读到 Mac 的模型列表、新建会话创建终端、链路推送 3 秒内到达、Bridge 重启后自动重连并继续收到更新。
- **真实环境验证（2026-10-31）**：本机已安装的 CmuxRemote resident（真实 cmux）→ 真实 Cloudflare relay（`relay.trentaml.com`）→ Android 模拟器。真实主人在 CLI 批准只读设备后，App 通过 `relayed=true` 的加密链路列出真实会话、订阅 `/v2/sessions` 与 `/v2/feed`，并读取了一个真实会话的完整历史（166 KB，分块 ACK）。批准范围仅读，因此没有在真实会话里发送或停止任何内容。
- 未验证：真机 Xiaomi 18 Fold 的折叠姿态（模拟器只能改窗口宽度）、Keystore 在真机上的 backing、写操作在真实 cmux 上的效果。

复现：

```sh
# 隔离 Bridge（不连 cmux）
swift build --product CmuxRemoteBridge
python3 scripts/build-enrollment-fixture.py
.build/enrollment-fixture <state-dir> 7799 --auto-approve 0

# Android 集成测试（fixture 的 enroll 码走 Gradle 属性，测试 JVM 才能读到）
cd android
./gradlew cleanTest testDebugUnitTest -PcmuxFixtureEnroll="<fixture 打印的 enroll=...>"
```



Android 先行第一版壳已经落地，iPhone Duo / iOS 代码未动：

- `android/`：Gradle 8.9 + AGP 8.7.3 + Kotlin 2.0.21 + Compose Material3，`minSdk 29` / `targetSdk 35`，单 Activity，edge-to-edge。
- `adaptive/PaneLayoutPolicy.kt`：共用布局规则；`adaptive/PaneLayoutPolicyTest.kt` 12 个 JVM 测试全部通过。
- `ui/AdaptiveRoot.kt`：Compact 单栏、TwoPane 双栏、ThreePane 支持面板、Tabletop 半开；示例数据，**尚未接 Bridge**。
- `ui/SessionListScreen.kt`：普通手机单栏；短横屏自动进入 dense 模式（紧凑待处理卡 + 单行 footer）。
- `ui/ConversationScreen.kt` / `ui/TabletopScreen.kt`：示例对话、工具卡、后台任务、审批卡、输入栏。
- 任务专用 AVD（带窗口运行，不使用用户已有 AVD）：
  - `cmux-remote-phone`：1080×2400 @420dpi → 411dp；竖屏 Compact 已验证。
  - `cmux-remote-fold`：1768×2208 @420dpi → 673dp；内屏 TwoPane 已验证。
  - 同一折叠 AVD 用 `wm size 2399×1079`（914×411dp）验证普通手机横屏仍为 Compact；用 `wm size 884×2208`（337dp）验证外屏 Compact。

验证命令：

```sh
cd android
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ./gradlew testDebugUnitTest assembleDebug
adb -s emulator-5558 install -r app/build/outputs/apk/debug/app-debug.apk
```

当前非目标：配对、协议、历史/发送/停止、真实 Bridge 连接、半开真机/FoldingFeature 注入。模拟器通过不等于真机或连接验收。

### 9.1 阶段与出口条件

| 阶段 | 内容 | 出口条件 | 预估 |
| --- | --- | --- | --- |
| **P0 协议合同** | `spec/`、黄金向量、一致性 runner、Bridge 接受 `android` kind、Mac 图标/文案 | Swift + Kotlin 对同一向量产出相同签名/摘要；隔离 Bridge 登记成功；无授权扩大 | 1–2 人周 |
| **A1 Android 壳（第一版已完成）** | Gradle 工程、Compose 主题、共用 `PaneLayoutPolicy`、普通手机 Compact、小米 18 Fold 双栏、tabletop、示例数据、单元测试、任务专用 AVD | 普通手机 411dp 竖屏、914×411 横屏单栏；折叠内屏 673dp 双栏；外屏 337dp 单栏；12 个 policy 单测通过；模拟器截图留证 | 已完成（2026-10-30） |
| **A2 Android 协议（第一版已完成）** | v2 登记、HTTPS + 请求证明、证书固定、列表/历史/预览、发送/停止、Feed 读取与回答 | 隔离 fixture 上完成配对→列表→读→发→停→回答；22 项测试通过；未接真实 cmux | 后续：HPKE 订阅、图片、Keystore、断线重连 |
| **P1 iOS Duo（暂缓）** | 窗口类、浏览器抽取、双栏、`ArrangementView`/`NavigationSplitView` spike、Device Hub | 等 Android 壳稳定后再启动；本轮不改 iOS | 4–5 人周 |
| **P3 功能对齐** | 模型切换、新会话/恢复、项目/diff、后台任务、工具详情、图片、重命名 | parity matrix 的 P3 项全部有真机证据 | 3–4 人周 |
| **P4 折叠屏打磨** | 外屏/内屏、铰链、tabletop、多窗口、键盘/拖放、可访问性 | 折叠屏真机验收清单；无内容绘制在铰链下；无关机/跳转 | 2–3 人周 |
| **P5 发布** | Play internal/closed、商店材料、隐私、截图、回滚 | Internal 测试通过；Data safety/隐私政策；版本号/签名可复现 | 1–2 人周 |

**并行关系**：P0 与 P1 可并行（P0 不改 UI）；P2 依赖 P0；P3 依赖 P2；P4 依赖 P2/P3；P5 依赖 P4。

**P2 内部先 spike 再铺功能**：第一周只做 Tink authenticated HPKE、OkHttp DER pin + HostnameVerifier、NsdManager 三件互操作实验，给出 go/no-go。若 authenticated HPKE 没有现成实现，后续功能估算按上限甚至延期；不要把“能编译”当成“能互通”。

### 9.2 测试矩阵

| 层级 | iOS | Android |
| --- | --- | --- |
| 单元 | Swift 包测试 + 手机模型检查 | JVM 单测 + 黄金向量 |
| 协议 | Swift conformance | Kotlin conformance（同一套向量） |
| 集成 | 隔离 Bridge fixture | 隔离 Bridge / Kotlin fake Bridge |
| UI | XCUITest（现有 23 个 + 新增自适应） | Compose UI + 截图 |
| 折叠/多窗口 | iPhone Duo Device Hub（外屏/内屏/半开/Split View）+ iPad 分屏/Stage Manager | AVD Pixel Fold + 小米 18 Fold 真机；`WindowLayoutInfoPublisherRule` |
| 安全 | 现有 + Android 专项 | Keystore/备份/导出组件/pin |
| 性能 | 大历史/滚动 | Macrobenchmark |

### 9.3 CI

- 现有 `.github/workflows/ci.yml` 是手动 **Package verification**；提交/合并/PR 不触发检查（`AGENTS.md`），保持这个纪律。
- 新增 Android job（手动触发）：
  - Ubuntu：JDK 17/21、Gradle wrapper、`lint`、JVM 单测、**纯 JVM 黄金向量**（不依赖 Bridge）。
  - macOS：iOS 构建 + iPad 模拟器 UI 测试（现有）+ **黑盒一致性**（Swift fixture + Kotlin JVM runner）。`scripts/fixtures/PhoneUIFixture.swift` 依赖 `CmuxRemoteBridge` / Darwin / SwiftNIO-SSL，Ubuntu 跑不了它。
  - 如果黑盒一致性必须在 Ubuntu 跑，Kotlin fake Bridge 必须成为 **P0 交付物**，不能按“可选”处理。
  - 模拟器：Ubuntu KVM 或 macOS arm64 runner 跑 Pixel Fold / tablet AVD；具体可用性**待核实**。
  - 系统镜像：当前只有 android-35 arm64。至少补 API 29 / 31 / 33 / 35（`dataExtractionRules` 31、predictive back 33/34 需要对应环境）。
- 不上传签名材料；密钥只从 CI secret / 私有目录读取。
- 本地验证顺序：`scripts/verify.sh`（Swift）→ `scripts/build-ios.sh`（UI 改动）→ Android `./gradlew check` + 仪器测试（仅用户明确要求或打包时）。

### 9.4 发布

- iOS：P1 完成后走现有 TestFlight 流程；iPad 截图和说明补齐；不改变现有 bundle id / 签名。
- Android：Play internal → closed → production；先小比例灰度；保留上一版可回滚。
- 版本号：两端独立；发布说明统一列出“协议版本 / 需要的最低 Bridge 版本”。
- 文档：README 增加 Android 安装/配对；`docs/PRIVACY.md` 增加 Android 数据说明；新增 `docs/ANDROID-RELEASE.md`（签名/打包/商店）。

---

### 9.0b iOS 对齐（2026-10-31 第二轮）

按 [iOS ↔ Android 对照](IOS-ANDROID-PARITY.md) 逐项补齐，已实现并纳入同一 APK：

- 布局：左抽屉（工作区树、边缘拖开、遮罩关闭）、搜索替换标题栏、排序（工作区/时间，持久化）、工作区与状态过滤、分组折叠（持久化）、下拉刷新。
- 多 Mac：保存多台、并行聚合、Mac 标签、单台移除。
- 渲染：Markdown（标题/列表/代码/表格/行内/链接）、活动分组与可展开工具卡、完整工具记录分页、会话内问题卡可回答、回复脚注（复制/分享/引用/选文）、选文页。
- 滚动：最新按钮、上拉加载更早（`before_seq`）。
- 状态：运行计时、回合用时页、待发送结果未知的持久化与回执查询。
- 输入：设备端语音听写（60 s / 8 KiB，永不回落网络识别）。
- 其他：CameraX + ML Kit 扫码；连接详情（身份/证书/能力/传输/密钥/移除）；诊断日志（500 条、脱敏、复制报告）；项目相对路径输入；Feed 待处理/全部切换、多模式决定、多问题表单与历史；中英双语资源。

验证：`android/` 单元测试 56 项通过（含新增的 Markdown 解析、诊断日志、多 Mac 合并、URI 签名编码测试）。

### 9.0c 第三轮：把“已完成”接通并补齐数据（2026-10-31）

逐项复核 [iOS ↔ Android 对照](IOS-ANDROID-PARITY.md) 时发现，上一轮登记的若干页面其实定义了
却没有渲染入口（工具记录、选文、时间、连接、诊断、添加 Mac）。本轮先接通这些页面，再补齐
Bridge 已经返回、客户端却丢掉的数据：

- 覆盖层导航：工具完整记录（字段切换与翻页）、选文、对话时间、连接详情、诊断日志、添加 Mac；
  各自有返回处理，可压在 Compact / 双栏 / 三栏 / Tabletop 之上。
- 时间线数据：`responses`、`recordedRunSeconds`、`recordedTurnCount`、`currentTurnStartedAt`、
  `agentModel` 解析并用于运行计时、回合用时、完成时间、时间页与头部模型。
- 会话操作：强制停止（确认）、模型切换 `model_confirm_required` 确认流程、当前模型标记。
- 输入与消息：长按菜单、发送中/未送达气泡、待发送结果未知横幅、图片草稿缩略图、图片文件选择、
  输入栏菜单（照片 / 图片文件 / 项目 / 待处理）、历史图片分享与重试。
- 工具与问题：工具卡输入输出、引用文件、终端退出码/耗时；会话内问题卡按提示词关联 Feed request。
- 配对：Android NSD 附近 Mac（TXT 身份校验、确认后从签名 bootstrap 登记）、原生登记 JSON 粘贴、
  添加 Mac 使用独立覆盖层，不再替换已连接列表。
- 列表与 Feed：Feed 全部事件切换真实可用；状态过滤与 iOS 一致；分组内新建；错误码本地化。
- 诊断：请求、登记、链路事件写入环形日志；路径中的标识改写为 `:id`，便于定位又不多留标识。
- 后台快照：启动/重连先显示后台同步保存的会话列表与待处理数量，成功读取后替换；列表 key 与会话选择改为 `hostID + session.id`。
- 本地会话缓存（对应 iOS `ConversationStore`）：`conversations.sqlite` 按 host + session 保存整段对话，
  新 generation 整段替换；24 个会话、单个 60,000 条消息 / 128 MiB、数据库 512 MiB；移除 Mac 同时清缓存。
- 对话更新：打开先显示已存整段；新读取按消息 id 就地更新、按 seq 合并；回复按首消息锚点合并；
  图片按 generation 失效；后台任务只由最新页决定；上翻优先读本地页，未命中才回网络；
  打开未读到底的会话时最多 64 页地异步补齐缓存，页面关闭即取消；实时写盘每 2 秒最多一次。
- 后台任务记录缓存（对应 iOS `BackgroundTaskCache`）：按 host + 设备身份 + session + task 保存最后一页，
  16 条 / 单条 4 MiB，读取算一次使用并按 LRU 淘汰；打开先显示缓存，读取后替换；移除 Mac 一并清理。

真实环境验证（2026-10-31 晚）：隔离 Bridge 连本机 cmux-tui daemon，真实 `enrollment open/approve` 只授权一个临时
workspace（含 `conversationStart`）。模拟器上由 App 新建会话并收到真实 Agent 回复；另建 156 条消息的长对话
（150 次工具调用），验证分组、工具卡、首次 100 条 + 上翻补页到 156 条、SQLite 冷启动离线恢复、generation
替换、单 Mac 离线时用缓存会话列表。测试中修复：Mac 失败时缓存列表消失、generation 变化后不回最新、顶部补页只触发一次。

验证：82 项 JVM 测试通过（新增发现 TXT 8 项、转录/缓存解码 7 项、合并逻辑 5 项、任务缓存 6 项）；任务专用手机与折叠 AVD 上人工回归
配对、双栏、连接详情、诊断、Feed 全事件、添加 Mac 返回、图片分享、长按、选文页、时间页。
附近设备发现未在真实局域网验收。

仍未完成：后台同步预取对话正文与任务记录、relay 目录与 origin 管理、真机折叠姿态与 Keystore、
DeX/多窗口、TalkBack 全量走查；深链、通知、TTS、触感维持不做或待定。

## 10. 风险与待核实

| 项 | 状态 | 处理 |
| --- | --- | --- |
| 在线资料 | 本版已通过 DeepSeek Search/Fetch 核对 Apple 官方规格/Tech Talk 与媒体发布信息 | 具体 SDK 签名、OEM 行为、商店政策仍需官方文档/真机确认；不要引用二手转述当合同 |
| 小米 18 Fold 规格 | 已发布（2026-09-07）；5.38"/7.58"、219g、HyperOS 4 六分屏等来自媒体 | 用真机采集 `WindowMetrics` / `FoldingFeature`；不写死型号；以小米官方规格为准 |
| iPhone Duo 规格 / 上市 | Apple 官方规格与 2026-10-23 开售信息已核对；媒体报告首批内屏/适配问题 | 用 Device Hub + 真机测折痕/半开/Split View；不要把模拟器通过当成真机通过 |
| Android API / 库版本 | 未锁定 | P2 开始前锁定 Kotlin/AGP/Compose/BOM/Tink/OkHttp 版本并记录 |
| Play 政策 / targetSdk 要求 | 未核对 | 发布前查 Play Console 最新要求 |
| iPhone Duo / iOS 27.1 API | Tech Talk 与第三方文章确认 `ArrangementView` / `onHingeChange` / `reservedRegions` 等概念；精确签名未在 SDK 头文件核对 | P1 安装 Xcode 27.1，以头文件/官方文档为准；保留 iOS 18 fallback |
| Android 后台限制 / HyperOS | 未实测 | 真机测试；文档只承诺 best-effort |
| Tink 是否支持 authenticated HPKE | 未核对 | P0 用黄金向量验证；不支持则换实现，禁止降级为 base 模式 |
| mDNS 在 Android / 企业 Wi-Fi | 未实测 | 保留 QR / v2 登记粘贴 / relay 兜底 |
| ML Kit 离线扫码 / F-Droid | 未核对 | 首版用 ML Kit；F-Droid 变体用 ZXing |
| 单一开发者产能 | 估算 | 阶段出口条件优先于日期；先做 P0/P1 |
| 两端 UI 漂移 | 结构性风险 | 设计 token 表 + parity matrix + 截图评审；不共享 UI 框架 |

**明确不做**：

- 不在 Android 上实现终端模拟器。
- 不连接 Claude/Codex provider API，不新建 Agent 运行时。
- 不修改已安装 cmux、不改变用户 socket 模式。
- 不把 Compose Multiplatform / Flutter 作为首版 UI 方案。
- 不承诺后台实时推送；不把 FCM 当作现有能力的替代。
- 不声称模拟器 / AVD 验收等于真机、铰链、相机、Keystore 验收。

---

## 11. 验收清单

### iOS 自适应

- [ ] iPhone 竖屏全部现有 UI 测试通过。
- [ ] iPad 全屏双栏；选择会话不 push 覆盖列表。
- [ ] iPad 分屏 / Stage Manager 从 320 到 1366 宽连续缩放；iPhone Duo Device Hub 的外屏/内屏/半开/Split View；选择/草稿/滚动保持。
- [ ] `>= 1100` 且详情可用宽 `>= 480` 时支持面板；项目/Feed/图片/工具详情进入/退出路径正确。
- [ ] 折叠/旋转时运行中的回复不跳走；展开卡片不被重置。
- [ ] 键盘、动态字体 200%、VoiceOver、英文/简体中文截图。
- [ ] 无内容绘制在铰链/安全区下（Android 折叠屏）；iOS 无假铰链。

### Android

- [ ] 扫码 → 主人批准 → 列表 → 历史 → 发送 → 停止 → Feed 回复，全程真机。
- [ ] 证书 pin 错误、主机身份变化、撤销、重放、路径穿越、outcome unknown 全部 fail closed。
- [ ] 冷启动 / 进程死亡 / 网络切换 / 后台回来：不重复写、不回放旧订阅、不丢账本。
- [ ] 外屏/内屏折叠、tabletop、旋转、分屏/多窗口：布局与输入区正确。
- [ ] 键盘、TalkBack、fontScale 200%、大屏截图。
- [ ] Keystore 不可用/重置、备份恢复、导出组件扫描。
- [ ] 无分析 SDK、无明文、无凭据进日志。

### 协议

- [ ] Swift 与 Kotlin 对同一组黄金向量产出相同字节/签名/Authorization。
- [ ] 双方都能完成登记、连接、读取、发送、停止、订阅、撤销。
- [ ] `spec/` 与实现同步；新增路由/错误码必须同时更新 schema、向量、两端测试。
- [ ] Bridge 只增加 `android` client kind，没有新增权限或绕过检查。

---

## 附录 A：关键文件索引

| 主题 | 文件 |
| --- | --- |
| 产品/权限边界 | `AGENTS.md`、`docs/DESIGN.md` |
| 连接 v2 | `docs/CONNECTION-V2.md`、`Sources/CmuxRemoteCore/Connection/*` |
| WebSocket v3 / relay | `docs/WEBSOCKET-RELAY.md`、`Sources/CmuxRemoteCore/Link/*`、`Sources/CmuxRemoteClient/LinkClientConnection.swift` |
| API 路由 | `docs/API.md` |
| iOS 设计系统 | `docs/IOS-DESIGN-SYSTEM.md`、`ios/Sources/MobileDesign.swift` |
| iOS 根/导航 | `ios/Sources/CmuxRemoteApp.swift`、`SessionListView.swift`、`AppNavigationStack.swift`、`SideDrawer.swift` |
| iOS 会话 | `ios/Sources/ConversationView.swift`、`ConversationModel.swift`、`ChatComposer.swift` |
| 证书 pin | `Sources/CmuxRemoteClient/PinnedSessionDelegate.swift` |
| 请求签名 | `Sources/CmuxRemoteClient/RemoteClientRuntime.swift`、`Sources/CmuxRemoteCore/Connection/IdentityCryptography.swift` |
| HPKE | `Sources/CmuxRemoteCore/Link/LinkCipher.swift`、`LinkClientHandshake.swift` |
| client kind 白名单 | `Sources/CmuxRemoteBridge/ConnectionAuthority.swift:204` |
| Mac 设备图标 | `mac/Companion/DevicesSettingsView.swift:100,105` |
| UI fixture | `scripts/fixtures/PhoneUIFixture.swift`、`scripts/build-phone-ui-fixture.py` |
| 测试脚本 | `scripts/verify.sh`、`scripts/build-ios.sh`、`scripts/test-ios-navigation.sh` |
| 发布 | `docs/TESTFLIGHT.md`、`docs/MAC-RELEASE.md`、`.github/workflows/*` |

## 附录 B：联网后需要核对的外部资料

1. Android 官方：adaptive layouts、window size classes、`FoldingFeature`、`ListDetailPaneScaffold` / `SupportingPaneScaffold`、predictive back、edge-to-edge。
2. Android 官方：Keystore / StrongBox 对 Ed25519 的支持现状；Tink HPKE API 与版本。
3. OkHttp WebSocket、`X509TrustManager`、`CertificatePinner` 的 SPKI 语义。
4. Android `NsdManager` 在 Android 12+ / 企业 Wi-Fi 的行为与权限。
5. CameraX + ML Kit barcode 离线模型；ZXing 替代方案。
6. Play Console：targetSdk 要求、Data safety、大屏/折叠屏截图规范。
7. Apple：iPhone Duo 技术规格、Tech Talk "Prepare your app for iPhone Duo"、`ArrangementView` / `onHingeChange` / `reservedRegions` / `toolbarVerticalEdge` 的 SDK 头文件与官方文档；iPad Stage Manager / 多窗口。
8. 小米：小米 18 Fold 官方规格页、澎湃 OS 4 分屏/小窗/应用连续性文档；Pixel Fold / Galaxy Z Fold / OnePlus Open 的实测数据。
9. Cloudflare Workers / Durable Objects 当前限制与价格（relay 不变，但发布说明需核对）。
