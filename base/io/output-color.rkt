#lang racket

(require "output.rkt"
         "../terminal/cursor-state.rkt"
         "../ansi/ansi-format.rkt")

;; ═══════════════════════════════════════════════════════
;; 样式系统 — 双表 256/16 自动回退
;;
;;   两个 hash: registry-256 和 registry-16
;;   style-define! 同时注册到两个表
;;   应用时通过 current-registry 参数选表 — 纯 hash 查询，零分支
;;   color-fg*/bg* 构造双色 thunk (struct color-thunk)
;;   普通 color-fg/attr-bold 等双表一致，自动放两边
;; ═══════════════════════════════════════════════════════

(define (make-style . specs)
  ;; 过滤 #f (color-thunk 缺省侧), 保证双表注册安全
  (λ () (for-each (λ (s) (s)) (filter procedure? specs))))

(define registry-256 (make-hash))
(define registry-16  (make-hash))
(define current-registry (make-parameter registry-16))

;; ── 双色构造器 ──

(struct color-thunk (do-256 do-16) #:transparent)

(define (color-fg* c256 c16)
  (unless (<= 0 c16 15)  (error 'color-fg* "16-color value must be 0-15, got ~a" c16))
  (unless (<= 0 c256 255) (error 'color-fg* "256-color value must be 0-255, got ~a" c256))
  (color-thunk (color256-fg c256) (color-fg c16)))

(define (color-bg* c256 c16)
  (unless (<= 0 c16 15)  (error 'color-bg* "16-color value must be 0-15, got ~a" c16))
  (unless (<= 0 c256 255) (error 'color-bg* "256-color value must be 0-255, got ~a" c256))
  (color-thunk (color256-bg c256) (color-bg c16)))

;; ── style-define! — 双表注册 ──

(define (style-define! name . specs)
  (define (resolve pick)
    (apply make-style
           (for/list ([s specs])
             (if (color-thunk? s) (pick s) s))))
  (hash-set! registry-256 name (resolve color-thunk-do-256))
  (hash-set! registry-16  name (resolve color-thunk-do-16)))

;; ── style-apply! / style->bytes — 从当前表取 ──

(define (style-apply! name)
  (define s (hash-ref (current-registry) name void))
  (when (procedure? s) (s)))

(define (style-reset) (put-bytes format-reset))

(define (style->bytes name)
  (define style-proc (hash-ref (current-registry) name void))
  (if (procedure? style-proc)
      (call-with-output-bytes
       (λ (out)
         (parameterize ([current-output-port out])
           (style-proc))))
      (bytes)))

;; ═══════════════════════════════════════════════════════
;; 输出 — put-* / format-*
;; ═══════════════════════════════════════════════════════

(define (put-styled name v)
  (define style-bytes (style->bytes name))
  (put-bytes (bytes-append style-bytes (format-content v) format-reset)))

(define (put-styled-at row col name v)
  ;; 与 format-styled-at 保持一致: DECSC/DECRC 由终端恢复光标
  (put-bytes (format-styled-at row col name v)))

(define (put-styled-at! row col name v)
  (cursor-move row col)
  (put-styled name v))

(define (format-styled name v)
  (define style-bytes (style->bytes name))
  (bytes-append style-bytes (format-content v) format-reset))

(define (format-styled-at row col name v)
  ;; 终端自保存/恢复光标，不依赖内置追踪状态
  (bytes-append format-cursor-save
                (format-cursor-move row col)
                (format-styled name v)
                format-cursor-restore))

(define (format-styled-at! row col name v)
  (set-cursor! row col)
  (bytes-append (format-cursor-move row col)
                (format-styled name v)))

(define (format-styled* name v)
  (define style-bytes (style->bytes name))
  (bytes-append style-bytes (format-content v)))

;; ═══════════════════════════════════════════════════════
;; 颜色构造器
;; ═══════════════════════════════════════════════════════

(define (color-fg n)
  (unless (<= 0 n 15) (error 'color-fg "ANSI color must be 0-15, got ~a" n))
  (λ () (put-bytes (format-fg-base n))))

(define (color-bg n)
  (unless (<= 0 n 15) (error 'color-bg "ANSI color must be 0-15, got ~a" n))
  (λ () (put-bytes (format-bg-base n))))

(define (color256-fg n)
  (unless (<= 0 n 255) (error 'color256-fg "256 color must be 0-255, got ~a" n))
  (λ () (put-bytes (format-256-fg-base n))))

(define (color256-bg n)
  (unless (<= 0 n 255) (error 'color256-bg "256 color must be 0-255, got ~a" n))
  (λ () (put-bytes (format-256-bg-base n))))

(define (color-rgb-fg r g b)
  (unless (<= 0 r 255) (error 'color-rgb-fg "R must be 0-255, got ~a" r))
  (unless (<= 0 g 255) (error 'color-rgb-fg "G must be 0-255, got ~a" g))
  (unless (<= 0 b 255) (error 'color-rgb-fg "B must be 0-255, got ~a" b))
  (λ () (put-bytes (format-rgb-fg-base r g b))))

(define (color-rgb-bg r g b)
  (unless (<= 0 r 255) (error 'color-rgb-bg "R must be 0-255, got ~a" r))
  (unless (<= 0 g 255) (error 'color-rgb-bg "G must be 0-255, got ~a" g))
  (unless (<= 0 b 255) (error 'color-rgb-bg "B must be 0-255, got ~a" b))
  (λ () (put-bytes (format-rgb-bg-base r g b))))

;; ═══════════════════════════════════════════════════════
;; 属性构造器
;; ═══════════════════════════════════════════════════════

(define attr-bold      (λ () (put-bytes format-bold)))
(define attr-dim       (λ () (put-bytes format-dim)))
(define attr-italic    (λ () (put-bytes format-italic)))
(define attr-underline (λ () (put-bytes format-underline)))
(define attr-blink     (λ () (put-bytes format-blink)))
(define attr-reverse   (λ () (put-bytes format-reverse)))

;; ═══════════════════════════════════════════════════════
;; 颜色深度检测 & 切换
;; ═══════════════════════════════════════════════════════

(define (detect-color-depth)
  (define term (getenv "TERM"))
  (if (and term (regexp-match? #rx"256color" term))
      registry-256
      registry-16))

(define (use-256color!)
  (current-registry registry-256))

(define (use-16color!)
  (current-registry registry-16))

(define (use-color-auto!)
  (current-registry (detect-color-depth)))

;; ═══════════════════════════════════════════════════════
;; format-styled-attr (保持不变)
;; ═══════════════════════════════════════════════════════

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

(define (format-styled-attr-at row col fmt-fn v)
  ;; DECSC/DECRC 由终端保存/恢复光标，不依赖内置追踪状态
  (bytes-append format-cursor-save
                (format-cursor-move row col)
                (fmt-fn v)
                format-cursor-restore))

(define (format-styled-attr-at! row col fmt-fn v)
  (set-cursor! row col)
  (bytes-append (format-cursor-move row col) (fmt-fn v)))

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

;; ═══════════════════════════════════════════════════════
;; 导出
;; ═══════════════════════════════════════════════════════

(provide
 ;; 样式管理
 style-define! style-apply! style-reset style->bytes
 current-registry use-256color! use-16color! use-color-auto!
 ;; 立即输出
 put-styled put-styled-at put-styled-at!
 ;; 格式化
 format-styled format-styled-at format-styled-at! format-styled*
 ;; 颜色构造器
 color-fg color-bg color256-fg color256-bg color-rgb-fg color-rgb-bg
 color-fg* color-bg*
 ;; 属性
 attr-bold attr-dim attr-italic attr-underline attr-blink attr-reverse
 ;; 格式化属性
 format-styled-bold format-styled-bold-at format-styled-bold-at!
 format-styled-dim format-styled-dim-at format-styled-dim-at!
 format-styled-italic format-styled-italic-at format-styled-italic-at!
 format-styled-underline format-styled-underline-at format-styled-underline-at!
 format-styled-blink format-styled-blink-at format-styled-blink-at!
 format-styled-reverse format-styled-reverse-at format-styled-reverse-at!)
