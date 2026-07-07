#lang racket

(require "../ui/main.rkt")

(define last-action (box "none"))

(run-app
  ((make-text #:text (λ () (format "Last: ~a" (unbox last-action)))
              #:style 'title)
   1 1 40 1)
  ((make-button #:text "A"
                #:on-activate (λ () (set-box! last-action "a"))) 2 3 0 0)
  ((make-button #:text "B"
                #:on-activate (λ () (set-box! last-action "b"))) 3 5 0 0)
  ((make-button #:text "C"
                #:on-activate (λ () (set-box! last-action "c"))) 4 7 0 0))
