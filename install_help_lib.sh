#!/bin/bash

# install_help_lib.sh
# 安装 ncurses-help.so 到 /usr/lib/

set -e  # 遇到错误立即退出

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_NAME="ncurses-help.so"
SOURCE_FILE="$SCRIPT_DIR/$LIB_NAME"
DEST_DIR="/usr/lib"
DEST_FILE="$DEST_DIR/$LIB_NAME"

echo "正在安装 $LIB_NAME 到 $DEST_DIR ..."

# 检查源文件是否存在
if [ ! -f "$SOURCE_FILE" ]; then
    echo "错误：找不到源文件 $SOURCE_FILE"
    exit 1
fi

# 检查是否以 root 运行
if [ "$EUID" -ne 0 ]; then
    echo "此脚本需要 root 权限来写入 $DEST_DIR。请使用 sudo。"
    exit 1
fi

# 备份已存在的文件（如果存在）
if [ -f "$DEST_FILE" ]; then
    echo "警告：$DEST_FILE 已存在，正在备份为 ${DEST_FILE}.bak"
    cp "$DEST_FILE" "${DEST_FILE}.bak"
fi

# 复制文件
cp "$SOURCE_FILE" "$DEST_FILE"

# 设置权限（通常 .so 文件权限为 644 或 755）
chmod 644 "$DEST_FILE"

echo "成功安装 $LIB_NAME 到 $DEST_DIR"
echo "如需卸载，请运行 ./uninstall_lib.sh（需 root 权限）"