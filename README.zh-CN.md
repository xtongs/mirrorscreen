# MirrorScreen

[English](README.md)

轻量级 macOS 虚拟显示器命令行工具。

可创建虚拟显示器并镜像内置屏幕，内置 `start/stop/status/restart` 管理命令，适合直接在 bash 中使用。

## 快速开始

```bash
# 1) 安装到 PATH（示例：~/.local/bin）
mkdir -p ~/.local/bin
cp MirrorScreen ~/.local/bin/MirrorScreen
chmod +x ~/.local/bin/MirrorScreen

# 2) 启动常驻服务
MirrorScreen start

# 3) 查看状态和日志
MirrorScreen status
tail -f ~/.local/bin/MirrorScreen.log
```

## 功能特性

- 内置服务管理：`start / stop / status / restart`
- `start` 自动注册 `LaunchAgent` 常驻运行，避免“终端退出后进程消失”
- 自动检测虚拟显示器离线并尝试恢复
- 内置屏幕关闭时自动切换到扩展模式，开启后自动恢复镜像
- 日志输出到可执行文件同目录下的 `MirrorScreen.log`

## 技术原理（How it works）

> 目标：在不插实体外接显示器的情况下，让 macOS “认为”有一块外接屏存在，从而在合盖/内置屏关闭后仍能保持图形会话可用（效果与传统 clamshell 模式接近）。

### 1) 用“虚拟外接屏”满足 clamshell 条件

很多 MacBook 在合盖后会让内置屏变为离线状态；当系统没有检测到可用外接显示器时，通常会进一步进入睡眠以避免无显示输出。

MirrorScreen 通过创建一个虚拟显示器，使系统枚举到一块“外接屏”，从而让合盖后的会话更容易保持可用（实际行为仍受机型、macOS 版本与电源策略影响，建议外接电源）。

### 2) 使用 CoreGraphics 私有 API 创建虚拟显示器

项目通过 CoreGraphics 的未公开类 `CGVirtualDisplay` / `CGVirtualDisplayDescriptor` / `CGVirtualDisplaySettings` 创建虚拟显示器：

- 先读取源显示器（优先内置屏，否则主屏）的分辨率与刷新率
- 构造 `CGVirtualDisplayDescriptor`（名称、最大像素宽高、vendor/product/serial 等）
- `CGVirtualDisplay(descriptor:)` 创建虚拟显示器并拿到 `displayID`
- 通过 `CGVirtualDisplaySettings` 下发一组分辨率模式（含 HiDPI 与常见分辨率）

由于这些 API 未公开，`Sources/CGVirtualDisplayBridge/include/CGVirtualDisplayPrivate.h` 只是为了让 Swift 能调用到 CoreGraphics.framework 内的同名运行时类。

### 3) 镜像与合盖/亮屏时的模式切换

创建虚拟显示器后，MirrorScreen 使用公开 API `CGConfigureDisplayMirrorOfDisplay` 将“虚拟屏”镜像到“源显示器”（默认优先内置屏）。

当检测到内置屏离线（常见于合盖/关屏）且当前处于镜像模式时，会自动切到扩展模式（取消镜像），避免镜像目标消失导致的显示配置异常；当内置屏重新在线且合盖前处于镜像时，再自动恢复镜像。

### 4) 虚拟显示器保活与自动重建

macOS 可能在睡眠/唤醒、用户切换或某些显示配置变化后回收虚拟显示器。MirrorScreen 通过两条路径尽量自愈：

- 定时轮询 `CGGetOnlineDisplayList`，发现虚拟屏离线则重建并按需恢复镜像
- 在 `CGVirtualDisplayDescriptor.terminationHandler` 被系统触发时进行重建

### 5) `caffeinate -d` 防止显示器休眠

为了减少“显示器进入休眠 → 显示配置变化/会话不可用”的概率，进程启动后会拉起子进程 `/usr/bin/caffeinate -d`（仅阻止显示器休眠），在 `stop` 时终止该子进程。

## 安装

### 方式一：从 GitHub Releases 下载（推荐）

下载 `MirrorScreen` 二进制后：

```bash
mkdir -p ~/.local/bin
mv MirrorScreen ~/.local/bin/MirrorScreen
chmod +x ~/.local/bin/MirrorScreen
```

### 方式二：本地构建

```bash
git clone <your-repo-url>
cd MirrorScreen
swift build -c release
mkdir -p ~/.local/bin
BIN_DIR="$(swift build -c release --show-bin-path)"
cp "$BIN_DIR/MirrorScreen" ~/.local/bin/MirrorScreen
chmod +x ~/.local/bin/MirrorScreen
```

## 使用

```bash
MirrorScreen start     # 启动 launchd 常驻服务（推荐）
MirrorScreen status    # 查看服务和进程状态
MirrorScreen restart   # 重启服务
MirrorScreen stop      # 停止服务
```

### 合盖使用建议（clamshell-like）

1. 建议接入电源适配器（多数机型在电池模式下更容易合盖睡眠）。
2. 执行 `MirrorScreen start` 后用 `MirrorScreen status` 确认进程在运行，并在“显示器”里能看到名为 `MirrorScreen` 的虚拟显示器。
3. 合盖后：
   - 若你是远程使用：提前开启“屏幕共享/远程管理”，然后通过局域网远程连接。
   - 若你是本机外设使用：连接外接键盘/鼠标/触控板，系统应维持可用会话（具体取决于 macOS 与机型）。

`start` 会创建/更新：

- `~/Library/LaunchAgents/com.mirrorscreen.agent.plist`
- `~/Library/Logs/MirrorScreen.launchd.out.log`
- `~/Library/Logs/MirrorScreen.launchd.err.log`

## 调试模式

```bash
MirrorScreen run
MirrorScreen --foreground
MirrorScreen --exit-on-signal
```

## 日志

主日志：

- `<MirrorScreen可执行文件目录>/MirrorScreen.log`

launchd 日志：

- `~/Library/Logs/MirrorScreen.launchd.out.log`
- `~/Library/Logs/MirrorScreen.launchd.err.log`

日志包含：启动参数、PID/PPID、虚拟显示器创建/离线/恢复、镜像切换、错误信息。

## 系统要求

- macOS 13 (Ventura) 或更高版本
- Apple Silicon 或 Intel Mac
- 必须在 GUI 会话中运行（不支持纯 SSH 无图形会话）

## 常见问题

- 启动后很快消失：使用 `MirrorScreen start`，不要用临时 shell 会话后台拉起。
- 看不到虚拟显示器：先执行 `MirrorScreen status`，再查看 `MirrorScreen.log` 是否有创建失败/恢复失败日志。
- 移动了二进制路径后异常：重新执行一次 `MirrorScreen start` 刷新 LaunchAgent 配置。

## 卸载

```bash
MirrorScreen stop
rm -f ~/Library/LaunchAgents/com.mirrorscreen.agent.plist
rm -f ~/Library/Logs/MirrorScreen.launchd.out.log
rm -f ~/Library/Logs/MirrorScreen.launchd.err.log
# 可选：删除二进制与主日志
# rm -f ~/.local/bin/MirrorScreen ~/.local/bin/MirrorScreen.log
```

## 注意事项

- 本项目使用 CoreGraphics 未公开 API（`CGVirtualDisplay`），未来 macOS 更新可能导致行为变化或直接失效。
- 该实现不适用于 Mac App Store，上架/公证（notarization）也可能受限。
- `caffeinate -d` 仅防止“显示器休眠”，不等同于强制禁止系统睡眠；合盖持续可用通常更依赖外接电源与系统电源策略。
- 必须在已登录的 GUI 会话内运行（`LaunchAgent`），纯 SSH/无图形会话下无法创建/管理显示配置。

## License

MIT
