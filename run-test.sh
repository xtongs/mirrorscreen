#!/bin/bash
# 测试脚本 - 请在 macOS GUI 终端中运行

BIN_DIR="$(swift build -c release --show-bin-path 2>/dev/null)"
BIN="$BIN_DIR/MirrorScreen"

echo "=== MirrorScreen 测试 ==="
echo ""

if [ -z "$BIN_DIR" ] || [ ! -f "$BIN" ]; then
    echo "错误: 二进制文件不存在或构建失败，请先运行: swift build -c release"
    exit 1
fi

echo "1. 检查当前会话是否有 GUI..."
if [ -z "$DISPLAY" ] && [ ! -d "/private/tmp/com.apple.launchd" ]; then
    echo "⚠️  警告: 当前可能没有 GUI 会话"
fi

echo ""
echo "2. 启动 MirrorScreen 服务..."
echo ""

"$BIN" start
"$BIN" status
echo ""
echo "3. 观察日志（Ctrl+C 退出 tail）..."
echo ""
tail -f "$BIN_DIR/MirrorScreen.log"
