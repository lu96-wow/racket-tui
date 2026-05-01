# link.sh - 链接安装（开发模式，修改源码立即生效）
#!/bin/bash
raco pkg install --link $PWD/
echo "tui 已链接安装（开发模式）"