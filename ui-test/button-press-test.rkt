#lang racket

(require "../main.rkt"
         "../ui/run.rkt"
         "../ui/component.rkt"
         "../ui/widgets/button.rkt"
         "../base/io/build-input.rkt"
         "../base/io/output.rkt"
         "../base/io/output-styles.rkt")

(define last-action (box "none"))

(define (make-header)
  (component
    (λ (focused? x y w h)
      (put-styled-at! y x 'title (format "Last: ~a" (unbox last-action))))
    (build-input)
    #f #t 40 1 (box #t)))

(define (on-press name)
  (λ ()
    (set-box! last-action (format "press button ~a" name))))

(define specs
  (list (list (make-header) 1 1 40 1)
        (list (make-button #:text "A" #:on-press (on-press "A")) 1 3 0 0)
        (list (make-button #:text "B" #:on-press (on-press "B")) 1 5 0 0)
        (list (make-button #:text "C" #:on-press (on-press "C")) 1 7 0 0)))

(run-app specs)
