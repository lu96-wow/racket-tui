#lang racket
;; 调度器 — 焦点 / 布局 / 绘制
(require "../base/main.rkt"
         "../base/io/build-input.rkt"
         "component.rkt")

(provide run-app)

;; specs : (list (list component x y w h) ...)
;;         x, y, w, h 可以是 number 或 box? — 组件可通过 box 修改坐标
(define (run-app specs)
  (with-tui
    (cursor-hide)
    (define (unbox* v) (if (box? v) (unbox v) v))

    (define focus (box (for/or ([s specs])
                         (define comp (car s))
                         (and (component-show? comp)
                              (component-focusable? comp)
                              comp))))
    (define quit? (box #f))

    (define global
      (build-input
       #:char (λ (ch) (when (= ch (char->integer #\q))
                         (set-box! quit? #t)))
       #:mouse-press (λ (btn mx my mods)
                       (when (eq? btn 'left)
                         (for/or ([s specs])
                           (match-let ([(list comp xb yb wb hb) s])
                             (define cx (unbox* xb))
                             (define cy (unbox* yb))
                             (define cw (unbox* wb))
                             (define ch (unbox* hb))
                             (and (component-show? comp)
                                  (component-focusable? comp)
                                  (<= cx mx (+ cx cw -1))
                                  (<= cy my (+ cy ch -1))
                                  (begin (set-box! focus comp) #t))))))))

    (let loop ()
      (screen-clear)
      (for ([s specs])
        (match-let ([(list comp xb yb wb hb) s])
          (when (component-show? comp)
            ((component-render comp)
             (eq? comp (unbox focus))
             (unbox* xb) (unbox* yb) (unbox* wb) (unbox* hb)))))
      (flush-output)

      (unless (unbox quit?)
        (let-values ([(type data mods) (read-event)])
          (global type data mods)
          (when (unbox focus)
            ((component-handler (unbox focus)) type data mods))
          (loop))))))
