#!/bin/bash
# 启动 MirrorScreen launchd 常驻服务（推荐方式）

BIN="/Users/clawrunner/Workspace/MirrorScreen/.build/arm64-apple-macosx/release/MirrorScreen"

if [ ! -f "$BIN" ]; then
    echo "错误: 二进制文件不存在"
    exit 1
fi

GUI_USER=$(stat -f "%Su" /dev/console)

if [ -z "$GUI_USER" ]; then
    echo "错误: 无法确定 GUI 用户"
    exit 1
fi

echo "以 GUI 用户 $GUI_USER 身份启动 MirrorScreen 服务..."
echo ""

"$BIN" start
"$BIN" status
echo ""
echo "日志文件:"
echo "  $BIN.log"
