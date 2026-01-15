#lang racket

(require "../lib.rkt"
         "../lib_extern.rkt"
         "../color.rkt"
         "../ncurses_default_color.rkt"
         "../attribute_data.rkt")

(define (main) 
    (when (has_colors)
        ;;兼容只支持默认颜色的终端
        (define-color-pair 'a COLOR_RED COLOR_BLACK)
        (mvaddstr/xy 0 0 "红字黑底" (pair 'a))
        
        ;rgb 定义拓展颜色
        (define-color 'green 0 1000 0)
        (define-color 'blue 0 0 1000)
        (define-color 'red 1000 0 0)

        ;支持混用
        (define-color-pair 'b COLOR_BLACK 'green)
        (mvaddstr/xy 0 1 "红字绿底" (pair 'b))

        ;纯彩色
        (define-color-pair 'c 'blue 'green)
        (mvaddstr/xy 0 2 "蓝字红底" (pair 'c))
    )
    (getch)
    (refresh)
)

;; 启动
(with-ncurses
    main
)