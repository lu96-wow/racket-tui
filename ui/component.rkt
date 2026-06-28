#lang racket

(provide component component?
         component-render component-handler
         component-focusable? component-show?
         component-w component-h)

;; render    : (λ (focused? x y w h) → void)   x,y,w,h 0-based, 调度器传入
;; handler   : (λ (type data mods) → void)     build-input 构造
;; focusable?: bool
;; show?     : bool
;; w, h      : natural / box?  组件期望宽高
(struct component (render handler focusable? show? w h) #:transparent)
