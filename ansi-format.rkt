#lang racket

(provide format-cursor-move format-cursor-up format-cursor-down
         format-cursor-right format-cursor-left format-cursor-col
         format-cursor-home format-cursor-hide format-cursor-show
         format-screen-clear format-screen-clear-below format-screen-clear-above
         format-line-clear format-line-clear-right format-line-clear-left
         format-buffer-alt-enable format-buffer-alt-disable
         format-content format-reset
         format-rgb-fg format-rgb-bg format-rgb-fg-bg
         format-256-fg format-256-bg
         format-styled)

;; 基础 ANSI 序列生成器
(define (format-cursor-move row col)
  (string->bytes/utf-8 (format "\e[~a;~aH" row col)))

(define (format-cursor-up n)
  (string->bytes/utf-8 (format "\e[~aA" n)))

(define (format-cursor-down n)
  (string->bytes/utf-8 (format "\e[~aB" n)))

(define (format-cursor-right n)
  (string->bytes/utf-8 (format "\e[~aC" n)))

(define (format-cursor-left n)
  (string->bytes/utf-8 (format "\e[~aD" n)))

(define (format-cursor-col n)
  (string->bytes/utf-8 (format "\e[~aG" n)))

(define format-cursor-home #"\e[H")
(define format-cursor-hide #"\e[?25l")
(define format-cursor-show #"\e[?25h")

(define format-screen-clear #"\e[2J")
(define format-screen-clear-below #"\e[0J")
(define format-screen-clear-above #"\e[1J")
(define format-line-clear #"\e[2K")
(define format-line-clear-right #"\e[0K")
(define format-line-clear-left #"\e[1K")
(define format-buffer-alt-enable #"\e[?1049h")
(define format-buffer-alt-disable #"\e[?1049l")

(define format-reset #"\e[0m")

;; 内容转换为字节串
(define (format-content v)
  (cond
    [(bytes? v) v]
    [(string? v) (string->bytes/utf-8 v)]
    [(char? v) (string->bytes/utf-8 (string v))]
    [else (string->bytes/utf-8 (format "~a" v))]))

;; RGB 颜色格式化
(define (format-rgb-fg r g b v)
  (bytes-append (string->bytes/utf-8 (format "\e[38;2;~a;~a;~am" r g b))
                (format-content v)
                format-reset))

(define (format-rgb-bg r g b v)
  (bytes-append (string->bytes/utf-8 (format "\e[48;2;~a;~a;~am" r g b))
                (format-content v)
                format-reset))

(define (format-rgb-fg-bg fr fg fb br bg bb v)
  (bytes-append (string->bytes/utf-8 (format "\e[38;2;~a;~a;~a;48;2;~a;~a;~am" fr fg fb br bg bb))
                (format-content v)
                format-reset))

;; 256 色格式化
(define (format-256-fg n v)
  (bytes-append (string->bytes/utf-8 (format "\e[38;5;~am" n))
                (format-content v)
                format-reset))

(define (format-256-bg n v)
  (bytes-append (string->bytes/utf-8 (format "\e[48;5;~am" n))
                (format-content v)
                format-reset))

;; 通用样式格式化（接收样式字节串）
(define (format-styled style-bytes v)
  (bytes-append style-bytes
                (format-content v)
                format-reset))