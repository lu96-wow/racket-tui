#lang racket

;; 游标状态代理到当前 grid。
;;
;; 与 base 的差异：base 用两个全局变量跟踪光标；char 后端以 grid 光标为真相，
;; 这里把变量同步成 ANSI 1-based（与 base 的语义一致），供 put-newline /
;; cursor-up 等仍按变量计算位置的函数使用。

(require "../screen/grid.rkt"
         "../screen/session.rkt")

(provide current-cursor-row current-cursor-col
         set-cursor! get-cursor update-cursor! sync-cursor!)

(define current-cursor-row 1)
(define current-cursor-col 1)

(define (sync-cursor! g)
  (set! current-cursor-row (+ 1 (grid-cursor-row g)))
  (set! current-cursor-col (+ 1 (grid-cursor-col g))))

(define (set-cursor! row col)
  (set! current-cursor-row row)
  (set! current-cursor-col col))

(define (get-cursor)
  (values current-cursor-row current-cursor-col))

(define (update-cursor!)
  (sync-cursor! (the-screen))
  (get-cursor))
