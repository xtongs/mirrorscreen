# MirrorScreen

[English](README.en.md)

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
cp .build/arm64-apple-macosx/release/MirrorScreen ~/.local/bin/MirrorScreen
chmod +x ~/.local/bin/MirrorScreen
```

## 使用

```bash
MirrorScreen start     # 启动 launchd 常驻服务（推荐）
MirrorScreen status    # 查看服务和进程状态
MirrorScreen restart   # 重启服务
MirrorScreen stop      # 停止服务
```

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

- 本项目使用 CoreGraphics 未公开 API（`CGVirtualDisplay`），未来 macOS 更新可能导致行为变化。

## License

MIT
