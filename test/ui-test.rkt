#lang racket

(require "../main.rkt")

;; 两个按钮, 位置手动指定
(define btn-ok
  (make-button #:text "OK"
               #:on-activate (λ () (printf "OK~n"))))

(define btn-cancel
  (make-button #:text "Cancel"
               #:on-activate (λ () (printf "Cancel~n"))))

;; specs: (list (list comp x y w h) ...)
;; x,y 0-based, 调度器照单绘制
(run-app (list (list btn-ok     2 1  4 1)
               (list btn-cancel 8 1  8 1)))

(printf "quit~n")
