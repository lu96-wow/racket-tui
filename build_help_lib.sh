#!/bin/sh

mkdir old

gcc -shared -fPIC -o ncurses-help.so ncurses-help.c -lncursesw
cp ncurses-help.so test


mv button_data.rkt old/button_data.rkt.old
mv key_data.rkt old/key_data.rkt.old

racket Generate_Key.rkt
racket Generate_Button.rkt 