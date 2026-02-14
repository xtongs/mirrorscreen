# MirrorScreen

轻量级 macOS 虚拟显示器命令行工具。  
A lightweight macOS virtual display CLI tool.

可创建虚拟显示器并镜像内置屏幕，内置 `start/stop/status/restart` 管理命令，适合直接在 bash 中使用。  
It creates a virtual display and mirrors your built-in screen, with built-in `start/stop/status/restart` commands for direct bash usage.

## 快速开始 / Quick Start

```bash
# 1) 安装到 PATH（示例：~/.local/bin）
# 1) Install to PATH (example: ~/.local/bin)
mkdir -p ~/.local/bin
cp MirrorScreen ~/.local/bin/MirrorScreen
chmod +x ~/.local/bin/MirrorScreen

# 2) 启动常驻服务
# 2) Start daemon service
MirrorScreen start

# 3) 查看状态和日志
# 3) Check status and logs
MirrorScreen status
tail -f ~/.local/bin/MirrorScreen.log
```

## 功能特性 / Features

- 内置服务管理：`start / stop / status / restart`  
  Built-in service management commands: `start / stop / status / restart`
- `start` 自动注册 `LaunchAgent` 常驻运行，避免“终端退出后进程消失”  
  `start` registers a persistent `LaunchAgent` to avoid process exit when terminal sessions end.
- 自动检测虚拟显示器离线并尝试恢复  
  Automatically detects virtual display offline state and tries recovery.
- 内置屏幕关闭时自动切换到扩展模式，开启后自动恢复镜像  
  Switches to extended mode when the built-in display is off, and restores mirror mode when back on.
- 日志输出到可执行文件同目录下的 `MirrorScreen.log`  
  Logs are written to `MirrorScreen.log` in the same directory as the executable.

## 安装 / Installation

### 方式一：从 GitHub Releases 下载（推荐）  
### Option 1: Download from GitHub Releases (Recommended)

下载 `MirrorScreen` 二进制后：  
After downloading the `MirrorScreen` binary:

```bash
mkdir -p ~/.local/bin
mv MirrorScreen ~/.local/bin/MirrorScreen
chmod +x ~/.local/bin/MirrorScreen
```

### 方式二：本地构建  
### Option 2: Build from Source

```bash
git clone <your-repo-url>
cd MirrorScreen
swift build -c release
mkdir -p ~/.local/bin
cp .build/arm64-apple-macosx/release/MirrorScreen ~/.local/bin/MirrorScreen
chmod +x ~/.local/bin/MirrorScreen
```

## 使用 / Usage

```bash
MirrorScreen start     # 启动 launchd 常驻服务（推荐） / Start launchd service (recommended)
MirrorScreen status    # 查看服务和进程状态 / Show service and process status
MirrorScreen restart   # 重启服务 / Restart service
MirrorScreen stop      # 停止服务 / Stop service
```

`start` 会创建/更新：  
`start` will create/update:

- `~/Library/LaunchAgents/com.mirrorscreen.agent.plist`
- `~/Library/Logs/MirrorScreen.launchd.out.log`
- `~/Library/Logs/MirrorScreen.launchd.err.log`

## 调试模式 / Debug Mode

```bash
MirrorScreen run
MirrorScreen --foreground
MirrorScreen --exit-on-signal
```

## 日志 / Logs

主日志 / Main log:

- `<MirrorScreen可执行文件目录>/MirrorScreen.log`

launchd 日志 / launchd logs:

- `~/Library/Logs/MirrorScreen.launchd.out.log`
- `~/Library/Logs/MirrorScreen.launchd.err.log`

日志包含：启动参数、PID/PPID、虚拟显示器创建/离线/恢复、镜像切换、错误信息。  
Logs include startup args, PID/PPID, virtual display create/offline/recovery events, mirror switching, and errors.

## 系统要求 / Requirements

- macOS 13 (Ventura) 或更高版本 / macOS 13 (Ventura) or later
- Apple Silicon 或 Intel Mac / Apple Silicon or Intel Mac
- 必须在 GUI 会话中运行（不支持纯 SSH 无图形会话）  
  Must run in a GUI session (pure SSH headless sessions are not supported)

## 常见问题 / FAQ

- 启动后很快消失：使用 `MirrorScreen start`，不要用临时 shell 会话后台拉起。  
  Disappears shortly after startup: use `MirrorScreen start` instead of launching from a temporary shell session.
- 看不到虚拟显示器：先执行 `MirrorScreen status`，再查看 `MirrorScreen.log` 是否有创建失败/恢复失败日志。  
  Virtual display not visible: run `MirrorScreen status` first, then inspect `MirrorScreen.log` for create/recovery failures.
- 移动了二进制路径后异常：重新执行一次 `MirrorScreen start` 刷新 LaunchAgent 配置。  
  Issues after moving binary path: run `MirrorScreen start` again to refresh LaunchAgent config.

## 卸载 / Uninstall

```bash
MirrorScreen stop
rm -f ~/Library/LaunchAgents/com.mirrorscreen.agent.plist
rm -f ~/Library/Logs/MirrorScreen.launchd.out.log
rm -f ~/Library/Logs/MirrorScreen.launchd.err.log
# 可选：删除二进制与主日志 / Optional: remove binary and main log
# rm -f ~/.local/bin/MirrorScreen ~/.local/bin/MirrorScreen.log
```

## 注意事项 / Notes

- 本项目使用 CoreGraphics 未公开 API（`CGVirtualDisplay`），未来 macOS 更新可能导致行为变化。  
  This project uses private CoreGraphics API (`CGVirtualDisplay`), and future macOS updates may change behavior.

## License

MIT
