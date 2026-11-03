# cmux-remote 宣传网站设计参考

调研日期：2026-10-14。网站工作分支：`codex/marketing-site`，从 `origin/main` 的 `0d455f8` 创建。

## 产品定位

建议主标题：**离开 Mac，继续你的 AI 编程会话。**

cmux-remote 是独立的 Mac companion 和原生 iPhone 应用。宣传重点来自当前仓库 [README](../README.md)、[连接协议](../docs/CONNECTION-V2.md) 和 [iOS 设计系统](../docs/IOS-DESIGN-SYSTEM.md)：

- 在 iPhone 上阅读已有 Claude/Codex 会话与实时文字预览。
- 向已绑定的运行中会话发送提示、停止工作，回复受支持的待处理审批。
- 查看项目文件与 Git 差异。
- 扫码配对、Mac 批准设备、指定工作区与查看/控制权限，按设备撤销访问。
- 继续使用 cmux 中已有的 Agent，无需重新连接模型 API，也不依赖 cmux cloud 账号。

网站展示应保留手机的真实白色界面、蓝色主按钮和原生导航。首屏用 Mac 与 iPhone 的会话对应关系解释产品，正文用实际阅读、发送、查看差异的场景展开。

公网中转与 Mac 镜像须按实际发布和验收状态标注，不能仅凭设计文档当作稳定能力。当前 [WebSocket/relay 文档](../docs/WEBSOCKET-RELAY.md) 标记公网部署与完整验收未完成；下载入口应在实现时核对 Releases/TestFlight 的可用状态。页脚应注明独立项目身份。

## 5 个 DESIGN.md 参考

以下文件来自 [VoltAgent/awesome-design-md](https://github.com/VoltAgent/awesome-design-md)，是社区对品牌网站的设计分析，适合作为灵感，并非品牌官方规范。颜色和尺寸来自这些分析文件，后续应转换成 cmux-remote 自己的设计令牌。

| 参考 | 分析文件的视觉要点 | 适合 cmux-remote 的用法 | 取舍 |
| --- | --- | --- | --- |
| [Apple DESIGN.md](https://github.com/VoltAgent/awesome-design-md/blob/main/design-md/apple/DESIGN.md) | 白色与 `#f5f5f7`，蓝色 `#0066cc`，系统字体，大幅产品展示 | 首屏 iPhone/Mac 组合、真实手机操作图、轻量下载入口 | 最贴合现有 iOS 界面；需用具体会话内容说明价值 |
| [Raycast DESIGN.md](https://github.com/VoltAgent/awesome-design-md/blob/main/design-md/raycast/DESIGN.md) | 近黑 `#07080a`，细描边，Inter，白色主按钮，产品界面主导 | 深色 Mac 背景中展示白色 iPhone 会话，突出效率与原生工具感 | 视觉记忆更强；红色条纹属于 Raycast，应换成自己的表达 |
| [Linear DESIGN.md](https://github.com/VoltAgent/awesome-design-md/blob/main/design-md/linear.app/DESIGN.md) | 近黑 `#010102`，炭灰分层，单一紫蓝 `#5e6ad2`，克制排版 | 解释会话、工作区、状态与权限，适合精确的功能叙事 | 很适合开发者产品；白色手机画面需要保持明显的视觉层次 |
| [Warp DESIGN.md](https://github.com/VoltAgent/awesome-design-md/blob/main/design-md/warp/DESIGN.md) | 暖炭色 `#2b2622`、米白，Inter/DM Mono，少量衬线，紧凑形状 | Mac 侧终端与 Agent 工作过程、安装步骤、技术细节区域 | 工具属性鲜明；首屏仍应展示结构化手机会话 |
| [Vercel DESIGN.md](https://github.com/VoltAgent/awesome-design-md/blob/main/design-md/vercel/DESIGN.md) | 白底黑字，细网格，Geist/Geist Mono，技术标签 | 三步配对、连接拓扑、开源说明和权限范围 | 信息表达清晰；手机产品的亲和感需要通过截图补足 |

## 第二批：不同气质的设计系统

这些仍是第三方对公开网站的设计分析，不是品牌官方规范。Things 和 Tailscale 的参考页提供预览和 DESIGN.md 下载；其余链接直接指向 Markdown 文件。下列适配建议是针对 cmux-remote 的设计判断。

| 参考 | 视觉语言 | 对 cmux-remote 的适配建议 |
| --- | --- | --- |
| [Things：预览与 DESIGN.md](https://www.shadcn.io/design/things) | 冷调浅灰白 `#f2f5f7`、蓝色 `#2576eb`、系统字体、原生窗口圆角；设备截图承担视觉表现 | 用 Mac 和 iPhone 的实际画面说明同一会话如何延续，适合聚焦单个原生应用的宣传页 |
| [Tailscale：预览与 DESIGN.md](https://www.webdesignhot.com/design.md/tailscale/) | 暖白 `#f9f7f6`、砖红 `#d04841`、Inter，亲切而清晰的技术表达 | 重点参考连接步骤、设备关系与权限的表达；帮助普通用户理解配对与控制范围。公网访问文案仍须按发布状态核对 |
| [Mercury DESIGN.md](https://github.com/VoltAgent/awesome-design-md/blob/main/design-md/mercury/DESIGN.md) | 墨紫 `#171721` 与近白 `#fbfcfd`，靛蓝 `#5266eb`，轻字重与柔和卡片 | 深色首屏展示白色手机会话，后续切换浅色功能区域；适合精致、安静的产品方向 |
| [Resend DESIGN.md](https://github.com/VoltAgent/awesome-design-md/blob/main/design-md/resend/DESIGN.md) | 黑底、白字、大型衬线标题、细描边与低强度光晕 | 借助强排版和少量产品画面营造质感；适合简短价值主张与清晰的下载动作 |
| [Ollama DESIGN.md](https://github.com/VoltAgent/awesome-design-md/blob/main/design-md/ollama/DESIGN.md) | 白底、黑色胶囊按钮、中性灰、安装片段和简洁吉祥物 | 适合开源工具气质：一句说明、手机预览、安装步骤、GitHub 入口。手机画面需要足够大，避免功能价值被安装说明盖过 |
| [PostHog DESIGN.md](https://github.com/VoltAgent/awesome-design-md/blob/main/design-md/posthog/DESIGN.md) | 灰奶油底 `#eeefe9`、黄橙 `#f7a501`、IBM Plex Sans、小圆角和手绘插画 | 用自己的角色与场景插画表达离开桌面后查看回复、继续对话的体验，适合更有趣的开发者社区品牌 |
| [Claude DESIGN.md](https://github.com/VoltAgent/awesome-design-md/blob/main/design-md/claude/DESIGN.md) | 暖白 `#faf9f5`、陶土 `#cc785c`、衬线大标题与深色产品展示 | 适合围绕“继续对话”的叙事；应保留自己的品牌，并让 Claude/Codex 两种会话获得同等展示 |

### 第二批优先选择

- **原生应用路线：Things。** 重点在设备与真实界面，比大型平台式页面更适合这个 companion 产品。
- **连接与信任路线：Tailscale。** 把配对与授权讲得轻松、直观，弱化协议细节。
- **柔和精致路线：Mercury。** 使用墨紫、近白和轻字重形成自己的视觉识别。

Things 可以作为新的首选整体方向，Tailscale 作为连接与权限区域的叙事参考。若更看重视觉个性，可以选择 Mercury 或 PostHog。

## 第三批：扩展到独立来源与官方系统

前两批过度依赖 VoltAgent 的品牌分析文件。本批按来源区分风格库、网站分析、布局模式和官方营销系统；它们提供的参考不同，不能都当成现成的完整 DESIGN.md。

| 来源 | 实际提供什么 | 本次具体候选与用途 |
| --- | --- | --- |
| [albemala/design-md-library](https://github.com/albemala/design-md-library) | 独立维护的具名 DESIGN.md 风格系统 | [Forma](https://github.com/albemala/design-md-library/blob/main/design-md/saas-landing/DESIGN.md)：暖白、深绿、DM Sans 轻字重与 DM Mono 标签，适合产品宣传页；[Focus Utility](https://github.com/albemala/design-md-library/blob/main/design-md/utility-app/DESIGN.md)：暖中性色、黑色组件、少量蓝色，适合功能示意；[Agency Landing](https://github.com/albemala/design-md-library/blob/main/design-md/agency-landing/DESIGN.md)：奶油纸色、大衬线标题、直角与金色点缀，适合更强的编辑式视觉 |
| [Refero Styles](https://styles.refero.design/) | 带预览、DESIGN.md、CSS 变量与令牌的网站风格分析 | [teenage engineering 分析](https://styles.refero.design/style/aecf9dda-5cba-4dc7-9e73-59b65d895cdf)：浅灰白、直角、细线、产品主导的工业设计气质；可以借鉴大幅设备展示与精确标签，但手机界面与中文正文仍要保持可读的字重 |
| [FreeDesignMD](https://freedesignmd.com/) | 可下载 Markdown 的视觉系统，以及独立布局模式 | [Bento Quiet](https://freedesignmd.com/pattern/bento-quiet)：统一圆角、描边和表面色的 12 列布局；适合把会话预览、差异查看和配对展示成尺寸不同的功能模块。它是布局模式，不是完整品牌系统 |
| [Mozilla Protocol](https://protocol.mozilla.org/) | Mozilla/Firefox 网站的官方设计系统，含代码组件、排版、令牌、内容与可访问性规则 | 官网提供 Hero、Download Button、Feature Card 等宣传组件，适合参考软件下载、功能介绍与上手页面的结构；不是现成 DESIGN.md |
| [GitHub Primer Brand](https://primer.style/brand/) | GitHub 官方营销网站和数字体验设计系统 | 适合开发者产品的宣传页结构、组件和主题；应采用 cmux-remote 自己的品牌与文案，不是现成 DESIGN.md |
| [catrinmdonnelly/DESIGN.md](https://github.com/catrinmdonnelly/DESIGN.md) | 用来定义自己品牌令牌与设计约束的 Markdown 模板 | 适合在选定方向后整理 cmux-remote 自己的规范；它不是可直接挑选的视觉风格库 |

### 不依赖前两批品牌分析的候选方向

1. **Forma + Bento Quiet**：暖白与深绿，轻字重标题，功能区域采用尺寸有变化但样式一致的模块。适合清晰、安静的产品介绍。
2. **工业产品展示方向**：参考 Refero 的 teenage engineering 分析，用直角、细线和大幅 Mac/iPhone 画面形成识别；正文保持常规可读字重。
3. **编辑式产品故事方向**：参考 Agency Landing 的奶油纸色与衬线标题，突出从桌面到手机继续工作的场景；减少原模板的巨大标题尺寸，给产品画面留空间。

这些组合是针对 cmux-remote 的设计建议，尚未构成最终选定的视觉系统。

## 可选择的整体方向

### A：Apple 为主，Vercel 辅助（首选）

白色和浅灰页面、黑色大标题、蓝色行动按钮。首屏放 Mac 与 iPhone 的组合图，手机画面占主要位置。功能段落保留充足留白；配对和权限区域采用清晰的步骤与细线结构。

与当前手机界面一致，适合让访问者迅速理解“把 Mac 上的 AI 会话带到手机”。

### B：Raycast 为主，Linear 辅助

深色画布、白色主按钮、细描边。白色手机界面成为首屏焦点，Mac 界面在后方提供上下文。会话状态和功能区使用紧凑但清晰的文字层级。

适合更强调开发者工具、效率和产品质感的定位。

### C：Warp 为主

暖炭色与米白，安装命令和技术标签使用等宽字体。首屏同时展示 Agent 在 Mac 工作和用户在手机继续对话，后续讲解配对、控制与差异查看。

适合偏技术受众、开源社区和终端使用场景的定位。

## 建议页面顺序

1. 首屏：一句价值主张、Mac/iPhone 产品展示、下载与源码入口。
2. 场景：查看回复 → 发送下一步 → 检查文件差异。
3. 连续性：同一个已有 Agent，会话继续留在 Mac。
4. 上手：启动 Bridge → 扫码 → 在 Mac 批准。
5. 权限：指定工作区、查看或控制、按设备撤销。
6. 下载、系统要求、FAQ 和独立项目说明。

本轮仅完成设计调研；尚未选定最终网站设计系统或实现页面。
