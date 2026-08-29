#lang racket

(require "../ansi/ansi-format.rkt"
         "../terminal/cursor-state.rkt"
         "../ansi/ansi-var.rkt")

;; 核心输出函数（可切换缓冲模式）
(define current-write-bytes (λ (bs) (write-bytes bs) (flush-output)))
(define current-write-byte  (λ (b) (write-byte b) (flush-output)))
(define current-write-char  (λ (c) (write-char c) (flush-output)))
(define current-display     (λ (s) (display s) (flush-output)))

(define (set-immediate-mode!)
  (set! current-write-bytes (λ (bs) (write-bytes bs) (flush-output)))
  (set! current-write-byte  (λ (b) (write-byte b) (flush-output)))
  (set! current-write-char  (λ (c) (write-char c) (flush-output)))
  (set! current-display     (λ (s) (display s) (flush-output))))

(define (set-buffered-mode!)
  (set! current-write-bytes (λ (bs) (write-bytes bs)))
  (set! current-write-byte  (λ (b) (write-byte b)))
  (set! current-write-char  (λ (c) (write-char c)))
  (set! current-display     (λ (s) (display s))))

(define (flush!) (flush-output))

;; 基础输出
(define (put-byte b) (current-write-byte b))
(define (put-bytes bs) (current-write-bytes bs))
(define (put-char c) (current-write-char c))
(define (put-string s) (current-display s))

(define (put v)
  (cond [(string? v) (put-string v)]
        [(bytes? v) (put-bytes v)]
        [(char? v) (put-char v)]
        [(integer? v) (put-byte v)]
        [else (void)]))

;; 批量拼接并输出，省去手动 (bytes-append ...) + put-bytes
(define (put-format-bytes . parts)
  (put-bytes (apply bytes-append parts)))

(define (put-newline)
  (put-string (unbox newline-var))
  (set-cursor! (+ current-cursor-row 1) 1))

(define (format-newline)
  (string->bytes/utf-8 (unbox newline-var)))

;; 光标控制
(define (cursor-up n)   (put-bytes (format-cursor-up n))   (set-cursor! (max 1 (- current-cursor-row n)) current-cursor-col))
(define (cursor-down n) (put-bytes (format-cursor-down n)) (set-cursor! (+ current-cursor-row n) current-cursor-col))
(define (cursor-right n)(put-bytes (format-cursor-right n))(set-cursor! current-cursor-row (+ current-cursor-col n)))
(define (cursor-left n) (put-bytes (format-cursor-left n)) (set-cursor! current-cursor-row (max 1 (- current-cursor-col n))))
(define (cursor-move row col) (put-bytes (format-cursor-move row col)) (set-cursor! row col))
(define (cursor-col n)  (put-bytes (format-cursor-col n)) (set-cursor! current-cursor-row n))
(define (cursor-home)   (put-bytes format-cursor-home) (set-cursor! 1 1))
(define (cursor-hide)   (put-bytes format-cursor-hide))
(define (cursor-show)   (put-bytes format-cursor-show))

;; 屏幕控制
(define (screen-clear)        (put-bytes format-screen-clear) (set-cursor! 1 1))
(define (screen-clear-below)  (put-bytes format-screen-clear-below))
(define (screen-clear-above)  (put-bytes format-screen-clear-above))
(define (line-clear)          (put-bytes format-line-clear))
(define (line-clear-right)    (put-bytes format-line-clear-right))
(define (line-clear-left)     (put-bytes format-line-clear-left))
(define (buffer-alt-enable)   (put-bytes format-buffer-alt-enable))
(define (buffer-alt-disable)  (put-bytes format-buffer-alt-disable))

;; 颜色输出
(define (put-fg n v)
  (put-bytes (format-fg n v)))

(define (put-bg n v)
  (put-bytes (format-bg n v)))

(define (put-rgb-fg r g b v)
  (put-bytes (format-rgb-fg r g b v)))

(define (put-rgb-bg r g b v)
  (put-bytes (format-rgb-bg r g b v)))

(define (put-rgb-fg-bg fr fg fb br bg bb v)
  (put-bytes (format-rgb-fg-bg fr fg fb br bg bb v)))

(define (put-256-fg n v)
  (put-bytes (format-256-fg n v)))

(define (put-256-bg n v)
  (put-bytes (format-256-bg n v)))

;; ── 独立 SGR 输出（不带内容、不带位置）──
;; 对应 format-*-base，直接输出纯转义序列
;; 例: (put-fg-base 1) (put-bold) (put-256-bg-base 208)
(define (put-fg-base n) (put-bytes (format-fg-base n)))
(define (put-bg-base n) (put-bytes (format-bg-base n)))
(define (put-rgb-fg-base r g b) (put-bytes (format-rgb-fg-base r g b)))
(define (put-rgb-bg-base r g b) (put-bytes (format-rgb-bg-base r g b)))
(define (put-rgb-fg-bg-base fr fg fb br bg bb)
  (put-bytes (format-rgb-fg-bg-base fr fg fb br bg bb)))
(define (put-256-fg-base n) (put-bytes (format-256-fg-base n)))
(define (put-256-bg-base n) (put-bytes (format-256-bg-base n)))

;; 属性直接输出（不带内容、不带位置）
(define (put-bold)      (put-bytes format-bold))
(define (put-dim)       (put-bytes format-dim))
(define (put-italic)    (put-bytes format-italic))
(define (put-underline) (put-bytes format-underline))
(define (put-blink)     (put-bytes format-blink))
(define (put-reverse)   (put-bytes format-reverse))

;; 绝对位置输出
(define (put-at row col v)
  (put-bytes (format-content-at row col v)))

(define (put-at! row col v)
  (put-bytes (format-content-at! row col v)))

;; 彩色定位输出（与 format-*-at 对称，DECSC/DECRC 由终端保存/恢复光标）
(define (put-fg-at row col n v) (put-bytes (format-fg-at row col n v)))
(define (put-fg-at! row col n v) (put-bytes (format-fg-at! row col n v)))
(define (put-bg-at row col n v) (put-bytes (format-bg-at row col n v)))
(define (put-bg-at! row col n v) (put-bytes (format-bg-at! row col n v)))
(define (put-rgb-fg-at row col r g b v)
  (put-bytes (format-rgb-fg-at row col r g b v)))
(define (put-rgb-fg-at! row col r g b v)
  (put-bytes (format-rgb-fg-at! row col r g b v)))
(define (put-rgb-bg-at row col r g b v)
  (put-bytes (format-rgb-bg-at row col r g b v)))
(define (put-rgb-bg-at! row col r g b v)
  (put-bytes (format-rgb-bg-at! row col r g b v)))
(define (put-rgb-fg-bg-at row col fr fg fb br bg bb v)
  (put-bytes (format-rgb-fg-bg-at row col fr fg fb br bg bb v)))
(define (put-rgb-fg-bg-at! row col fr fg fb br bg bb v)
  (put-bytes (format-rgb-fg-bg-at! row col fr fg fb br bg bb v)))
(define (put-256-fg-at row col n v) (put-bytes (format-256-fg-at row col n v)))
(define (put-256-fg-at! row col n v) (put-bytes (format-256-fg-at! row col n v)))
(define (put-256-bg-at row col n v) (put-bytes (format-256-bg-at row col n v)))
(define (put-256-bg-at! row col n v) (put-bytes (format-256-bg-at! row col n v)))

;; 光标保存/恢复（与 format-cursor-save/restore 对称）
(define (put-cursor-save) (put-bytes format-cursor-save))
(define (put-cursor-restore) (put-bytes format-cursor-restore))

;; 样式重置（与 format-reset 对称）
(define (put-reset) (put-bytes format-reset))

;; 导出
(provide put put-byte put-bytes put-format-bytes put-char put-string put-newline
         format-newline
         put-at put-at!
         cursor-up cursor-down cursor-right cursor-left
         cursor-move cursor-col cursor-home
         cursor-hide cursor-show
         screen-clear screen-clear-below screen-clear-above
         line-clear line-clear-right line-clear-left
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
         put-bold put-dim put-italic put-underline put-blink put-reverse)