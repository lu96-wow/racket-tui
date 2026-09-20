#lang racket

;; char 后端的「格式化」层 —— 与 base/ansi/ansi-format.rkt 同名同签名，
;; 但返回的是 op / op-seq 而不是 ANSI 字节。
;;
;; 因为返回值不再是 bytes，批量拼接要用 base-char 覆盖过的 bytes-append
;; （见 base-char/main.rkt），它等价于 ops-append。

(require "../screen/ops.rkt")

(provide format-content
         format-cursor-move format-cursor-up format-cursor-down
         format-cursor-right format-cursor-left format-cursor-col
         format-cursor-save format-cursor-restore
         format-cursor-home format-cursor-hide format-cursor-show
         format-screen-clear format-screen-clear-below format-screen-clear-above
         format-line-clear format-line-clear-right format-line-clear-left
         format-buffer-alt-enable format-buffer-alt-disable
         format-reset
         format-fg-base format-bg-base
         format-rgb-fg-base format-rgb-bg-base format-rgb-fg-bg-base
         format-256-fg-base format-256-bg-base
         format-fg format-bg
         format-rgb-fg format-rgb-bg format-rgb-fg-bg
         format-256-fg format-256-bg
         format-bold format-dim format-italic
         format-underline format-blink format-reverse
         format-content-at format-content-at!
         format-fg-at format-fg-at!
         format-bg-at format-bg-at!
         format-rgb-fg-at format-rgb-fg-at!
         format-rgb-bg-at format-rgb-bg-at!
         format-256-fg-at format-256-fg-at!
         format-256-bg-at format-256-bg-at!
         format-rgb-fg-bg-at format-rgb-fg-bg-at!)

(define (format-content v) (->ops v))

;; ── 基础序列 ─────────────────────────────────────────────

(define format-cursor-save (op 'save '()))
(define format-cursor-restore (op 'restore '()))
(define format-cursor-home (op 'home '()))
(define format-cursor-hide (op 'cursor-hide '()))
(define format-cursor-show (op 'cursor-show '()))
(define format-screen-clear (op 'erase-screen '(2)))
(define format-screen-clear-below (op 'erase-screen '(0)))
(define format-screen-clear-above (op 'erase-screen '(1)))
(define format-line-clear (op 'erase-line '(2)))
(define format-line-clear-right (op 'erase-line '(0)))
(define format-line-clear-left (op 'erase-line '(1)))
(define format-buffer-alt-enable (op 'alt-enable '()))
(define format-buffer-alt-disable (op 'alt-disable '()))
(define format-reset (op 'sgr '(0)))

(define (format-cursor-move row col) (op 'move-abs (list row col)))
(define (format-cursor-up n) (op 'move-rel (list (- n) 0)))
(define (format-cursor-down n) (op 'move-rel (list n 0)))
(define (format-cursor-right n) (op 'move-rel (list 0 n)))
(define (format-cursor-left n) (op 'move-rel (list 0 (- n))))
(define (format-cursor-col n) (op 'move-col (list n)))

;; ── 颜色 base（与 base 一致的 16 色映射）─────────────────

(define (fg-code n)
  (cond [(= n 9) 39] [(< n 8) (+ 30 n)] [else (+ 90 (- n 8))]))

(define (bg-code n)
  (cond [(= n 9) 49] [(< n 8) (+ 40 n)] [else (+ 100 (- n 8))]))

(define (format-fg-base n) (op 'sgr (list (fg-code n))))
(define (format-bg-base n) (op 'sgr (list (bg-code n))))
(define (format-rgb-fg-base r g b) (op 'sgr (list 38 2 r g b)))
(define (format-rgb-bg-base r g b) (op 'sgr (list 48 2 r g b)))
(define (format-rgb-fg-bg-base fr fg fb br bg bb)
  (op 'sgr (list 38 2 fr fg fb 48 2 br bg bb)))
(define (format-256-fg-base n) (op 'sgr (list 38 5 n)))
(define (format-256-bg-base n) (op 'sgr (list 48 5 n)))

;; ── 转义+内容（自动 reset）──────────────────────────────

(define (format-fg n v) (ops-append (format-fg-base n) v format-reset))
(define (format-bg n v) (ops-append (format-bg-base n) v format-reset))
(define (format-rgb-fg r g b v) (ops-append (format-rgb-fg-base r g b) v format-reset))
(define (format-rgb-bg r g b v) (ops-append (format-rgb-bg-base r g b) v format-reset))
(define (format-rgb-fg-bg fr fg fb br bg bb v)
  (ops-append (format-rgb-fg-bg-base fr fg fb br bg bb) v format-reset))
(define (format-256-fg n v) (ops-append (format-256-fg-base n) v format-reset))
(define (format-256-bg n v) (ops-append (format-256-bg-base n) v format-reset))

;; ── 属性 ─────────────────────────────────────────────────

(define format-bold (op 'sgr '(1)))
(define format-dim (op 'sgr '(2)))
(define format-italic (op 'sgr '(3)))
(define format-underline (op 'sgr '(4)))
(define format-blink (op 'sgr '(5)))
(define format-reverse (op 'sgr '(7)))

;; ── 绝对定位 ─────────────────────────────────────────────

(define (format-content-at row col v)
  (op 'at (list row col v)))
(define (format-content-at! row col v)
  (op 'at! (list row col v)))

(define (format-color-at row col color-op v)
  (op 'at (list row col (ops-append color-op v format-reset))))
(define (format-color-at! row col color-op v)
  (op 'at! (list row col (ops-append color-op v format-reset))))

(define (format-fg-at row col n v) (format-color-at row col (format-fg-base n) v))
(define (format-fg-at! row col n v) (format-color-at! row col (format-fg-base n) v))
(define (format-bg-at row col n v) (format-color-at row col (format-bg-base n) v))
(define (format-bg-at! row col n v) (format-color-at! row col (format-bg-base n) v))
(define (format-rgb-fg-at row col r g b v)
  (format-color-at row col (format-rgb-fg-base r g b) v))
(define (format-rgb-fg-at! row col r g b v)
  (format-color-at! row col (format-rgb-fg-base r g b) v))
(define (format-rgb-bg-at row col r g b v)
  (format-color-at row col (format-rgb-bg-base r g b) v))
(define (format-rgb-bg-at! row col r g b v)
  (format-color-at! row col (format-rgb-bg-base r g b) v))
(define (format-256-fg-at row col n v)
  (format-color-at row col (format-256-fg-base n) v))
(define (format-256-fg-at! row col n v)
  (format-color-at! row col (format-256-fg-base n) v))
(define (format-256-bg-at row col n v)
  (format-color-at row col (format-256-bg-base n) v))
(define (format-256-bg-at! row col n v)
  (format-color-at! row col (format-256-bg-base n) v))
(define (format-rgb-fg-bg-at row col fr fg fb br bg bb v)
  (format-color-at row col (format-rgb-fg-bg-base fr fg fb br bg bb) v))
(define (format-rgb-fg-bg-at! row col fr fg fb br bg bb v)
  (format-color-at! row col (format-rgb-fg-bg-base fr fg fb br bg bb) v))
