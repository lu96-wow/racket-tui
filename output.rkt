;; output.rkt - 输出函数（带副作用）
#lang racket

(require racket/bytes
         "ansi-format.rkt")

;; 光标追踪
(define current-cursor-row 0)
(define current-cursor-col 0)

(define (set-cursor! row col)
  (set! current-cursor-row row)
  (set! current-cursor-col col))

;; 基础输出
(define (put-byte b)        (write-byte b)  (flush-output))
(define (put-bytes bs)      (write-bytes bs) (flush-output))
(define (put-char c)        (write-char c)  (flush-output))
(define (put-string s)      (display s)     (flush-output))

(define (put v)
  (cond [(string? v) (put-string v)]
        [(bytes? v)  (put-bytes v)]
        [(char? v)   (put-char v)]
        [(integer? v) (put-byte v)]
        [else (void)]))

(define (put-newline)
  (put-string "\r\n")
  (set-cursor! (+ current-cursor-row 1) 0))

;; 光标控制
(define (cursor-up n)
  (put-bytes (format-cursor-up n))
  (set-cursor! (max 0 (- current-cursor-row n)) current-cursor-col))

(define (cursor-down n)
  (put-bytes (format-cursor-down n))
  (set-cursor! (+ current-cursor-row n) current-cursor-col))

(define (cursor-right n)
  (put-bytes (format-cursor-right n))
  (set-cursor! current-cursor-row (+ current-cursor-col n)))

(define (cursor-left n)
  (put-bytes (format-cursor-left n))
  (set-cursor! current-cursor-row (max 0 (- current-cursor-col n))))

(define (cursor-move row col)
  (put-bytes (format-cursor-move row col))
  (set-cursor! row col))

(define (cursor-col n)
  (put-bytes (format-cursor-col n))
  (set-cursor! current-cursor-row n))

(define (cursor-home)
  (put-bytes format-cursor-home)
  (set-cursor! 0 0))

(define (cursor-hide)  (put-bytes format-cursor-hide))
(define (cursor-show)  (put-bytes format-cursor-show))

;; 屏幕控制
(define (screen-clear)
  (put-bytes format-screen-clear)
  (set-cursor! 0 0))

(define (screen-clear-below)   (put-bytes format-screen-clear-below))
(define (screen-clear-above)   (put-bytes format-screen-clear-above))
(define (line-clear)           (put-bytes format-line-clear))
(define (line-clear-right)     (put-bytes format-line-clear-right))
(define (line-clear-left)      (put-bytes format-line-clear-left))
(define (buffer-alt-enable)    (put-bytes format-buffer-alt-enable))
(define (buffer-alt-disable)   (put-bytes format-buffer-alt-disable))

;; 绝对位置输出
(define (put-at row col v)
  (define old-r current-cursor-row)
  (define old-c current-cursor-col)
  (cursor-move row col)
  (put v)
  (cursor-move old-r old-c))

(define (put-at! row col v)
  (cursor-move row col)
  (put v))

;; 导出
(provide put put-byte put-bytes put-char put-string put-newline
         put-at put-at!
         cursor-up cursor-down cursor-right cursor-left
         cursor-move cursor-col cursor-home
         cursor-hide cursor-show
         screen-clear screen-clear-below screen-clear-above
         line-clear line-clear-right line-clear-left
         buffer-alt-enable buffer-alt-disable
         current-cursor-row current-cursor-col)