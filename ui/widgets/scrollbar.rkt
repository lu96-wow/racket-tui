#lang racket

;; scrollbar — 滚动条渲染 + 拖拽换算（纯函数，不持有状态）
;;
;; 滚动位置由使用方（如 list/output）的 keyed local state 保存。
;; 这里只提供渲染和"鼠标 y → scroll"的换算。

(require "../surface.rkt")

(provide scrollbar-render
         scrollbar-scroll-from-y
         scrollbar-metrics)

;; 返回 (thumb-h track-range range) 三个中间量
(define (scrollbar-metrics h total)
  (define thumb-h (max 1 (quotient (* h h) total)))
  (define range (max 1 (- total h)))
  (define track-range (max 1 (- h thumb-h)))
  (values thumb-h track-range range))

;; 在 (x,y) 处画宽 w 高 h 的滚动条
(define (scrollbar-render surf x y w h total scroll)
  (when (and (> w 0) (> h 0) (> total h))
    (define-values (thumb-h track-range range) (scrollbar-metrics h total))
    (define thumb-y (quotient (* (min scroll range) track-range) range))
    (for ([r (in-range h)])
      (define in-thumb? (<= thumb-y r (+ thumb-y thumb-h -1)))
      (surface-put-string! surf (+ y r) x
        (make-string w (if in-thumb? #\█ #\│))
        (if in-thumb? 'scroll-thumb 'scroll-track)))))

;; 鼠标 y 坐标 → scroll 值
(define (scrollbar-scroll-from-y my y h total)
  (define-values (thumb-h track-range range) (scrollbar-metrics h total))
  (define rel (- my y))
  (max 0 (min (inexact->exact (round (/ (* rel range) track-range 1.0))) range)))
