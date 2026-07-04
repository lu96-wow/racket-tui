#lang racket

(require "../ui/main.rkt")

(define last-action (box "none"))

(define specs
  (list (list (make-text #:text (λ () (format "Last: ~a" (unbox last-action)))
                         #:style 'title)
              0 0 40 1)
        (list (make-button #:text "A"
                           #:on-activate (λ () (set-box! last-action "clicked A"))) 0 2 0 0)
        (list (make-button #:text "B"
                           #:on-activate (λ () (set-box! last-action "clicked B"))) 0 4 0 0)
        (list (make-button #:text "C"
                           #:on-activate (λ () (set-box! last-action "clicked C"))) 0 6 0 0)))

(run-app specs)
