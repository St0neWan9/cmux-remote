# 两台 Mac 局域网镜像测试：这台作远端，另一台作客户端

本轮只测试 Mac Companion、Bridge 和原生 cmux workspace 镜像，不测试移动端。

## 先看这四点

- **A（远端）**：当前这台 Valuz-Studio，由我准备并保持服务运行。
- **B（客户端）**：你要去操作的另一台 Mac，下面标注 B 的步骤都在那里执行。
- B 不需要 SSH 登录 A；在可互通的局域网中，通过 Bonjour 发现和 HTTPS 连接。
- 首次连接需要 A 批准一次。你可以把请求 ID 发给我批准，也可以回到 A 执行本文的批准命令。批准后，正常重启不需要重新配对。

## 当前 A 的连接信息

这些值在 2026-10-12 实际启动并验证；A 换网络后 IP 可能变化，届时以重新确认的值为准。

| 项目 | 值 |
| --- | --- |
| A 的官方 cmux 版本 | `0.65.0`（build `108`） |
| 发现列表中的名称 | **cmux Alpha Remote** |
| Bridge HTTPS 地址 | `https://10.20.0.59:7780` |
| 安装包下载地址 | `http://10.20.0.59:7781/mac-alpha-candidate-20261012.zip` |
| 本文下载地址 | `http://10.20.0.59:7781/LAN-ALPHA-TEST.zh-CN.md` |
| 测试 workspace 名称 | **cmux Remote source acceptance** |
| 测试 workspace UUID | `a759d3d3-52e6-481d-a466-94cc44dbf52b` |
| Host ID | `2792ede6c5052cb0e0d608914b24d5b870db89dd1cffca20ac39ae2300d1eac9` |
| TLS 证书 SHA-256 | `a1c640be046c15941a8f95f9a1e7c64df764f7139441bdf5b72b72b973af6cd1` |
| 安装包 SHA-256 | `e68d87d708ee85c9fc2a85dfefc5d409857a7a9d5d53b1d0ccbcf28dc92a8e6a` |

7781 只提供安装包和文档；连接与终端数据走 7780 的 HTTPS。
下载目录不包含 Bridge 身份私钥、授权状态或 cmux 数据。临时下载服务与
远端 Bridge 都由 A 的专用测试终端保持运行。不要关闭该终端。

## 1. B：确认环境和网络

本次冻结包是 **Apple Silicon / arm64** 的 ad-hoc Debug 包，无需 Xcode 编译。
B 需要 macOS 14.0 或更新版本，已经安装官方 cmux，并使用 Default Workspaces 侧栏。

在 B 的终端执行：

```sh
uname -m
nc -vz 10.20.0.59 7780
nc -vz 10.20.0.59 7781
```

预期：架构为 `arm64`，两个端口都能连接。如果是 `x86_64`，先停止安装，
需要另做 Intel 包。如果端口不通，先检查 A 是否仍在运行、两机是否在可互通的
网络中；来宾 Wi-Fi、客户端隔离或防火墙可能阻止连接。
不要通过关闭系统安全保护解决问题。

## 2. B：下载、校验、安装冻结候选

```sh
mkdir -p "$HOME/cmux-alpha"
cd "$HOME/cmux-alpha"
curl --fail --show-error --output cmux-alpha.zip \
  http://10.20.0.59:7781/mac-alpha-candidate-20261012.zip
printf '%s  %s\n' \
  'e68d87d708ee85c9fc2a85dfefc5d409857a7a9d5d53b1d0ccbcf28dc92a8e6a' \
  'cmux-alpha.zip' | shasum -a 256 -c -
ditto -x -k cmux-alpha.zip .
codesign --verify --deep --strict \
  "$HOME/cmux-alpha/candidate-20261012/CmuxRemoteMac.app"
```

预期：校验输出 `cmux-alpha.zip: OK`，签名验证成功。校验失败就不要安装。
A 已实际验证过这份 ZIP 的 `ditto` 解压、签名和 CLI 执行。

若 B 已运行以前的 **cmux Remote Companion**，先退出 Companion。
下面只备份/安装该项目的 Companion，**不要退出或替换官方 cmux**：

```sh
bash <<'INSTALL'
set -eu
mkdir -p "$HOME/Applications" "$HOME/.local/bin"
if [ -e "$HOME/Applications/CmuxRemoteMac.app" ]; then
  alpha_installed_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
    "$HOME/Applications/CmuxRemoteMac.app/Contents/Info.plist")
  if [ "$alpha_installed_id" != 'cmux-remote.desktop' ]; then
    echo '目标位置不是本项目的 Companion，已停止安装' >&2
    exit 1
  fi
  mv "$HOME/Applications/CmuxRemoteMac.app" \
    "$HOME/Applications/CmuxRemoteMac.backup-$(date +%Y%m%d-%H%M%S).app"
fi
ditto "$HOME/cmux-alpha/candidate-20261012/CmuxRemoteMac.app" \
  "$HOME/Applications/CmuxRemoteMac.app"
cp "$HOME/cmux-alpha/candidate-20261012/cmux-remote" \
  "$HOME/.local/bin/cmux-remote-alpha"
chmod +x "$HOME/.local/bin/cmux-remote-alpha"
INSTALL
```

本版本不使用替换侧栏的 ExtensionKit 扩展，不需要开启 Extensions beta。
这是本地测试包，尚未做 Developer ID 公证；若 macOS 阻止打开，记录原始提示，
不要执行关闭 Gatekeeper 或移除安全检查的命令。

## 3. B：在官方 cmux 里启动本地 Bridge

在 B 的官方 cmux 中新建一个普通本地 workspace，命名为 **Remote Bridge**。
在它的终端执行初始化（已有状态则保留），然后启动服务：

```sh
if [ ! -f "$HOME/.local/state/cmux-remote/token" ]; then
  "$HOME/.local/bin/cmux-remote-alpha" init
fi
"$HOME/.local/bin/cmux-remote-alpha" serve --port 7782
```

预期：显示 `cmux-remote listening on https://127.0.0.1:7782`，进程保持前台运行。
B 只监听本机。保留默认 Bonjour 发现，才能在 Companion 中发现 A。
当前 `--no-discovery` 同时关闭广播和附近主机发现，本轮不要添加该选项。
必须在 cmux 内启动，以符合 `cmuxOnly` 的进程来源检查。

Companion 固定读取 B 的默认 `~/.local/state/cmux-remote/owner.sock`。
**本步骤不要添加另一条 `--state` 路径**，否则 Companion 找不到你的 Bridge。
若报 `already_running`，已有 Bridge 占用默认状态：先确认已有服务版本与归属，
不要启动第二份或删除状态。7782 若被别的程序占用，可换一个空闲端口，仍保留默认状态目录。

保留这个终端，另开一个 B 的 cmux 终端执行：

```sh
open "$HOME/Applications/CmuxRemoteMac.app"
```

## 4. A：临近配对时打开 10 分钟窗口

到这一步你可以在聊天里说 **“B 已就绪，请开配对”**，我在 A 执行。
窗口最长 600 秒，不能把早先测试时开的窗口当作仍有效。
如果你自己回 A 操作，命令是：

```sh
"$HOME/.local/share/cmux-remote-alpha/cmux-remote" enrollment open \
  --state "$HOME/.local/state/cmux-remote-alpha-source" \
  --host 10.20.0.59 --port 7780 --seconds 600 \
  --workspace a759d3d3-52e6-481d-a466-94cc44dbf52b --format json
```

仅开放专用测试 workspace，不授权其他已有工作区。

## 5. B：发现 A、核对身份并申请连接

1. Companion 的 Nearby Bridges 列表中选择 **cmux Alpha Remote**。
2. 弹出的确认窗口中，核对名称及 TLS 指纹是否与本文完全一致，然后点击信任。
3. 页面应显示等待远端批准及本次 **request ID**。记录该 ID。
4. 把 request ID 发给我批准；或按下一节在 A 自己批准。

附近没有设备时先点 Refresh。B 同时可以执行：

```sh
"$HOME/.local/bin/cmux-remote-alpha" discover
```

应看到本文的 Host ID。当前首次连接需要 Bonjour 发现；IP/端口可达不代表
Bonjour 一定可用，也不能保证输入 IP 就能绕过发现。若刷新后仍为空，检查两机
是否允许 mDNS/UDP 5353，记录结果给我，不要反复重新初始化身份。

如果你偏好 CLI，可在 B 用同一发现结果发起申请（与 UI 二选一，不同时新建两次）：

```sh
"$HOME/.local/bin/cmux-remote-alpha" connect \
  2792ede6c5052cb0e0d608914b24d5b870db89dd1cffca20ac39ae2300d1eac9 \
  --trust-certificate a1c640be046c15941a8f95f9a1e7c64df764f7139441bdf5b72b72b973af6cd1 \
  --name 'Mac-B Alpha test'
```

## 6. A：批准 B 的这一条请求

由我代做时，你只需提供上一节的 request ID。自己操作时，先在 **A** 查看：

```sh
"$HOME/.local/share/cmux-remote-alpha/cmux-remote" enrollment pending \
  --state "$HOME/.local/state/cmux-remote-alpha-source"
```

确认 request ID、clientName、clientKind=mac、workspace 都匹配 B；
下面把 `REQUEST_ID_FROM_B` 换成真实 ID，**这条命令只能在 A 执行**：

```sh
"$HOME/.local/share/cmux-remote-alpha/cmux-remote" enrollment approve REQUEST_ID_FROM_B \
  --state "$HOME/.local/state/cmux-remote-alpha-source" \
  --workspace a759d3d3-52e6-481d-a466-94cc44dbf52b \
  --capability workspaceRead --capability terminalRead --capability terminalInput
```

预期：`approved: true`。B 的 UI 随后出现工作区。
CLI 申请则在 B 执行 `cmux-remote-alpha connect status` 完成批准状态读取，
之后打开 Companion 选择 Saved connections 中的 A。
批准后可在 A 执行 `enrollment close --state ...` 关闭新申请窗口，已有授权保留。

## 7. B：镜像并验证核心功能

Companion 中选中 A，找到 **cmux Remote source acceptance**，点击 **Mirror here**。

预期：官方 cmux 的本机列表保持原样，下面增加原生 **Remote** 分组。
该 workspace 的本地镜像名为 **cmux Alpha Remote · cmux Remote source acceptance**。
本次源端是嵌套的三个 pane、共六个 terminal tab，包含 Source One、Source Two、
Alternate-screen TUI、Hidden echo 和两个 Dynamic source。比例可以不同，标签和分屏结构应一致。

| 测试 | 在 B 操作 | 预期结果 |
| --- | --- | --- |
| 实时输出 | 查看 Alternate-screen TUI | `frame=` 数字持续变化，`source_pid=88560`；字符、颜色和中文可见，无持续清屏闪烁 |
| 输入回传 | 在 Source One 输入 `MAC_B_ALPHA_001` 并回车 | 出现 `SOURCE_RECEIVED MAC_B_ALPHA_001`；消息来自 A 的原进程 |
| 隐藏 tab | 切到 Hidden echo，输入 `MAC_B_HIDDEN_001` 回车 | 看到该测试程序的收到提示；不要在 TUI 输入 `q`，它会退出该测试程序 |
| 切换焦点 | 在本机 workspace 和 Remote 镜像之间切换，再查看源端反馈 | 没有自动注入奇怪字符，实时画面恢复显示 |
| 重复打开 | 再次点击同一 workspace 的 Mirror here | 打开原有镜像，B 不新增第二个相同工作区 |
| 查看状态 | 在 B 另一个终端运行下面三条命令 | 目标镜像有 6 个绑定，状态为 `watching`，workspace ID 保持一致 |

```sh
"$HOME/.local/bin/cmux-remote-alpha" mirror catalog
"$HOME/.local/bin/cmux-remote-alpha" mirror list
"$HOME/.local/bin/cmux-remote-alpha" mirror status
```

开始这轮测试的是受控普通终端和 TUI，**它们不是 Claude/Codex 会话**。
真实 Agent 验收是后续单独一步：先确认 A 上的具体已有 Claude/Codex workspace，
单独授权，然后测试一条受控输入、输出、打断和退出；不重新启动 Agent，
也不把“测试终端通过”写成“真实 Agent 已通过”。

## 8. B：重启与断线恢复

按以下顺序做，每步后保存截图及 `mirror status` 结果：

1. 只退出 Companion，再打开，选 Saved connections 中的 A。应无需再次配对；
   点击 Mirror here 回到相同镜像。
2. 只在 B 的 **Remote Bridge** 终端按 Ctrl-C 停止本地 Bridge，然后再次执行
   第 3 节的 `serve` 命令。A 的终端不受影响；B 的既有镜像应恢复，状态回到 `watching`。
3. 远端 Bridge 断线由我在 A 触发，你在 B 观察。告诉我 **“开始远端断线测试”**；
   应保留旧画面，恢复后 TUI 的 `frame=` 继续变化，原 `source_pid` 不变。
4. 最后在某个镜像 viewer 按 **Ctrl-]**，应只退出本地 viewer，A 的源进程继续运行。
   手动退出会暂停该镜像同步；要重开，可关闭 **B 上刚创建的镜像 workspace**，
   然后从 Companion 再点击 Mirror here。不要关闭 A 上的源 workspace。

断线期间输入不会自动重发。若输入结果未知，先检查源端收到提示，避免盲目再次提交。

## 9. 失败时保留这些信息

记录失败步骤、B 的 macOS 版本/架构、cmux 版本、原始错误码以及：

```sh
"$HOME/.local/bin/cmux-remote-alpha" connect status
"$HOME/.local/bin/cmux-remote-alpha" mirror status
"$HOME/.local/bin/cmux-remote-alpha" mirror list
```

截图至少包含：发现列表、首次身份确认、等待批准、工作区列表、原生 Remote 分组，
以及断线前后。同一 workspace 重复打开和重启后，比较本地 workspace ID、surface ID。
无需复制任何 `.key` 文件或整个状态目录。

常见情况：

- `enrollment_closed/expired`：在 A 重新开 10 分钟窗口，B 取消旧请求后重新申请。
- `scope_denied` / 看得到但不能输入：检查 A 的批准是否含 `terminalInput`，以及 workspace 是否精确匹配。
- `socket_unavailable`：检查 B 的本地 Bridge 是否在 cmux 内运行、状态目录是否为默认目录。
- `mirror_unsupported`：记录 A/B 官方 cmux 的版本和错误；该版本可能缺少所需 replay/group API。
- `certificate_mismatch/host_changed`：停止连接，核对 A 的当前身份，不绕过指纹校验。
- `mirror_local_changed/stale_binding`：不要反复强制同步，先检查是否修改了本地镜像或源端进程。

## 10. 本轮通过标准与已完成的 A 端检查

B 的实机通过标准：发现并批准 → 原生 Remote 分组 → 同一源终端输出和输入 →
重复打开不重复创建 → Companion/Bridge 重启恢复 → 本地退出不结束 A 的源进程。

A 已对**本文专用服务**完成本机独立客户端预检：首次配对、6 个终端 replay、
受控输入、同一 operation 的重复提交只产生一个源端确认，以及远端 Bridge 重启后
保留原 6 个 viewer 和源进程。重启后再提交同一 operation，仍返回原 receipt，
源端确认次数保持 1。证据在
`.build/verification/lan-alpha/source-host-precheck.json`。
安装包的解压、签名和 CLI 执行也已实际验证。

当前尚不能据此宣称“两台物理 Mac 已通过”或“真实 Claude/Codex 已通过”。
输出仍是约 300 ms 加请求耗时的字符网格快照，支持当前画面，完整滚动历史、
无损流、图形/浏览器、共享尺寸和精确分屏比例不在本轮 Alpha 范围。

## A 端服务维护（仅在 A 执行）

A 的宿主终端是 **cmux Remote mirror acceptance** 中运行以下程序的 tab：

```sh
python3 /tmp/cmux-remote-alpha-host-20261012/run.py
```

这个前台程序保持 Bridge 7780 和下载服务 7781；退出只停止这两个测试服务。
重启后复用 `~/.local/state/cmux-remote-alpha-source`，不要删除或重新初始化它，
否则身份和已有授权将改变。不要退出官方 cmux 或停止源终端。
运行信息在 `/tmp/cmux-remote-alpha-host-20261012/process.json`。
