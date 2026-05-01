;; output.rkt - 移除颜色输出部分
#lang racket

(require racket/bytes)

;; ================= 光标追踪 =================
(define current-cursor-row 0)
(define current-cursor-col 0)

(define (set-cursor! row col)
  (set! current-cursor-row row)
  (set! current-cursor-col col))

;; ================= 基础输出 =================
(define (put-byte b)        (write-byte b)  (flush-output))
(define (put-bytes bs)      (write-bytes bs) (flush-output))
(define (put-char c)        (write-char c)  (flush-output))
(define (put-string s)      (display s)     (flush-output))

(define (put-newline)
  (put-string "\r\n")
  (set-cursor! (+ current-cursor-row 1) 0))

(define (put v)
  (cond [(string? v) (put-string v)]
        [(bytes? v)  (put-bytes v)]
        [(char? v)   (put-char v)]
        [(integer? v) (put-byte v)]
        [else (void)]))

;; ================= 光标控制 =================
(define (cursor-up n)
  (put-string (format "\e[~aA" n))
  (set-cursor! (max 0 (- current-cursor-row n)) current-cursor-col))

(define (cursor-down n)
  (put-string (format "\e[~aB" n))
  (set-cursor! (+ current-cursor-row n) current-cursor-col))

(define (cursor-right n)
  (put-string (format "\e[~aC" n))
  (set-cursor! current-cursor-row (+ current-cursor-col n)))

(define (cursor-left n)
  (put-string (format "\e[~aD" n))
  (set-cursor! current-cursor-row (max 0 (- current-cursor-col n))))

(define (cursor-move row col)
  (put-string (format "\e[~a;~aH" row col))
  (set-cursor! row col))

(define (cursor-col n)
  (put-string (format "\e[~aG" n))
  (set-cursor! current-cursor-row n))

(define (cursor-home)
  (put-string "\e[H")
  (set-cursor! 0 0))

(define (cursor-hide)  (put-string "\e[?25l"))
(define (cursor-show)  (put-string "\e[?25h"))

;; ================= 屏幕控制 =================
(define (screen-clear)
  (put-string "\e[2J")
  (set-cursor! 0 0))

(define (screen-clear-below)   (put-string "\e[0J"))
(define (screen-clear-above)   (put-string "\e[1J"))
(define (line-clear)           (put-string "\e[2K"))
(define (line-clear-right)     (put-string "\e[0K"))
(define (line-clear-left)      (put-string "\e[1K"))
(define (buffer-alt-enable)    (put-string "\e[?1049h"))
(define (buffer-alt-disable)   (put-string "\e[?1049l"))

;; ================= 绝对位置输出 =================
(define (put-at row col v)
  (define old-r current-cursor-row)
  (define old-c current-cursor-col)
  (cursor-move row col)
  (put v)
  (cursor-move old-r old-c))

(define (put-at! row col v)
  (cursor-move row col)
  (put v))

;; ================= 导出 =================
(provide put put-byte put-bytes put-char put-string put-newline
         put-at put-at!
         cursor-up cursor-down cursor-right cursor-left
         cursor-move cursor-col cursor-home
         cursor-hide cursor-show
         screen-clear screen-clear-below screen-clear-above
         line-clear line-clear-right line-clear-left
         buffer-alt-enable buffer-alt-disable
         current-cursor-row current-cursor-col)