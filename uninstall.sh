# uninstall.sh - 卸载 tui 包
#!/bin/bash
raco pkg remove tui
race pkg remove racket-tui
echo "tui 已卸载"