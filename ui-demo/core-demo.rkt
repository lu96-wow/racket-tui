#lang racket

;; 声明式 UI 核心验证 demo
;; 只用 core（leaf + 容器），不依赖任何组件。

(require "../ui/main.rkt"
         "../base/io/input.rkt")

;; ── 应用状态 ──
(struct model (count last-msg) #:transparent)

(define (update st msg)
  (match msg
    ['inc (struct-copy model st
             [count (add1 (model-count st))]
             [last-msg "↑ inc"])]
    ['dec (struct-copy model st
             [count (sub1 (model-count st))]
             [last-msg "↓ dec"])]
    [(list 'say s) (struct-copy model st [last-msg s])]
    [_ st]))

;; ── 渲染辅助 ──
(define (fill! surf x y w h style)
  (for ([r (in-range y (+ y h))])
    (surface-put-string! surf r x (make-string w #\space) style)))

(define (render-counter wdg rect ctx surf st)
  (match-let ([(list x y w h) rect])
    (define focused? (equal? (hash-ref ctx 'focus-key #f) (widget-key wdg)))
    (define style (if focused? 'selection 'info))
    (fill! surf x y w h style)
    (surface-put-string! surf y x (format "count: ~a" (model-count st)) style)))

(define (render-info wdg rect ctx surf st)
  (match-let ([(list x y w h) rect])
    (fill! surf x y w h 'info)
    (surface-put-string! surf y x (format "last: ~a" (model-last-msg st)) 'info)))

(define (render-local wdg rect ctx surf st)
  (match-let ([(list x y w h) rect])
    (define focused? (equal? (hash-ref ctx 'focus-key #f) (widget-key wdg)))
    (define style (if focused? 'selection 'info))
    (fill! surf x y w h style)
    (surface-put-string! surf y x
      (format "local: ~a (space/click +1)" (hash-ref ctx 'local))
      style)))

(define (render-footer wdg rect ctx surf st)
  (match-let ([(list x y w h) rect])
    (fill! surf x y w h 'dim)
    (surface-put-string! surf y x
      "q=quit  tab/shift-tab=focus  ↑/↓=change  space/click=+local" 'dim)))

;; ── view：纯函数 ──
(define (view st)
  (vstack
   (child
    (panel
     (hstack
      (leaf #:key 'counter #:focusable? #t
            #:render   (λ (w r ctx s) (render-counter w r ctx s st))
            #:on-event (λ (w t d r ctx)
                         (match t
                           ['up    'inc]
                           ['down  'dec]
                           ['mouse (and (mouse-press? d) 'inc)]
                           [else #f])))
      (leaf #:key 'pad
            #:render (λ (w r ctx s) (void))))
     #:title "Counter")
    #:min 3)

   (child
    (panel
     (leaf #:key 'info
           #:render (λ (w r ctx s) (render-info w r ctx s st)))
     #:title "Info")
    #:weight 2 #:min 3)

   (child
    (panel
     (leaf #:key 'local-demo #:focusable? #t
           #:local   (λ () 0)
           #:render  (λ (w r ctx s) (render-local w r ctx s st))
           #:on-event (λ (w t d r ctx)
                        (match t
                          ['space ((hash-ref ctx 'set-local!)
                                   (add1 (hash-ref ctx 'local))) #f]
                          ['mouse (and (mouse-press? d)
                                       ((hash-ref ctx 'set-local!)
                                        (add1 (hash-ref ctx 'local))) #f)]
                          [else #f])))
     #:title "Local state")
    #:min 3)

   (child
    (leaf #:key 'footer
          #:render (λ (w r ctx s) (render-footer w r ctx s st)))
    #:min 1 #:max 1)))

;; ── 启动 ──
(run-app
 #:init   (model 0 "none")
 #:update update
 #:view   view
 #:keymap (list (cons #\q      msg-quit)
                (cons 'tab     msg-focus-next)
                (cons 'backtab msg-focus-prev)))
