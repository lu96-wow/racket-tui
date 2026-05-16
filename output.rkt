#lang racket

(require "ansi-format.rkt"
         "cursor-state.rkt"
         "screen-buffer.rkt"
         "resize.rkt")

(define current-screen (make-parameter #f))

(define (screen-mode?) (current-screen))

(define (with-screen-buffer thunk)
  (define buf (make-screen-buffer))
  (parameterize ([current-screen buf])
    (let-values ([(r c) (get-window-size)])
      (sb-ensure! buf r c)
      (sb-clear! buf))
    (thunk)
    (sb-flush! buf)
    buf))

(define (screen-put-bytes bs)
  (define buf (current-screen))
  (sb-put! buf current-cursor-row current-cursor-col bs)
  (set-cursor! current-cursor-row (+ current-cursor-col (bytes-length bs))))

;; 光标控制 - screen-mode 下只更新状态
(define (cursor-up n)
  (unless (screen-mode?) (write-bytes (format-cursor-up n)) (flush-output))
  (set-cursor! (max 0 (- current-cursor-row n)) current-cursor-col))

(define (cursor-down n)
  (unless (screen-mode?) (write-bytes (format-cursor-down n)) (flush-output))
  (set-cursor! (+ current-cursor-row n) current-cursor-col))

(define (cursor-right n)
  (unless (screen-mode?) (write-bytes (format-cursor-right n)) (flush-output))
  (set-cursor! current-cursor-row (+ current-cursor-col n)))

(define (cursor-left n)
  (unless (screen-mode?) (write-bytes (format-cursor-left n)) (flush-output))
  (set-cursor! current-cursor-row (max 0 (- current-cursor-col n))))

(define (cursor-move row col)
  (unless (screen-mode?) (write-bytes (format-cursor-move row col)) (flush-output))
  (set-cursor! row col))

(define (cursor-col n)
  (unless (screen-mode?) (write-bytes (format-cursor-col n)) (flush-output))
  (set-cursor! current-cursor-row n))

(define (cursor-home)
  (unless (screen-mode?) (write-bytes format-cursor-home) (flush-output))
  (set-cursor! 0 0))

(define (cursor-hide)
  (unless (screen-mode?) (write-bytes format-cursor-hide) (flush-output)))

(define (cursor-show)
  (unless (screen-mode?) (write-bytes format-cursor-show) (flush-output)))

;; 基础输出
(define (put-byte b)
  (if (screen-mode?)
      (screen-put-bytes (bytes b))
      (begin (write-byte b) (flush-output))))

(define (put-bytes bs)
  (if (screen-mode?)
      (screen-put-bytes bs)
      (begin (write-bytes bs) (flush-output))))

(define (put-char c)
  (if (screen-mode?)
      (screen-put-bytes (string->bytes/utf-8 (string c)))
      (begin (write-char c) (flush-output))))

(define (put-string s)
  (if (screen-mode?)
      (screen-put-bytes (string->bytes/utf-8 s))
      (begin (display s) (flush-output))))

(define (put v)
  (cond [(string? v) (put-string v)]
        [(bytes? v) (put-bytes v)]
        [(char? v) (put-char v)]
        [(integer? v) (put-byte v)]
        [else (void)]))

(define (put-newline)
  (if (screen-mode?)
      (set-cursor! (+ current-cursor-row 1) 0)
      (begin (display "\r\n") (flush-output)
             (set-cursor! (+ current-cursor-row 1) 0))))

;; flush: screen-mode 下 diff+输出，否则直接 flush
(define (flush!)
  (if (screen-mode?)
      (sb-flush! (current-screen))
      (flush-output)))

;; 屏幕控制
(define (screen-clear)
  (if (screen-mode?)
      (let ([buf (current-screen)])
        (sb-clear! buf)
        (set-cursor! 1 1))
      (begin (write-bytes format-screen-clear) (flush-output)
             (set-cursor! 1 1))))

(define (screen-clear-below)
  (unless (screen-mode?) (write-bytes format-screen-clear-below) (flush-output)))

(define (screen-clear-above)
  (unless (screen-mode?) (write-bytes format-screen-clear-above) (flush-output)))

(define (line-clear)
  (unless (screen-mode?) (write-bytes format-line-clear) (flush-output)))

(define (line-clear-right)
  (unless (screen-mode?) (write-bytes format-line-clear-right) (flush-output)))

(define (line-clear-left)
  (unless (screen-mode?) (write-bytes format-line-clear-left) (flush-output)))

(define (buffer-alt-enable)
  (write-bytes format-buffer-alt-enable) (flush-output))

(define (buffer-alt-disable)
  (write-bytes format-buffer-alt-disable) (flush-output))

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
  (if (screen-mode?)
      (begin (set-cursor! row col) (put v))
      (put-bytes (format-content-at row col v))))

(define (put-at! row col v)
  (if (screen-mode?)
      (begin (set-cursor! row col) (put v))
      (put-bytes (format-content-at! row col v))))

;; 兼容旧的 immediate/buffered API（screen-mode 下忽略）
(define (set-immediate-mode!) (void))
(define (set-buffered-mode!) (void))

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
         put-fg put-bg put-rgb-fg put-rgb-bg put-256-fg put-256-bg
         with-screen-buffer screen-mode? current-screen)
