#lang racket

(require "../component.rkt"
         "../../base/io/build-input.rkt"
         "../../base/io/output-styles.rkt"
         "../../base/io/output-color.rkt"
         "../../base/io/output.rkt")

(provide make-button)

(define (make-button #:text text #:on-activate on-activate)
  (define label (string-append " " text " "))
  (component
   (λ (focused? x y w h)
     (put-styled-at! (+ y 1) (+ x 1)
                     (if focused? 'button-hover 'button)
                     label))
   (build-input #:enter on-activate #:space on-activate)
   #t #t
   (string-length label)
   1
   (box #t)))
