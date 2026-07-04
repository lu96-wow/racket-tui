#lang racket
;; scrollbar 子组件 — 通用滚动条，不持有滚动状态，只持拖拽状态

(require "../../base/io/output-styles.rkt"
         "../../base/io/output-color.rkt"
         "../../base/io/output.rkt")

(provide make-scrollbar
         scrollbar-render scrollbar-press scrollbar-move scrollbar-release
         scrollbar?)

(struct scrollbar (render press move release dragging?)
  #:mutable #:transparent)

(define (make-scrollbar #:track-style [track-style 'scroll-track]
                        #:thumb-style [thumb-style 'scroll-thumb])
  (define dragging? (box #f))

  (define (render x y h total sy)
    (define thumb-h (max 1 (quotient (* h h) total)))
    (define thumb-y (quotient (* sy (- h thumb-h)) (max 1 (- total h))))
    (for ([row (in-range h)])
      (define in-thumb? (<= thumb-y row (+ thumb-y thumb-h -1)))
      (write-bytes (format-styled-at (+ y row) x
                     (if in-thumb? thumb-style track-style)
                     (if in-thumb? "█" "│")))))

  (define (calc-scroll my y h total)
    (let* ([rel-row (- my y)]
           [max-sy (max 0 (- total h))]
           [new-scroll (max 0 (min (quotient (* rel-row max-sy) (max 1 (- h 1))) max-sy))])
      new-scroll))

  (define (press my y h total sy)
    (if (and (> total h) (<= y my (+ y h -1)))
        (begin (set-box! dragging? #t)
               (values (calc-scroll my y h total) #t))
        (values sy #f)))

  (define (move my y h total sy)
    ;; 允许鼠标越界 — calc-scroll 自动 clamp，拖拽更顺滑
    (if (and (unbox dragging?) (> total h))
        (values (calc-scroll my y h total) #t)
        (values sy #f)))

  (define (release)
    (set-box! dragging? #f))

  (scrollbar render press move release dragging?))
