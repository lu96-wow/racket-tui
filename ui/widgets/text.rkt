#lang racket

(require "../component.rkt"
         "../../base/io/build-input.rkt"
         "../../base/io/output-styles.rkt"
         "../../base/io/output-color.rkt"
         "../../base/io/output.rkt")

(provide make-text)

(define (make-text #:text text #:style [style 'info] #:h-align [h-align 'left])
  ;; text 可以是 string 或 (-> string)
  (define get-text (if (string? text) (λ () text) text))
  (define dirty (box #t))
  (define last-text (box ""))

  (define (render? x y w h focused?)
    (define current (get-text))
    (unless (equal? current (unbox last-text))
      (set-box! last-text current)
      (set-box! dirty #t)))

  (component
   (λ (focused? x y w h)
     (define s (get-text))
     (define visible (if (> (string-length s) w)
                        (substring s 0 w)
                        s))
     (define visible-w (string-length visible))
     (define x-off
       (case h-align
         [(center) (quotient (max 0 (- w visible-w)) 2)]
         [(right)  (max 0 (- w visible-w))]
         [else 0]))
     (for ([i (in-range h)])
       (cursor-move (+ y i) x)
       (put-string (make-string w #\space)))
     (put-styled-at! y (+ x x-off) style visible))

   (build-input)
   #f #t (string-length (get-text)) 1 dirty
   render?))
