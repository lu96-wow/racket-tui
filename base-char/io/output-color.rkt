#lang racket

;; char 后端的样式系统 —— 与 base/io/output-color.rkt 同名同签名。
;; 双表（256/16）回退逻辑不变；区别只是「应用样式」改成 emit op 到 grid。

(require "./output.rkt"
         "../ansi/ansi-format.rkt"
         "../screen/ops.rkt"
         "../terminal/cursor-state.rkt")

(define (make-style . specs)
  (λ () (for-each (λ (s) (s)) (filter procedure? specs))))

(define registry-256 (make-hash))
(define registry-16  (make-hash))
(define current-registry (make-parameter registry-16))

(struct color-thunk (do-256 do-16) #:transparent)

(define (color-fg* c256 c16)
  (unless (<= 0 c16 15)  (error 'color-fg* "16-color value must be 0-15, got ~a" c16))
  (unless (<= 0 c256 255) (error 'color-fg* "256-color value must be 0-255, got ~a" c256))
  (color-thunk (color256-fg c256) (color-fg c16)))

(define (color-bg* c256 c16)
  (unless (<= 0 c16 15)  (error 'color-bg* "16-color value must be 0-15, got ~a" c16))
  (unless (<= 0 c256 255) (error 'color-bg* "256-color value must be 0-255, got ~a" c256))
  (color-thunk (color256-bg c256) (color-bg c16)))

(define (style-define! name . specs)
  (define (resolve pick)
    (apply make-style
           (for/list ([s specs])
             (if (color-thunk? s) (pick s) s))))
  (hash-set! registry-256 name (resolve color-thunk-do-256))
  (hash-set! registry-16  name (resolve color-thunk-do-16)))

(define (style-apply! name)
  (define s (hash-ref (current-registry) name void))
  (when (procedure? s) (s)))

(define (style-reset) (emit format-reset))

;; 返回 op-seq（名字沿用 base 的 style->bytes，便于换后端不改调用点）
(define (style->bytes name)
  (define s (hash-ref (current-registry) name void))
  (if (procedure? s)
      (let ([acc '()])
        (parameterize ([current-emit-sink (λ (o) (set! acc (cons o acc)))])
          (s))
        (reverse acc))
      '()))

;; ── 输出 ─────────────────────────────────────────────────

(define (put-styled name v)
  (emit (ops-append (style->bytes name) v format-reset)))

(define (format-styled name v)
  (ops-append (style->bytes name) v format-reset))

(define (format-styled-at row col name v)
  (op 'at (list row col (format-styled name v))))

(define (format-styled-at! row col name v)
  (op 'at! (list row col (format-styled name v))))

(define (put-styled-at row col name v)
  (emit (format-styled-at row col name v)))

(define (put-styled-at! row col name v)
  (emit (format-styled-at! row col name v)))

(define (format-styled* name v)
  (ops-append (style->bytes name) v))

;; ── 属性族 ───────────────────────────────────────────────

(define (attr-style attr)
  (λ (v) (ops-append attr v format-reset)))

(define (format-styled-bold v) (ops-append format-bold v format-reset))
(define (format-styled-dim v) (ops-append format-dim v format-reset))
(define (format-styled-italic v) (ops-append format-italic v format-reset))
(define (format-styled-underline v) (ops-append format-underline v format-reset))
(define (format-styled-blink v) (ops-append format-blink v format-reset))
(define (format-styled-reverse v) (ops-append format-reverse v format-reset))

(define (format-styled-attr-at row col fmt v)
  (op 'at (list row col (fmt v))))
(define (format-styled-attr-at! row col fmt v)
  (op 'at! (list row col (fmt v))))

(define (format-styled-bold-at row col v) (format-styled-attr-at row col format-styled-bold v))
(define (format-styled-bold-at! row col v) (format-styled-attr-at! row col format-styled-bold v))
(define (format-styled-dim-at row col v) (format-styled-attr-at row col format-styled-dim v))
(define (format-styled-dim-at! row col v) (format-styled-attr-at! row col format-styled-dim v))
(define (format-styled-italic-at row col v) (format-styled-attr-at row col format-styled-italic v))
(define (format-styled-italic-at! row col v) (format-styled-attr-at! row col format-styled-italic v))
(define (format-styled-underline-at row col v) (format-styled-attr-at row col format-styled-underline v))
(define (format-styled-underline-at! row col v) (format-styled-attr-at! row col format-styled-underline v))
(define (format-styled-blink-at row col v) (format-styled-attr-at row col format-styled-blink v))
(define (format-styled-blink-at! row col v) (format-styled-attr-at! row col format-styled-blink v))
(define (format-styled-reverse-at row col v) (format-styled-attr-at row col format-styled-reverse v))
(define (format-styled-reverse-at! row col v) (format-styled-attr-at! row col format-styled-reverse v))

(define (put-styled-bold v) (emit (format-styled-bold v)))
(define (put-styled-bold-at row col v) (emit (format-styled-bold-at row col v)))
(define (put-styled-bold-at! row col v) (emit (format-styled-bold-at! row col v)))
(define (put-styled-dim v) (emit (format-styled-dim v)))
(define (put-styled-dim-at row col v) (emit (format-styled-dim-at row col v)))
(define (put-styled-dim-at! row col v) (emit (format-styled-dim-at! row col v)))
(define (put-styled-italic v) (emit (format-styled-italic v)))
(define (put-styled-italic-at row col v) (emit (format-styled-italic-at row col v)))
(define (put-styled-italic-at! row col v) (emit (format-styled-italic-at! row col v)))
(define (put-styled-underline v) (emit (format-styled-underline v)))
(define (put-styled-underline-at row col v) (emit (format-styled-underline-at row col v)))
(define (put-styled-underline-at! row col v) (emit (format-styled-underline-at! row col v)))
(define (put-styled-blink v) (emit (format-styled-blink v)))
(define (put-styled-blink-at row col v) (emit (format-styled-blink-at row col v)))
(define (put-styled-blink-at! row col v) (emit (format-styled-blink-at! row col v)))
(define (put-styled-reverse v) (emit (format-styled-reverse v)))
(define (put-styled-reverse-at row col v) (emit (format-styled-reverse-at row col v)))
(define (put-styled-reverse-at! row col v) (emit (format-styled-reverse-at! row col v)))

;; ── 颜色构造器 ───────────────────────────────────────────

(define (color-fg n)
  (unless (<= 0 n 15) (error 'color-fg "ANSI color must be 0-15, got ~a" n))
  (λ () (emit (format-fg-base n))))

(define (color-bg n)
  (unless (<= 0 n 15) (error 'color-bg "ANSI color must be 0-15, got ~a" n))
  (λ () (emit (format-bg-base n))))

(define (color256-fg n)
  (unless (<= 0 n 255) (error 'color256-fg "256 color must be 0-255, got ~a" n))
  (λ () (emit (format-256-fg-base n))))

(define (color256-bg n)
  (unless (<= 0 n 255) (error 'color256-bg "256 color must be 0-255, got ~a" n))
  (λ () (emit (format-256-bg-base n))))

(define (color-rgb-fg r g b)
  (λ () (emit (format-rgb-fg-base r g b))))

(define (color-rgb-bg r g b)
  (λ () (emit (format-rgb-bg-base r g b))))

(define attr-bold      (λ () (emit format-bold)))
(define attr-dim       (λ () (emit format-dim)))
(define attr-italic    (λ () (emit format-italic)))
(define attr-underline (λ () (emit format-underline)))
(define attr-blink     (λ () (emit format-blink)))
(define attr-reverse   (λ () (emit format-reverse)))

;; ── 颜色深度 ─────────────────────────────────────────────

(define (detect-color-depth)
  (define term (getenv "TERM"))
  (if (and term (regexp-match? #rx"256color" term))
      registry-256
      registry-16))

(define (use-256color!) (current-registry registry-256))
(define (use-16color!)  (current-registry registry-16))
(define (use-color-auto!) (current-registry (detect-color-depth)))

(provide
 style-define! style-apply! style-reset style->bytes
 current-registry use-256color! use-16color! use-color-auto!
 put-styled put-styled-at put-styled-at!
 put-styled-bold put-styled-bold-at put-styled-bold-at!
 put-styled-dim put-styled-dim-at put-styled-dim-at!
 put-styled-italic put-styled-italic-at put-styled-italic-at!
 put-styled-underline put-styled-underline-at put-styled-underline-at!
 put-styled-blink put-styled-blink-at put-styled-blink-at!
 put-styled-reverse put-styled-reverse-at put-styled-reverse-at!
 format-styled format-styled-at format-styled-at! format-styled*
 color-fg color-bg color256-fg color256-bg color-rgb-fg color-rgb-bg
 color-fg* color-bg*
 attr-bold attr-dim attr-italic attr-underline attr-blink attr-reverse
 format-styled-bold format-styled-bold-at format-styled-bold-at!
 format-styled-dim format-styled-dim-at format-styled-dim-at!
 format-styled-italic format-styled-italic-at format-styled-italic-at!
 format-styled-underline format-styled-underline-at format-styled-underline-at!
 format-styled-blink format-styled-blink-at format-styled-blink-at!
 format-styled-reverse format-styled-reverse-at format-styled-reverse-at!)
