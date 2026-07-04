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

  (define (thumb-pos sy h total)
    (define thumb-h (max 1 (quotient (* h h) total)))
    (define thumb-y (quotient (* sy (- h thumb-h)) (max 1 (- total h))))
    (values thumb-y thumb-h))

  (define (scroll-from-thumb-y thumb-y h total)
    ;; 从滑块顶部位置反算 scroll
    (define thumb-h (max 1 (quotient (* h h) total)))
    (define range (max 1 (- total h)))
    (define range-px (max 1 (- h thumb-h)))
    (max 0 (min (quotient (* thumb-y range) range-px) range)))

  ;; 鼠标 y 坐标 → scroll 值（用浮点避免整数累积误差）
  (define (my->scroll my y h total)
    (define thumb-h (max 1 (quotient (* h h) total)))
    (define range-px (max 1 (- h thumb-h)))
    (define range (max 1 (- total h)))
    (define rel (- my y))
    (max 0 (min (inexact->exact (round (/ (* rel range) range-px 1.0))) range)))

  (define (press my y h total sy)
    (if (and (> total h) (<= y my (+ y h -1)))
        (begin
          (set-box! dragging? #t)
          (values (my->scroll my y h total) #t))
        (values sy #f)))

  (define (move my y h total sy)
    (if (and (unbox dragging?) (> total h))
        (values (my->scroll my y h total) #t)
        (values sy #f)))

  (define (release)
    (set-box! dragging? #f))

  (scrollbar render press move release dragging?))
