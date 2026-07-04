#lang racket

(require "../component.rkt"
         "../../base/io/build-input.rkt"
         "../../base/io/output-styles.rkt"
         "../../base/io/output-color.rkt"
         "../../base/io/output.rkt")

(provide make-button)

(define (make-button #:text text
                     #:on-activate [on-activate void]
                     #:style [style 'button]
                     #:show? [show? (box #t)])
  (define label (string-append " " text " "))
  (define show-box (if (boolean? show?) (box show?) show?))
  (define pressed? (box #f))
  (define dirty    (box #t))

  (component
   (λ (focused? x y w h)
     (define cur-style (if (unbox pressed?) 'button-pressed style))
     (write-bytes (format-styled-at y x cur-style label)))

   (build-input
    #:enter on-activate
    #:space on-activate
    #:mouse-press (λ (btn mx my mods)
                    (when (eq? btn 'left)
                      (set-box! pressed? #t)
                      (set-box! dirty #t)))
    #:mouse-release (λ (btn mx my mods)
                      (when (eq? btn 'left)
                        (when (unbox pressed?)
                          (on-activate))
                        (set-box! pressed? #f)
                        (set-box! dirty #t))))

   #t show-box
   (string-length label)
   1
   dirty
   #f))
