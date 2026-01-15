#!/bin/bash
if [ "$EUID" -ne 0 ]; then
    echo "请使用 sudo 运行卸载脚本"
    exit 1
fi
rm -f /usr/lib/ncurses-help.so
echo "已卸载 ncurses-help.so"