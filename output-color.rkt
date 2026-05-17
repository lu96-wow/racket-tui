#lang racket

(require "output.rkt"
         "cursor-state.rkt"
         "ansi-format.rkt")

;; 样式系统（高层抽象）

(define (make-style . specs)
  (λ () (for-each (λ (s) (s)) specs)))

(define style-registry (make-hash))

(define (style-define! name . specs)
  (hash-set! style-registry name (apply make-style specs)))

(define (style-apply! name)
  (define s (hash-ref style-registry name
                      (λ () (error 'style-apply! "Undefined style: ~a" name))))
  (s))

(define (style-reset) (put-bytes format-reset))

;; 获取样式字节串（用于批量输出）
(define (style->bytes name)
  (define style-proc (hash-ref style-registry name
                               (λ () (error 'style->bytes "Undefined style: ~a" name))))
  (call-with-output-bytes
   (λ (out)
     (parameterize ([current-output-port out])
       (style-proc)))))

;; 立即输出样式函数

(define (put-styled name v)
  (define style-bytes (style->bytes name))
  (put-bytes (bytes-append style-bytes (format-content v) format-reset)))

(define (put-styled-at row col name v)
  (define old-r current-cursor-row)
  (define old-c current-cursor-col)
  (cursor-move row col)
  (put-styled name v)
  (cursor-move old-r old-c))

(define (put-styled-at! row col name v)
  (cursor-move row col)
  (put-styled name v))

;; 格式化样式函数（返回字节串，同时管理光标状态）

(define (format-styled name v)
  (define style-bytes (style->bytes name))
  (bytes-append style-bytes (format-content v) format-reset))

(define (format-styled-at row col name v)
  (define old-r current-cursor-row)
  (define old-c current-cursor-col)
  (set-cursor! row col)
  (let ([bs (bytes-append (format-cursor-move row col)
                          (format-styled name v)
                          (format-cursor-move old-r old-c))])
    (set-cursor! old-r old-c)
    bs))

(define (format-styled-at! row col name v)
  (set-cursor! row col)
  (bytes-append (format-cursor-move row col)
                (format-styled name v)))

(define (format-styled* name v)
  (define style-bytes (style->bytes name))
  (bytes-append style-bytes (format-content v)))

;; 颜色构造器（用于样式系统）

(define (color-fg n)
  (unless (<= 0 n 15) (error 'color-fg "ANSI color must be 0-15, got ~a" n))
  (λ () (put-bytes (format-fg n))))

(define (color-bg n)
  (unless (<= 0 n 15) (error 'color-bg "ANSI color must be 0-15, got ~a" n))
  (λ () (put-bytes (format-bg n))))

(define (color256-fg n)
  (unless (<= 0 n 255) (error 'color256-fg "256 color must be 0-255, got ~a" n))
  (λ () (put-bytes (format-256-fg n))))

(define (color256-bg n)
  (unless (<= 0 n 255) (error 'color256-bg "256 color must be 0-255, got ~a" n))
  (λ () (put-bytes (format-256-bg n))))

(define (color-rgb-fg r g b)
  (unless (<= 0 r 255) (error 'color-rgb-fg "R must be 0-255, got ~a" r))
  (unless (<= 0 g 255) (error 'color-rgb-fg "G must be 0-255, got ~a" g))
  (unless (<= 0 b 255) (error 'color-rgb-fg "B must be 0-255, got ~a" b))
  (λ () (put-bytes (format-rgb-fg r g b))))

(define (color-rgb-bg r g b)
  (unless (<= 0 r 255) (error 'color-rgb-bg "R must be 0-255, got ~a" r))
  (unless (<= 0 g 255) (error 'color-rgb-bg "G must be 0-255, got ~a" g))
  (unless (<= 0 b 255) (error 'color-rgb-bg "B must be 0-255, got ~a" b))
  (λ () (put-bytes (format-rgb-bg r g b))))

;; 属性构造器（用于样式系统）

(define attr-bold      (λ () (put-bytes format-bold)))
(define attr-dim       (λ () (put-bytes format-dim)))
(define attr-italic    (λ () (put-bytes format-italic)))
(define attr-underline (λ () (put-bytes format-underline)))
(define attr-blink     (λ () (put-bytes format-blink)))
(define attr-reverse   (λ () (put-bytes format-reverse)))

;; 格式化属性函数（返回字节串，同时管理光标状态）

;; 基础格式化
(define (format-styled-bold v)
  (bytes-append format-bold (format-content v) format-reset))

(define (format-styled-dim v)
  (bytes-append format-dim (format-content v) format-reset))

(define (format-styled-italic v)
  (bytes-append format-italic (format-content v) format-reset))

(define (format-styled-underline v)
  (bytes-append format-underline (format-content v) format-reset))

(define (format-styled-blink v)
  (bytes-append format-blink (format-content v) format-reset))

(define (format-styled-reverse v)
  (bytes-append format-reverse (format-content v) format-reset))

;; 辅助函数：带属性的 at 通用实现（同时管理光标状态）
(define (format-styled-attr-at row col fmt-fn v)
  (define old-r current-cursor-row)
  (define old-c current-cursor-col)
  (set-cursor! row col)
  (let ([bs (bytes-append (format-cursor-move row col)
                          (fmt-fn v)
                          (format-cursor-move old-r old-c))])
    (set-cursor! old-r old-c)
    bs))

(define (format-styled-attr-at! row col fmt-fn v)
  (set-cursor! row col)
  (bytes-append (format-cursor-move row col)
                (fmt-fn v)))

;; at 变体（恢复光标）
(define (format-styled-bold-at row col v)
  (format-styled-attr-at row col format-styled-bold v))

(define (format-styled-dim-at row col v)
  (format-styled-attr-at row col format-styled-dim v))

(define (format-styled-italic-at row col v)
  (format-styled-attr-at row col format-styled-italic v))

(define (format-styled-underline-at row col v)
  (format-styled-attr-at row col format-styled-underline v))

(define (format-styled-blink-at row col v)
  (format-styled-attr-at row col format-styled-blink v))

(define (format-styled-reverse-at row col v)
  (format-styled-attr-at row col format-styled-reverse v))

;; at! 变体（不恢复光标）
(define (format-styled-bold-at! row col v)
  (format-styled-attr-at! row col format-styled-bold v))

(define (format-styled-dim-at! row col v)
  (format-styled-attr-at! row col format-styled-dim v))

(define (format-styled-italic-at! row col v)
  (format-styled-attr-at! row col format-styled-italic v))

(define (format-styled-underline-at! row col v)
  (format-styled-attr-at! row col format-styled-underline v))

(define (format-styled-blink-at! row col v)
  (format-styled-attr-at! row col format-styled-blink v))

(define (format-styled-reverse-at! row col v)
  (format-styled-attr-at! row col format-styled-reverse v))

;; 导出

(provide
 ;; 样式管理
 style-define! style-apply! style-reset style->bytes
 ;; 立即输出样式
 put-styled put-styled-at put-styled-at!
 ;; 格式化样式（批量输出）
 format-styled format-styled-at format-styled-at! format-styled*
 ;; 颜色构造器
 color-fg color-bg color256-fg color256-bg color-rgb-fg color-rgb-bg
 ;; 属性构造器
 attr-bold attr-dim attr-italic attr-underline attr-blink attr-reverse
 ;; 格式化属性（批量输出）
 format-styled-bold format-styled-bold-at format-styled-bold-at!
 format-styled-dim format-styled-dim-at format-styled-dim-at!
 format-styled-italic format-styled-italic-at format-styled-italic-at!
 format-styled-underline format-styled-underline-at format-styled-underline-at!
 format-styled-blink format-styled-blink-at format-styled-blink-at!
 format-styled-reverse format-styled-reverse-at format-styled-reverse-at!)