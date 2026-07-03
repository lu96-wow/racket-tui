#lang racket

(provide component component?
         component-render component-handler
         component-focusable? component-show?
         component-w component-h component-dirty
         component-render?
         component-visible?
         component-show! component-hide! component-toggle!)

;; render    : (λ (focused? x y w h) → void)   x,y,w,h 0-based, 调度器传入
;; handler   : (λ (type data mods) → void)     build-input 构造
;; focusable?: bool
;; show?     : box<bool> | (-> bool)            可见性 (box 可写, thunk 只读)
;; w, h      : natural / box?  组件期望宽高
;; dirty     : box?  组件标记需要重绘（调度器每帧检查，绘后置 #f）
;; render?   : (or/c #f (λ (x y w h focused?) → void))
;;             每帧 needs-redraw? 之前调用；组件自行比对内容、置 dirty
(struct component
  (render handler focusable? show? w h dirty render?) #:transparent)

;; 统一的可见性检查
(define (component-visible? comp)
  (define s (component-show? comp))
  (cond [(boolean? s) s]
        [(box? s) (unbox s)]
        [(procedure? s) (s)]
        [else s]))

;; 可见性操作 (仅 box 可写, thunk 只读→静默无效)
(define (component-show! comp)
  (define s (component-show? comp))
  (when (box? s)
    (unless (unbox s)
      (set-box! s #t)
      (set-box! (component-dirty comp) #t))))

(define (component-hide! comp)
  (define s (component-show? comp))
  (when (box? s)
    (when (unbox s)
      (set-box! s #f)
      (set-box! (component-dirty comp) #t))))

(define (component-toggle! comp)
  (define s (component-show? comp))
  (when (box? s)
    (set-box! s (not (unbox s)))
    (set-box! (component-dirty comp) #t)))
