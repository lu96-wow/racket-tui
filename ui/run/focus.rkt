#lang racket
;; 全局事件处理 — quit 键 + 鼠标点击切换键盘焦点

(require "../../base/main.rkt"
         "../../base/io/build-input.rkt"
         "../component.rkt")

(provide make-global)

(define (make-global specs-box maybe-unbox resolve-size focus quit?)
  (build-input
   #:char (λ (ch) (when (= ch (char->integer #\q))
                     (set-box! quit? #t)))
   #:mouse-press (λ (button mx my mods)
                   (when (eq? button 'left)
                     (for/or ([spec (unbox specs-box)])
                       (match-let ([(list comp xb yb wb hb) spec])
                         (define cx (maybe-unbox xb))
                         (define cy (maybe-unbox yb))
                         (define cw (resolve-size wb component-w comp))
                         (define ch (resolve-size hb component-h comp))
                         (and (component-visible? comp)
                              (component-focusable? comp)
                              (<= cx mx (+ cx cw -1))
                              (<= cy my (+ cy ch -1))
                              (begin (set-box! focus comp) #t))))))))
