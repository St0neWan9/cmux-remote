# 完整开发流程录制

`workflow-en.mp4` / `workflow-zh.mp4`（约 55 秒，1920 × 1080，无声）是同一次真实运行的两种语言版本，只有标题和步骤文字不同。封面为同名 `.jpg`。

流程：手机交代任务 → Agent 在 Mac 上修改代码并跑测试 → 手机查看测试输出、编辑 Diff 与 `git diff` → 手机发送下一步要求，Agent 完成并汇报。

录制方式：

- Mac 端是 cmux-tui 中真实运行的 Claude Code。按时间戳读取终端状态（`terminal … state read`），逐帧还原成画面，不是手绘示意。
- iPhone 端是 iOS 模拟器里的 Cmux Remote，连接本机隔离的 Bridge（只授权演示工作区），用 `simctl io recordVideo` 分段录制，每段都用截图校验时间轴。
- 演示项目在 `/Users/Shared/storefront`。测试和编辑命令预先放行，所以视频里没有授权卡片。
- Agent 等待的部分以 3 倍速播放，画面里标有「3× 加速」；其余部分为原速。标题、步骤条和配色来自 `design/tokens.json`。
- 手机界面语言为简体中文，英文版只翻译了视频外围的说明文字。

在 `website/videos.json` 的 `workflow` 下按页面语言配置 `en` / `zh`，每项包含 `src`，可选 `poster` 和 WebVTT `captions`；也可以直接配置单个 `src`，供两种语言共用。修改后重新构建。未配置时保留明确占位；界面示例不得冒充实际运行结果。

构建只发布允许的视频、图片和字幕扩展名，README 不会作为网站资源上传。
