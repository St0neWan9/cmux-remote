# Cmux Remote 宣传网站

独立静态 HTML / CSS / JavaScript 网站，使用 Bento Quiet 暖中性背景与蓝色强调，可部署到 Cloudflare Workers Static Assets。

## 页面

- `/`：新版英文首页，默认英文。
- `/zh/`：新版中文首页。
- `/design-system.html`、`/zh/design-system.html`：共享产品设计系统预览。
- 其他路径保留真实 404 状态。

网站现已统一使用 Agent 图形客户端的新内容，不再保留旧版落地页、独立 v2 资源或兼容跳转；`/v2` 路径返回 404。中英文覆盖首屏、功能演示、任务管理、官方比较、连接、安装、开源、FAQ、菜单与无障碍名称。语言切换保留当前锚点和显式语言选择。

## 本地运行与构建

要求 Node.js 22+。首次运行 `npm ci`，随后：

```sh
npm run dev
```

本地 Worker 默认在 `http://localhost:8787`。修改源文件后运行 `npm run build` 更新静态文件。

构建只复制公开资源到 `dist/`，并为 CSS 和 JavaScript 添加内容版本。文档、截图、依赖与本地配置不会发布。设计令牌唯一来源为仓库根目录的 `design/tokens.json`，更新后运行 `python3 scripts/export-design-tokens.py`，不要手工编辑 `tokens.css`。

## Cloudflare 发布

正式域名：`cmux-remote.trentaml.com`；Worker：`cmux-remote-website`。`wrangler.jsonc` 固定到拥有 `trentaml.com` 的账号，只绑定此子域名。部署凭证使用本机 Wrangler 登录，不写入仓库。

```sh
npm run deploy:dry-run
npm run deploy
```

Cloudflare 自动创建 Custom Domain 的 DNS 记录及 HTTPS 证书。重复发布沿用同一个 Worker。独立目录可整体复制部署，不依赖 Codex Sites、ChatGPT 登录或原生应用构建。

## 视频与界面示意

`videos.json` 中的 `workflow` 是完整开发流程的视频位置。当前明确显示“演示待补充”，无虚假播放按钮。素材放到 `media/` 并填写 `src`，可选填写 `poster` 和中文 WebVTT `captions`。加载失败恢复占位。

设备与会话均为 HTML 示意，非真实截图或实时数据；Mac / iPhone 同框宽度比保持约 4.366:1。需要大号手机内容时使用独立的会话细节组件。

## 验证

新版已完成静态构建、部署 dry-run、中英文 320 / 375 / 390 / 820 / 1440px 布局与横向溢出检查、手机页头对齐、Tabs 点击与键盘切换、保留锚点的语言切换、FAQ 展开，以及元数据、可访问名称、唯一 ID 和内部锚点核对。独立仓库不包含上游 cmux 的 `scripts/localize-changes`，因此直接审计双语静态页面和浏览器交互。原生 App 功能与真实视频播放不属于网站验证。
