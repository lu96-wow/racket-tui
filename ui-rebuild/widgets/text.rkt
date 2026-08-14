#lang racket

;; text — 声明式文本标签
;;
;; (text "hello" #:style 'info #:h-align 'left #:key #f)
;;
;; 因为 view 是纯函数、每帧从 state 重建，文本内容直接取当前值即可：
;; 不再需要旧的 static/lambda/box 三路分派。可见性由 view 条件渲染决定，
;; 也不再有 show?/hide!。

(require "../widget.rkt"
         "../surface.rkt")

(provide text)

(define (text str
              #:style   [style 'info]
              #:h-align [h-align 'left]
              #:key     [key #f])
  (leaf #:key key
        #:render (λ (w rect ctx surf)
                   (render-text str style h-align rect surf))))

(define (render-text str style h-align rect surf)
  (match-let ([(list x y w h) rect])
    ;; 先铺背景（样式可能带背景色），再画文本
    (for ([r (in-range h)])
      (surface-put-string! surf (+ y r) x (make-string w #\space) style))
    (define clipped (if (> (string-length str) w) (substring str 0 w) str))
    (define x-off
      (case h-align
        [(center) (quotient (max 0 (- w (string-length clipped))) 2)]
        [(right)  (max 0 (- w (string-length clipped)))]
        [else 0]))
    (surface-put-string! surf y (+ x x-off) clipped style)))
