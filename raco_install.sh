#!/bin/sh

raco pkg remove racket_tui
#以相对路径安装，
raco pkg install --link --auto