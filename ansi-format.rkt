#lang racket

;; ANSI 转义序列生成器（纯函数，返回字节串，不输出）

(provide format-content
         format-cursor-move format-cursor-up format-cursor-down
         format-cursor-right format-cursor-left format-cursor-col
         format-cursor-home format-cursor-hide format-cursor-show
         format-screen-clear format-screen-clear-below format-screen-clear-above
         format-line-clear format-line-clear-right format-line-clear-left
         format-buffer-alt-enable format-buffer-alt-disable
         format-reset
         format-rgb-fg format-rgb-bg format-rgb-fg-bg
         format-256-fg format-256-bg
         format-fg format-bg
         format-bold format-dim format-italic
         format-underline format-blink format-reverse)

;; 内容转换（辅助函数）
(define (format-content v)
  (cond [(bytes? v) v]
        [(string? v) (string->bytes/utf-8 v)]
        [(char? v) (string->bytes/utf-8 (string v))]
        [else (string->bytes/utf-8 (format "~a" v))]))


;; 基础 ANSI 序列（直接返回字节串）
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

;; 带参数的 ANSI 序列（返回字节串）
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

;; 16色前景/背景 - 完整表（16个标准色+默认）
(define fg-table
  #(30 31 32 33 34 35 36 37   ; 0-7
       90 91 92 93 94 95 96 97   ; 8-15
       39))

(define (format-fg n)
  (unless (<= 0 n 15) (error 'format-fg "ANSI color must be 0-15, got ~a" n))
  (define codes #(30 31 32 33 34 35 36 37    ; 0-7
                     90 91 92 93 94 95 96 97)) ; 8-15
  (define code (if (= n 9) 39 (vector-ref codes n)))
  (string->bytes/utf-8 (format "\e[~am" code)))

(define (format-bg n)
  (unless (<= 0 n 15) (error 'format-bg "ANSI color must be 0-15, got ~a" n))
  (define codes #(40 41 42 43 44 45 46 47     ; 0-7
                     100 101 102 103 104 105 106 107)) ; 8-15
  (define code (if (= n 9) 49 (vector-ref codes n)))
  (string->bytes/utf-8 (format "\e[~am" code)))

;; RGB 颜色
(define (format-rgb-fg r g b)
  (string->bytes/utf-8 (format "\e[38;2;~a;~a;~am" r g b)))

(define (format-rgb-bg r g b)
  (string->bytes/utf-8 (format "\e[48;2;~a;~a;~am" r g b)))

(define (format-rgb-fg-bg fr fg fb br bg bb)
  (string->bytes/utf-8 (format "\e[38;2;~a;~a;~a;48;2;~a;~a;~am" fr fg fb br bg bb)))

;; 256色
(define (format-256-fg n)
  (string->bytes/utf-8 (format "\e[38;5;~am" n)))

(define (format-256-bg n)
  (string->bytes/utf-8 (format "\e[48;5;~am" n)))

;; 属性
(define format-bold #"\e[1m")
(define format-dim #"\e[2m")
(define format-italic #"\e[3m")
(define format-underline #"\e[4m")
(define format-blink #"\e[5m")
(define format-reverse #"\e[7m")