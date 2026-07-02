#lang racket

(provide component component?
         component-render component-handler
         component-focusable? component-show?
         component-w component-h component-dirty
         component-render?)

;; render    : (λ (focused? x y w h) → void)   x,y,w,h 0-based, 调度器传入
;; handler   : (λ (type data mods) → void)     build-input 构造
;; focusable?: bool
;; show?     : bool
;; w, h      : natural / box?  组件期望宽高
;; dirty     : box?  组件标记需要重绘（调度器每帧检查，绘后置 #f）
;; render?   : (or/c #f (λ (x y w h focused?) → void))
;;             每帧 needs-redraw? 之前调用；组件自行比对内容、置 dirty
(struct component
  (render handler focusable? show? w h dirty render?) #:transparent)
