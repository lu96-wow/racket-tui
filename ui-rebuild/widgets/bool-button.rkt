#lang racket

;; bool-button — 声明式布尔开关
;;
;; (bool-button "Option" #:value #f #:on-toggle 'toggle
;;              #:on-style 'success #:off-style 'info #:key #f)
;;
;; 状态提升到 app state：view 传入 #:value，激活时返回 #:on-toggle 消息，
;; 由 update 负责翻转。组件自身无隐藏状态。

(require "../widget.rkt"
         "../surface.rkt"
         "../../base/io/input.rkt")

(provide bool-button)

(define (bool-button label
                     #:value     [value #f]
                     #:on-toggle [on-toggle #f]
                     #:on-style  [on-style 'success]
                     #:off-style [off-style 'info]
                     #:key       [key #f])
  (leaf #:key key
        #:focusable? #t
        #:render
        (λ (w rect ctx surf)
          (render-bool label value on-style off-style rect surf))
        #:on-event
        (λ (w type data rect ctx)
          (cond
            [(memq type '(enter space)) on-toggle]
            [(eq? type 'mouse) (and (mouse-press? data) on-toggle)]
            [else #f]))))

(define (render-bool label v on-style off-style rect surf)
  (match-let ([(list x y w h) rect])
    (define style (if v on-style off-style))
    (define mark (if v "[x]" "[ ]"))
    (define text (string-append mark " " label))
    (for ([r (in-range h)])
      (surface-put-string! surf (+ y r) x (make-string w #\space) style))
    (define line (if (> (string-length text) w) (substring text 0 w) text))
    (surface-put-string! surf y x line style)))
