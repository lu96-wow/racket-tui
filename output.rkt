#lang racket

(require "ansi-format.rkt"
         "cursor-state.rkt")

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

(define (put-newline)
  (put-string "\r\n")
  (set-cursor! (+ current-cursor-row 1) 0))

;; 光标控制
(define (cursor-up n)   (put-bytes (format-cursor-up n))   (set-cursor! (max 0 (- current-cursor-row n)) current-cursor-col))
(define (cursor-down n) (put-bytes (format-cursor-down n)) (set-cursor! (+ current-cursor-row n) current-cursor-col))
(define (cursor-right n)(put-bytes (format-cursor-right n))(set-cursor! current-cursor-row (+ current-cursor-col n)))
(define (cursor-left n) (put-bytes (format-cursor-left n)) (set-cursor! current-cursor-row (max 0 (- current-cursor-col n))))
(define (cursor-move row col) (put-bytes (format-cursor-move row col)) (set-cursor! row col))
(define (cursor-col n)  (put-bytes (format-cursor-col n)) (set-cursor! current-cursor-row n))
(define (cursor-home)   (put-bytes format-cursor-home) (set-cursor! 0 0))
(define (cursor-hide)   (put-bytes format-cursor-hide))
(define (cursor-show)   (put-bytes format-cursor-show))

;; 屏幕控制
(define (screen-clear)        (put-bytes format-screen-clear) (set-cursor! 0 0))
(define (screen-clear-below)  (put-bytes format-screen-clear-below))
(define (screen-clear-above)  (put-bytes format-screen-clear-above))
(define (line-clear)          (put-bytes format-line-clear))
(define (line-clear-right)    (put-bytes format-line-clear-right))
(define (line-clear-left)     (put-bytes format-line-clear-left))
(define (buffer-alt-enable)   (put-bytes format-buffer-alt-enable))
(define (buffer-alt-disable)  (put-bytes format-buffer-alt-disable))

;; 颜色输出
(define (put-fg n v)
  (put-bytes (bytes-append (format-fg n) (format-content v) format-reset)))

(define (put-bg n v)
  (put-bytes (bytes-append (format-bg n) (format-content v) format-reset)))

(define (put-rgb-fg r g b v)
  (put-bytes (bytes-append (format-rgb-fg r g b) (format-content v) format-reset)))

(define (put-rgb-bg r g b v)
  (put-bytes (bytes-append (format-rgb-bg r g b) (format-content v) format-reset)))

(define (put-256-fg n v)
  (put-bytes (bytes-append (format-256-fg n) (format-content v) format-reset)))

(define (put-256-bg n v)
  (put-bytes (bytes-append (format-256-bg n) (format-content v) format-reset)))

;; 绝对位置输出
(define (put-at row col v)
  (put-bytes (format-content-at row col v)))

(define (put-at! row col v)
  (put-bytes (format-content-at! row col v)))

;; 导出
(provide put put-byte put-bytes put-char put-string put-newline
         put-at put-at!
         cursor-up cursor-down cursor-right cursor-left
         cursor-move cursor-col cursor-home
         cursor-hide cursor-show
         screen-clear screen-clear-below screen-clear-above
         line-clear line-clear-right line-clear-left
         buffer-alt-enable buffer-alt-disable
         current-cursor-row current-cursor-col
         set-immediate-mode! set-buffered-mode! flush!
         put-fg put-bg put-rgb-fg put-rgb-bg put-256-fg put-256-bg)