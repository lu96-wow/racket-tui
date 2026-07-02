#lang racket

(require "../component.rkt"
         "../../base/io/build-input.rkt"
         "../../base/io/output-styles.rkt"
         "../../base/io/output-color.rkt"
         "../../base/io/output.rkt")

(provide make-button)

(define (make-button #:text text #:on-activate [on-activate void]
                     #:on-press [on-press void]
                     #:on-release [on-release void])
  (define label (string-append " " text " "))
  (define pressed? (box #f))
  (define dirty    (box #t))

  (component
   (λ (focused? x y w h)
     (define style
       (cond [(unbox pressed?) 'button-pressed]
             [focused? 'button-hover]
             [else 'button]))
     (put-styled-at! y x style label))

   (build-input
    #:enter on-activate
    #:space on-activate
    #:mouse-press (λ (btn mx my mods)
                    (when (eq? btn 'left)
                      (set-box! pressed? #t)
                      (set-box! dirty #t)
                      (on-press)))
    #:mouse-release (λ (btn mx my mods)
                      (when (eq? btn 'left)
                        (when (unbox pressed?)
                          (on-activate))
                        (set-box! pressed? #f)
                        (set-box! dirty #t)
                        (on-release))))

   #t #t
   (string-length label)
   1
   dirty))
