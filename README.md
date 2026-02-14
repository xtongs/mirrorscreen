# MirrorScreen

[中文文档](README.zh-CN.md)

A lightweight macOS virtual display CLI tool.

It creates a virtual display and mirrors your built-in screen, with built-in `start/stop/status/restart` commands for direct bash usage.

## Quick Start

```bash
# 1) Install to PATH (example: ~/.local/bin)
mkdir -p ~/.local/bin
cp MirrorScreen ~/.local/bin/MirrorScreen
chmod +x ~/.local/bin/MirrorScreen

# 2) Start daemon service
MirrorScreen start

# 3) Check status and logs
MirrorScreen status
tail -f ~/.local/bin/MirrorScreen.log
```

## Features

- Built-in service management commands: `start / stop / status / restart`
- `start` registers a persistent `LaunchAgent` to avoid process exit when terminal sessions end
- Automatically detects virtual display offline state and tries recovery
- Switches to extended mode when the built-in display is off, and restores mirror mode when back on
- Logs are written to `MirrorScreen.log` in the same directory as the executable

## Installation

### Option 1: Download from GitHub Releases (Recommended)

After downloading the `MirrorScreen` binary:

```bash
mkdir -p ~/.local/bin
mv MirrorScreen ~/.local/bin/MirrorScreen
chmod +x ~/.local/bin/MirrorScreen
```

### Option 2: Build from Source

```bash
git clone <your-repo-url>
cd MirrorScreen
swift build -c release
mkdir -p ~/.local/bin
cp .build/arm64-apple-macosx/release/MirrorScreen ~/.local/bin/MirrorScreen
chmod +x ~/.local/bin/MirrorScreen
```

## Usage

```bash
MirrorScreen start     # Start launchd service (recommended)
MirrorScreen status    # Show service and process status
MirrorScreen restart   # Restart service
MirrorScreen stop      # Stop service
```

`start` will create/update:

- `~/Library/LaunchAgents/com.mirrorscreen.agent.plist`
- `~/Library/Logs/MirrorScreen.launchd.out.log`
- `~/Library/Logs/MirrorScreen.launchd.err.log`

## Debug Mode

```bash
MirrorScreen run
MirrorScreen --foreground
MirrorScreen --exit-on-signal
```

## Logs

Main log:

- `<MirrorScreen executable directory>/MirrorScreen.log`

launchd logs:

- `~/Library/Logs/MirrorScreen.launchd.out.log`
- `~/Library/Logs/MirrorScreen.launchd.err.log`

Logs include startup args, PID/PPID, virtual display create/offline/recovery events, mirror switching, and errors.

## Requirements

- macOS 13 (Ventura) or later
- Apple Silicon or Intel Mac
- Must run in a GUI session (pure SSH headless sessions are not supported)

## FAQ

- Disappears shortly after startup: use `MirrorScreen start` instead of launching from a temporary shell session.
- Virtual display not visible: run `MirrorScreen status` first, then inspect `MirrorScreen.log` for create/recovery failures.
- Issues after moving binary path: run `MirrorScreen start` again to refresh LaunchAgent config.

## Uninstall

```bash
MirrorScreen stop
rm -f ~/Library/LaunchAgents/com.mirrorscreen.agent.plist
rm -f ~/Library/Logs/MirrorScreen.launchd.out.log
rm -f ~/Library/Logs/MirrorScreen.launchd.err.log
# Optional: remove binary and main log
# rm -f ~/.local/bin/MirrorScreen ~/.local/bin/MirrorScreen.log
```

## Notes

- This project uses private CoreGraphics API (`CGVirtualDisplay`), and future macOS updates may change behavior.

## License

MIT
