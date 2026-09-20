#lang racket

;; 字符图后端演示 —— 与 base 版 demo 的唯一区别就是 require 路径。
;; 运行: racket demo/char-preview.rkt

(require "../char.rkt")

(define (draw-ui)
  (bytes-append
   format-screen-clear
   (format-cursor-move 1 1)
   (format-rgb-fg 255 255 0 "=== TUI Demo ===")
   (format-cursor-move 3 1)
   (format-rgb-fg 0 255 0 "Press 'q' to quit")
   (format-cursor-move 5 1)
   (format-rgb-fg 255 0 0 "Hello, TUI!")
   (format-cursor-move 7 1)
   (format-256-fg 46 "UTF-8 support: 你好世界")
   (format-cursor-move 9 1)
   (format-styled-at 10 1 'warning "warning: styled via registry")
   format-cursor-save
   (format-cursor-move 11 1)
   format-bold "bold text" format-reset
   format-cursor-restore))

(with-tui
 (λ ()
   (put-bytes (draw-ui))
   (displayln (char-frame))
   (displayln "── 非默认格（按需属性）──")
   (for ([c (screen-styled-cells (the-screen))])
     (displayln c)))
 #:rows 13 #:cols 44)
