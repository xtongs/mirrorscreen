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

## How it works

> Goal: create a “virtual external monitor” so macOS keeps a usable GUI session when the MacBook lid is closed / the built-in display goes offline (similar to clamshell mode, without a physical monitor).

### 1) A virtual “external display” for clamshell-like behavior

On many MacBooks, closing the lid makes the built-in display go offline. If macOS can’t see any usable external display, it will often proceed to sleep to avoid having no display output.

MirrorScreen creates a virtual display so the system enumerates an “external monitor”, making it much more likely that the session stays usable after lid-close (actual behavior still depends on hardware, macOS version, and power policy; using AC power is recommended).

### 2) Creating the virtual display via CoreGraphics private API

MirrorScreen uses undocumented CoreGraphics classes `CGVirtualDisplay` / `CGVirtualDisplayDescriptor` / `CGVirtualDisplaySettings`:

- Read source display (prefer built-in, otherwise main) resolution and refresh rate
- Build a `CGVirtualDisplayDescriptor` (name, max pixel size, vendor/product/serial, etc.)
- Create `CGVirtualDisplay(descriptor:)` and obtain a `displayID`
- Apply `CGVirtualDisplaySettings` with a set of modes (HiDPI + common resolutions)

Because these APIs are private, `Sources/CGVirtualDisplayBridge/include/CGVirtualDisplayPrivate.h` is only a bridge header so Swift can call the runtime classes that live inside CoreGraphics.framework.

### 3) Mirroring and automatic mode switching

After creation, MirrorScreen uses the public API `CGConfigureDisplayMirrorOfDisplay` to mirror the virtual display from the source display.

When the built-in display turns off/goes offline (common on lid-close) while mirroring is enabled, it automatically disables mirroring (extended mode) to avoid display-configuration issues. When the built-in display comes back online and it was mirrored before, it restores mirroring automatically.

### 4) Keep-alive and auto-rebuild

macOS can reclaim virtual displays after sleep/wake, fast user switching, or certain display reconfigurations. MirrorScreen tries to self-heal via:

- Periodic polling with `CGGetOnlineDisplayList`; if the virtual display is offline, rebuild and restore mirroring if needed
- Rebuilding when `CGVirtualDisplayDescriptor.terminationHandler` is invoked

### 5) `caffeinate -d` to reduce display sleep

To reduce the chance of “display sleep → configuration changes / session becomes unusable”, the process starts `/usr/bin/caffeinate -d` (prevents display sleep only) and terminates it on `stop`.

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
BIN_DIR="$(swift build -c release --show-bin-path)"
cp "$BIN_DIR/MirrorScreen" ~/.local/bin/MirrorScreen
chmod +x ~/.local/bin/MirrorScreen
```

## Usage

```bash
MirrorScreen start     # Start launchd service (recommended)
MirrorScreen status    # Show service and process status
MirrorScreen restart   # Restart service
MirrorScreen stop      # Stop service
```

### Lid-closed usage (clamshell-like)

1. AC power is recommended (many models are more likely to sleep on battery when the lid is closed).
2. Run `MirrorScreen start`, then verify with `MirrorScreen status`. You should also see a `MirrorScreen` virtual display in System Settings → Displays.
3. After closing the lid:
   - For remote usage: enable Screen Sharing / Remote Management first, then connect over the network.
   - For local peripheral usage: use an external keyboard/mouse/trackpad; whether the session stays up depends on macOS + your hardware.

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

- This project uses private CoreGraphics API (`CGVirtualDisplay`); future macOS updates may change behavior or break it entirely.
- This approach is not suitable for the Mac App Store, and notarization/hardened runtime may be constrained by the private API usage.
- `caffeinate -d` prevents *display* sleep only; it does not guarantee the system will never sleep (lid-close behavior often depends on AC power and macOS power settings).
- Must run in a logged-in GUI session (`LaunchAgent`); pure SSH/headless sessions can’t manage display configuration.

## License

MIT
