#lang racket

;; 标准 ncurses 颜色 ID（固定值，来自 curses.h）
;; 这些是 C 库中的实际整数值，在几乎所有系统上都一致

(define COLOR_BLACK   0)
(define COLOR_RED     1)
(define COLOR_GREEN   2)
(define COLOR_YELLOW  3)
(define COLOR_BLUE    4)
(define COLOR_MAGENTA 5)
(define COLOR_CYAN    6)
(define COLOR_WHITE   7)

;; 扩展颜色（如果支持 16 色）
;; 注意：不是所有终端都支持，但定义出来无害
(define COLOR_BLACK_BOLD   8)   ; 有些系统用 8-15 表示 bright variants
(define COLOR_RED_BOLD     9)
(define COLOR_GREEN_BOLD   10)
(define COLOR_YELLOW_BOLD  11)
(define COLOR_BLUE_BOLD    12)
(define COLOR_MAGENTA_BOLD 13)
(define COLOR_CYAN_BOLD    14)
(define COLOR_WHITE_BOLD   15)

;; 导出所有
(provide (all-defined-out))