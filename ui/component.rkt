#lang racket

(require "../base/io/build-input.rkt"
         "../base/io/output-styles.rkt"
         "../base/io/output-color.rkt"
         "../base/io/output.rkt")

(provide component component?
         component-render component-handler
         component-focusable? component-show?
         component-w component-h
         make-button)

;; ─── component struct ───
;; render    : (λ (focused? x y w h) → void)   x,y,w,h 0-based, 调度器传入
;; handler   : (λ (type data mods) → void)     build-input 构造
;; focusable?: bool
;; show?     : bool
;; w, h      : natural  组件期望宽高
(struct component (render handler focusable? show? w h) #:transparent)

;; ─── make-button ───
(define (make-button #:text text #:on-activate on-activate)
  (define label (string-append " " text " "))
  (component
   (λ (focused? x y w h)
     (put-styled-at! (+ y 1) (+ x 1)
                     (if focused? 'button-hover 'button)
                     label))
   (build-input #:enter on-activate #:space on-activate)
   #t #t
   (string-length label)
   1))
