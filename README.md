first:

config system had libncurses/w

use: build_help_lib.sh
     install_help_lib.sh 
     to build and install c help lib

then can go to 演示示例 look example code

lib.rkt is ncurses ffi bind
lib_exteen is Stronger bind macro
auto initscr opencolor and release

mouse.rkt supports mouse
key.rkt supports keyboard
color.rkt supports color show

install_help_lib.sh install help c lib to system

raco_install will use racket package install to local

or:
  raco pkg install https://github.com/lu96-wow/racket-tui.git
  git clone
