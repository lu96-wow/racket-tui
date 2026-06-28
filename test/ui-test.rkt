#lang racket

(require "../main.rkt")

(define btn-ok
  (make-button #:text "OK"
               #:on-activate (λ () (printf "OK~n"))))

(define btn-cancel
  (make-button #:text "Cancel"
               #:on-activate (λ () (printf "Cancel~n"))))

(run-app (list (list btn-ok     2 1  4 1)
               (list btn-cancel 8 1  8 1)))

(printf "quit~n")
