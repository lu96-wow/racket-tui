#lang racket

(require "../component.rkt"
         "../../base/io/build-input.rkt"
         "../../base/io/output-styles.rkt"
         "../../base/io/output-color.rkt"
         "../../base/io/output.rkt")

(provide make-panel)

;; xb, yb, wb, hb 都是 box — handler 和 render 共享同一份
(define (make-panel xb yb wb hb #:color [clr 'selection])
  (define drag-edge (box #f))
  (define drag-base-right (box 0))

  (define (edge mx x w)
    (cond [(<= (abs (- mx x)) 1)          'left]
          [(<= (abs (- mx (+ x w -1))) 1) 'right]
          [else #f]))

  (component
   (λ (focused? x y w h)
     (for ([i (in-range h)])
       (put-styled-at! (+ y 1 i) (+ x 1) clr (make-string w #\space))))

   (build-input
    #:mouse-press (λ (btn mx my mods)
                    (when (eq? btn 'left)
                      (define x (unbox xb))
                      (define w (unbox wb))
                      (set-box! drag-edge (edge mx x w))
                      (set-box! drag-base-right (+ x w -1))))
    #:mouse-release (λ (btn mx my mods)
                      (set-box! drag-edge #f))
    #:mouse-move (λ (mx my mods)
                   (case (unbox drag-edge)
                     [(left)
                      (define r (unbox drag-base-right))
                      (define new-x (min mx (- r 2)))
                      (set-box! xb new-x)
                      (set-box! wb (+ r 1 (- new-x)))]
                     [(right)
                      (set-box! wb (max 3 (+ mx 1 (- (unbox xb)))))]
                     [else (void)])))
   #t #t
   wb
   hb))
