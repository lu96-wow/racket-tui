#lang racket

;; char 后端的输出层 —— 与 base/io/output.rkt 同名同签名。
;; 区别：不写终端字节，而是把 op 作用到当前 grid。
;;
;; 返回「字节」的函数在这里返回 op / op-seq，因此用 base-char 覆盖的
;; bytes-append（= ops-append）拼接即可，无需任何解析。

(require "../screen/ops.rkt"
         "../screen/grid.rkt"
         "../screen/session.rkt"
         "../screen/sgr.rkt"
         "../ansi/ansi-format.rkt"
         "../ansi/ansi-var.rkt"
         "../terminal/cursor-state.rkt")

;; ── op 应用 ──────────────────────────────────────────────

(define (ansi->0 x) (max 0 (- x 1)))

(define (apply-op! g o)
  (define args (op-args o))
  (case (op-kind o)
    [(text) (apply-content! g (car args))]
    [(at)
     (define r (ansi->0 (list-ref args 0)))
     (define c (ansi->0 (list-ref args 1)))
     (let ([sr (grid-cursor-row g)] [sc (grid-cursor-col g)]
           [sf (grid-fg g)] [sb (grid-bg g)] [sa (grid-attrs g)])
       (grid-move! g r c)
       (apply-content! g (list-ref args 2))
       (set-grid-cursor-row! g sr)
       (set-grid-cursor-col! g sc)
       (set-grid-fg! g sf)
       (set-grid-bg! g sb)
       (set-grid-attrs! g sa))]
    [(at!)
     (grid-move! g (ansi->0 (list-ref args 0)) (ansi->0 (list-ref args 1)))
     (apply-content! g (list-ref args 2))]
    [(move-abs) (grid-move! g (ansi->0 (car args)) (ansi->0 (cadr args)))]
    [(move-rel) (grid-move-rel! g (car args) (cadr args))]
    [(move-col) (grid-move! g (grid-cursor-row g) (ansi->0 (car args)))]
    [(home) (grid-move! g 0 0)]
    [(save) (grid-save! g)]
    [(restore) (grid-restore! g)]
    [(erase-screen) (grid-erase-display! g (car args))]
    [(erase-line) (grid-erase-line! g (car args))]
    [(cursor-hide) (set-grid-cursor-visible?! g #f)]
    [(cursor-show) (set-grid-cursor-visible?! g #t)]
    [(alt-enable) (screen-alt-enable!)]
    [(alt-disable) (screen-alt-disable!)]
    [(sgr) (apply-sgr! g args)]
    [else (void)]))

(define (apply-content! g content)
  (cond
    [(op? content) (apply-op! g content)]
    [(op-seq? content) (for-each (λ (o) (apply-op! g o)) content)]
    [else (write-content! g content)]))

(define (write-content! g v)
  (cond
    [(bytes? v) (write-chars! g (bytes->string/utf-8 v #\uFFFD))]
    [(string? v) (write-chars! g v)]
    [(char? v) (write-chars! g (string v))]
    [else (write-chars! g (format "~a" v))]))

(define (write-chars! g s)
  (for ([ch (in-string s)])
    (case ch
      [(#\newline) (grid-index! g)]
      [(#\return) (grid-carriage-return! g)]
      [(#\backspace) (grid-backspace! g)]
      [(#\tab) (grid-tab! g)]
      [else (grid-put-char! g ch)])))

;; ── 输出（emit）─────────────────────────────────────────
;; current-emit-sink 供样式系统「只取 op 不应用」时使用

(define current-emit-sink (make-parameter #f))

(define (emit v)
  (define ops (->ops v))
  (cond
    [(current-emit-sink) => (λ (sink) (for-each sink ops))]
    [else
     ;; 每个 op 都取当前屏：alt-enable/disable 会切换 (the-screen)，
     ;; 后续 op 必须作用到新屏上
     (for-each (λ (o) (apply-op! (the-screen) o)) ops)
     (sync-cursor! (the-screen))]))

;; 缓冲/立即模式对 grid 无区别
(define (set-immediate-mode!) (void))
(define (set-buffered-mode!) (void))
(define (flush!) (frame-end!))

;; ── 基础输出 ─────────────────────────────────────────────

;; 与 base 的 put-byte 一致：越界即报错（不静默截断）
(define (put-byte b)
  (unless (and (integer? b) (<= 0 b 255))
    (error 'put-byte "expected byte (0-255), got ~a" b))
  (emit (integer->char b)))
(define (put-bytes bs) (emit bs))
(define (put-char c) (emit c))
(define (put-string s) (emit s))
(define (put v)
  (cond [(string? v) (put-string v)]
        [(bytes? v) (put-bytes v)]
        [(char? v) (put-char v)]
        [(integer? v) (put-byte v)]
        [else (void)]))

(define (put-format-bytes . parts)
  (emit (apply ops-append parts)))

(define (put-newline)
  (emit (unbox newline-var)))

(define (format-newline)
  (->ops (unbox newline-var)))

;; ── 光标控制 ─────────────────────────────────────────────

(define (cursor-up n) (emit (format-cursor-up n)))
(define (cursor-down n) (emit (format-cursor-down n)))
(define (cursor-right n) (emit (format-cursor-right n)))
(define (cursor-left n) (emit (format-cursor-left n)))
(define (cursor-move row col) (emit (format-cursor-move row col)))
(define (cursor-col n) (emit (format-cursor-col n)))
(define (cursor-home) (emit format-cursor-home))
(define (cursor-hide) (emit format-cursor-hide))
(define (cursor-show) (emit format-cursor-show))

;; ── 屏幕控制 ─────────────────────────────────────────────

(define (screen-clear)
  (emit format-screen-clear)
  (emit format-cursor-home))
(define (screen-clear-below) (emit format-screen-clear-below))
(define (screen-clear-above) (emit format-screen-clear-above))
(define (line-clear) (emit format-line-clear))
(define (line-clear-right) (emit format-line-clear-right))
(define (line-clear-left) (emit format-line-clear-left))
;; 擦除指定整行（1-based），清完光标回到原位
(define (line-clear-row row) (emit (format-line-clear-row row)))
(define (buffer-alt-enable) (emit format-buffer-alt-enable))
(define (buffer-alt-disable) (emit format-buffer-alt-disable))

;; ── 颜色（带内容）───────────────────────────────────────

(define (put-fg n v) (emit (format-fg n v)))
(define (put-bg n v) (emit (format-bg n v)))
(define (put-rgb-fg r g b v) (emit (format-rgb-fg r g b v)))
(define (put-rgb-bg r g b v) (emit (format-rgb-bg r g b v)))
(define (put-rgb-fg-bg fr fg fb br bg bb v)
  (emit (format-rgb-fg-bg fr fg fb br bg bb v)))
(define (put-256-fg n v) (emit (format-256-fg n v)))
(define (put-256-bg n v) (emit (format-256-bg n v)))

;; ── 独立 SGR（不带内容）─────────────────────────────────

(define (put-fg-base n) (emit (format-fg-base n)))
(define (put-bg-base n) (emit (format-bg-base n)))
(define (put-rgb-fg-base r g b) (emit (format-rgb-fg-base r g b)))
(define (put-rgb-bg-base r g b) (emit (format-rgb-bg-base r g b)))
(define (put-rgb-fg-bg-base fr fg fb br bg bb)
  (emit (format-rgb-fg-bg-base fr fg fb br bg bb)))
(define (put-256-fg-base n) (emit (format-256-fg-base n)))
(define (put-256-bg-base n) (emit (format-256-bg-base n)))

(define (put-bold) (emit format-bold))
(define (put-dim) (emit format-dim))
(define (put-italic) (emit format-italic))
(define (put-underline) (emit format-underline))
(define (put-blink) (emit format-blink))
(define (put-reverse) (emit format-reverse))

;; ── 绝对位置 ─────────────────────────────────────────────

(define (put-at row col v) (emit (format-content-at row col v)))
(define (put-at! row col v) (emit (format-content-at! row col v)))

(define (put-fg-at row col n v) (emit (format-fg-at row col n v)))
(define (put-fg-at! row col n v) (emit (format-fg-at! row col n v)))
(define (put-bg-at row col n v) (emit (format-bg-at row col n v)))
(define (put-bg-at! row col n v) (emit (format-bg-at! row col n v)))
(define (put-rgb-fg-at row col r g b v)
  (emit (format-rgb-fg-at row col r g b v)))
(define (put-rgb-fg-at! row col r g b v)
  (emit (format-rgb-fg-at! row col r g b v)))
(define (put-rgb-bg-at row col r g b v)
  (emit (format-rgb-bg-at row col r g b v)))
(define (put-rgb-bg-at! row col r g b v)
  (emit (format-rgb-bg-at! row col r g b v)))
(define (put-rgb-fg-bg-at row col fr fg fb br bg bb v)
  (emit (format-rgb-fg-bg-at row col fr fg fb br bg bb v)))
(define (put-rgb-fg-bg-at! row col fr fg fb br bg bb v)
  (emit (format-rgb-fg-bg-at! row col fr fg fb br bg bb v)))
(define (put-256-fg-at row col n v) (emit (format-256-fg-at row col n v)))
(define (put-256-fg-at! row col n v) (emit (format-256-fg-at! row col n v)))
(define (put-256-bg-at row col n v) (emit (format-256-bg-at row col n v)))
(define (put-256-bg-at! row col n v) (emit (format-256-bg-at! row col n v)))

(define (put-cursor-save) (emit format-cursor-save))
(define (put-cursor-restore) (emit format-cursor-restore))
(define (put-reset) (emit format-reset))

(provide put put-byte put-bytes put-format-bytes put-char put-string put-newline
         format-newline
         put-at put-at!
         cursor-up cursor-down cursor-right cursor-left
         cursor-move cursor-col cursor-home
         cursor-hide cursor-show
         screen-clear screen-clear-below screen-clear-above
         line-clear line-clear-right line-clear-left line-clear-row
         buffer-alt-enable buffer-alt-disable
         current-cursor-row current-cursor-col
         set-immediate-mode! set-buffered-mode! flush!
         put-fg put-bg put-rgb-fg put-rgb-bg put-rgb-fg-bg put-256-fg put-256-bg
         put-fg-at put-fg-at! put-bg-at put-bg-at!
         put-rgb-fg-at put-rgb-fg-at! put-rgb-bg-at put-rgb-bg-at!
         put-rgb-fg-bg-at put-rgb-fg-bg-at! put-256-fg-at put-256-fg-at!
         put-256-bg-at put-256-bg-at!
         put-cursor-save put-cursor-restore put-reset
         put-fg-base put-bg-base put-rgb-fg-base put-rgb-bg-base
         put-rgb-fg-bg-base put-256-fg-base put-256-bg-base
         put-bold put-dim put-italic put-underline put-blink put-reverse
         current-emit-sink emit)
