#lang racket

;; button — 声明式按钮
;;
;; (button "Submit" #:on-activate 'submit #:style 'button #:key #f)
;;
;; #:on-activate 是一个消息值（view 里有 state，可直接算出消息）。
;; 激活方式：
;;   - Enter / Space（聚焦时）
;;   - 鼠标在按钮内按下→释放（依赖框架的拖拽捕获；拖出按钮释放则不激活）
;;
;; 按下视觉反馈需要 #:key（用 keyed local state 记 pressed?），
;; 不给 #:key 时按钮仍可用，只是没有按下高亮。

(require "../widget.rkt"
         "../surface.rkt"
         "../../base/io/input.rkt")

(provide button)

(define (button label
                #:on-activate  [on-activate #f]
                #:style        [style 'button]
                #:pressed-style [pressed-style 'button-pressed]
                #:key          [key #f])
  (leaf #:key key
        #:local (λ () #f)          ; pressed?（需 #:key 才有跨帧状态）
        #:focusable? #t
        #:render
        (λ (w rect ctx surf)
          (define pressed? (hash-ref ctx 'local #f))
          (render-button label (if pressed? pressed-style style) rect surf))
        #:on-event
        (λ (w type data rect ctx)
          (case type
            [(enter space)
             on-activate]
            [(mouse)
             (cond
               [(mouse-press? data)
                ((hash-ref ctx 'set-local!) #t)
                #f]
               [(mouse-release? data)
                ((hash-ref ctx 'set-local!) #f)
                (and (rect-contains? rect (mouse-x data) (mouse-y data))
                     on-activate)]
               [else #f])]
            [else #f]))))

(define (render-button label style rect surf)
  (match-let ([(list x y w h) rect])
    (define padded (string-append " " label " "))
    (define line (if (> (string-length padded) w) (substring padded 0 w) padded))
    (for ([r (in-range h)])
      (surface-put-string! surf (+ y r) x (make-string w #\space) style))
    (surface-put-string! surf y x line style)))

(define (rect-contains? r x y)
  (and (<= (first r) x (+ (first r) (third r) -1))
       (<= (second r) y (+ (second r) (fourth r) -1))))
