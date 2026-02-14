#!/bin/bash
# 测试脚本 - 请在 macOS GUI 终端中运行

BIN=".build/arm64-apple-macosx/release/MirrorScreen"

echo "=== MirrorScreen 测试 ==="
echo ""

if [ ! -f "$BIN" ]; then
    echo "错误: 二进制文件不存在，请先运行: swift build -c release"
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
tail -f .build/arm64-apple-macosx/release/MirrorScreen.log
