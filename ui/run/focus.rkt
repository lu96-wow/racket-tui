#lang racket
;; 全局事件处理 — quit 键 + 鼠标点击切换键盘焦点
;;
;; 职责:
;;   - q 键退出
;;   - 鼠标左键点击 → hit-test → 切换到对应 focusable 组件

(require "../../base/main.rkt"
         "../../base/io/build-input.rkt"
         "../component.rkt")

(provide make-global)

(define (make-global specs unbox* focus quit?)
  (build-input
   #:char (λ (ch) (when (= ch (char->integer #\q))
                     (set-box! quit? #t)))
   #:mouse-press (λ (btn mx my mods)
                   (when (eq? btn 'left)
                     (for/or ([s specs])
                       (match-let ([(list comp xb yb wb hb) s])
                         (define cx (unbox* xb))
                         (define cy (unbox* yb))
                         (define cw (let ([v (unbox* wb)]) (if (zero? v) (component-w comp) v)))
                         (define ch (let ([v (unbox* hb)]) (if (zero? v) (component-h comp) v)))
                         (and (component-show? comp)
                              (component-focusable? comp)
                              (<= cx mx (+ cx cw -1))
                              (<= cy my (+ cy ch -1))
                              (begin (set-box! focus comp) #t))))))))
