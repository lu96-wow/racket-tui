;; output-color.rkt - 颜色输出（带副作用）
#lang racket

(require "output.rkt"
         "ansi-format.rkt")

;; 样式系统
(define (make-style . specs)
  (λ () (for-each (λ (s) (s)) specs)))

(define style-registry (make-hash))

(define (style-define! name . specs)
  (hash-set! style-registry name (apply make-style specs)))

(define (style-apply! name)
  (define s (hash-ref style-registry name #f))
  (when s (s)))

(define (style-reset) (put-bytes format-reset))

;; 输出函数（复用 format-styled）
(define (put-styled name v)
  (define style-proc (hash-ref style-registry name #f))
  (if style-proc
      (let ([style-bytes (call-with-output-bytes
                          (λ (out)
                            (parameterize ([current-output-port out])
                              (style-proc))))])
        (put-bytes (format-styled style-bytes v)))
      (put v)))

(define (put-styled-at row col name v)
  (define old-r current-cursor-row)
  (define old-c current-cursor-col)
  (cursor-move row col)
  (put-styled name v)
  (cursor-move old-r old-c))

(define (put-styled-at! row col name v)
  (cursor-move row col)
  (put-styled name v))

;; RGB 颜色输出
(define (put-rgb-fg r g b v)
  (put-bytes (format-rgb-fg r g b v)))

(define (put-rgb-fg-at row col r g b v)
  (define old-r current-cursor-row)
  (define old-c current-cursor-col)
  (cursor-move row col)
  (put-rgb-fg r g b v)
  (cursor-move old-r old-c))

(define (put-rgb-fg-at! row col r g b v)
  (cursor-move row col)
  (put-rgb-fg r g b v))

(define (put-rgb-bg r g b v)
  (put-bytes (format-rgb-bg r g b v)))

(define (put-rgb-bg-at row col r g b v)
  (define old-r current-cursor-row)
  (define old-c current-cursor-col)
  (cursor-move row col)
  (put-rgb-bg r g b v)
  (cursor-move old-r old-c))

(define (put-rgb-bg-at! row col r g b v)
  (cursor-move row col)
  (put-rgb-bg r g b v))

(define (put-rgb-fg-bg fr fg fb br bg bb v)
  (put-bytes (format-rgb-fg-bg fr fg fb br bg bb v)))

(define (put-rgb-fg-bg-at row col fr fg fb br bg bb v)
  (define old-r current-cursor-row)
  (define old-c current-cursor-col)
  (cursor-move row col)
  (put-rgb-fg-bg fr fg fb br bg bb v)
  (cursor-move old-r old-c))

(define (put-rgb-fg-bg-at! row col fr fg fb br bg bb v)
  (cursor-move row col)
  (put-rgb-fg-bg fr fg fb br bg bb v))

;; 256 色输出
(define (put-256-fg n v)
  (put-bytes (format-256-fg n v)))

(define (put-256-fg-at row col n v)
  (define old-r current-cursor-row)
  (define old-c current-cursor-col)
  (cursor-move row col)
  (put-256-fg n v)
  (cursor-move old-r old-c))

(define (put-256-fg-at! row col n v)
  (cursor-move row col)
  (put-256-fg n v))

(define (put-256-bg n v)
  (put-bytes (format-256-bg n v)))

(define (put-256-bg-at row col n v)
  (define old-r current-cursor-row)
  (define old-c current-cursor-col)
  (cursor-move row col)
  (put-256-bg n v)
  (cursor-move old-r old-c))

(define (put-256-bg-at! row col n v)
  (cursor-move row col)
  (put-256-bg n v))

;; 颜色构造器（样式系统用，直接输出）
(define (color-fg n)
  (unless (<= 0 n 15) (error 'color-fg "ANSI color must be 0-15, got ~a" n))
  (λ () (put-string (format "\e[~am" (+ n (if (< n 8) 30 82))))))

(define (color-bg n)
  (unless (<= 0 n 15) (error 'color-bg "ANSI color must be 0-15, got ~a" n))
  (λ () (put-string (format "\e[~am" (+ n (if (< n 8) 40 92))))))

(define (color256-fg n)
  (unless (<= 0 n 255) (error 'color256-fg "256 color must be 0-255, got ~a" n))
  (λ () (put-string (format "\e[38;5;~am" n))))

(define (color256-bg n)
  (unless (<= 0 n 255) (error 'color256-bg "256 color must be 0-255, got ~a" n))
  (λ () (put-string (format "\e[48;5;~am" n))))

(define (color-rgb-fg r g b)
  (unless (<= 0 r 255) (error 'color-rgb-fg "R must be 0-255, got ~a" r))
  (unless (<= 0 g 255) (error 'color-rgb-fg "G must be 0-255, got ~a" g))
  (unless (<= 0 b 255) (error 'color-rgb-fg "B must be 0-255, got ~a" b))
  (λ () (put-string (format "\e[38;2;~a;~a;~am" r g b))))

(define (color-rgb-bg r g b)
  (unless (<= 0 r 255) (error 'color-rgb-bg "R must be 0-255, got ~a" r))
  (unless (<= 0 g 255) (error 'color-rgb-bg "G must be 0-255, got ~a" g))
  (unless (<= 0 b 255) (error 'color-rgb-bg "B must be 0-255, got ~a" b))
  (λ () (put-string (format "\e[48;2;~a;~a;~am" r g b))))

;; 属性构造器
(define attr-bold      (λ () (put-string "\e[1m")))
(define attr-dim       (λ () (put-string "\e[2m")))
(define attr-italic    (λ () (put-string "\e[3m")))
(define attr-underline (λ () (put-string "\e[4m")))
(define attr-blink     (λ () (put-string "\e[5m")))
(define attr-reverse   (λ () (put-string "\e[7m")))

;; 颜色别名
(define clr-black    (color-fg 0))  (define clr-red     (color-fg 1))
(define clr-green    (color-fg 2))  (define clr-yellow  (color-fg 3))
(define clr-blue     (color-fg 4))  (define clr-magenta (color-fg 5))
(define clr-cyan     (color-fg 6))  (define clr-white   (color-fg 7))
(define clr-default  (λ () (put-string "\e[39m")))

(define bclr-black   (color-bg 0))  (define bclr-red     (color-bg 1))
(define bclr-green   (color-bg 2))  (define bclr-yellow  (color-bg 3))
(define bclr-blue    (color-bg 4))  (define bclr-magenta (color-bg 5))
(define bclr-cyan    (color-bg 6))  (define bclr-white   (color-bg 7))
(define bclr-default (λ () (put-string "\e[49m")))

;; 向后兼容
(define (fg-black)   (clr-black))   (define (fg-red)     (clr-red))
(define (fg-green)   (clr-green))   (define (fg-blue)    (clr-blue))
(define (fg-yellow)  (clr-yellow))  (define (fg-magenta) (clr-magenta))
(define (fg-cyan)    (clr-cyan))    (define (fg-white)   (clr-white))
(define (fg-default) (clr-default))

(define (bg-black)   (bclr-black))  (define (bg-red)     (bclr-red))
(define (bg-green)   (bclr-green))  (define (bg-blue)    (bclr-blue))
(define (bg-yellow)  (bclr-yellow)) (define (bg-magenta) (bclr-magenta))
(define (bg-cyan)    (bclr-cyan))   (define (bg-white)   (bclr-white))
(define (bg-default) (bclr-default))

(define (style-bold)      (attr-bold))
(define (style-dim)       (attr-dim))
(define (style-italic)    (attr-italic))
(define (style-underline) (attr-underline))
(define (style-blink)     (attr-blink))
(define (style-reverse)   (attr-reverse))

;; 预设样式
(style-define! 'red   clr-red)
(style-define! 'green clr-green)
(style-define! 'blue  clr-blue)
(style-define! 'yellow clr-yellow)
(style-define! 'cyan  clr-cyan)
(style-define! 'magenta clr-magenta)
(style-define! 'white clr-white)

(style-define! 'error   clr-red attr-bold)
(style-define! 'warning clr-yellow attr-bold)
(style-define! 'info    clr-cyan)
(style-define! 'success clr-green)

(style-define! 'cursor    bclr-white clr-black)
(style-define! 'selection bclr-blue clr-white)

;; 导出
(provide put-styled put-styled-at put-styled-at!
         style-define! style-apply! style-reset
         color-fg color-bg color256-fg color256-bg
         color-rgb-fg color-rgb-bg
         attr-bold attr-dim attr-italic attr-underline attr-blink attr-reverse
         clr-black clr-red clr-green clr-yellow clr-blue clr-magenta clr-cyan clr-white
         bclr-black bclr-red bclr-green bclr-yellow bclr-blue bclr-magenta bclr-cyan bclr-white
         fg-black fg-red fg-green fg-blue fg-yellow fg-magenta fg-cyan fg-white fg-default
         bg-black bg-red bg-green bg-blue bg-yellow bg-magenta bg-cyan bg-white bg-default
         style-bold style-dim style-italic style-underline style-blink style-reverse
         put-rgb-fg put-rgb-fg-at put-rgb-fg-at!
         put-rgb-bg put-rgb-bg-at put-rgb-bg-at!
         put-rgb-fg-bg put-rgb-fg-bg-at put-rgb-fg-bg-at!
         put-256-fg put-256-fg-at put-256-fg-at!
         put-256-bg put-256-bg-at put-256-bg-at!)