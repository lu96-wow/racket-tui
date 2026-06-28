#lang racket
;; 调度器 — 只管三件事: 焦点(鼠标切换) / 布局(用户给定) / 绘制(组件自己画)
(require "../base/main.rkt"
         "../base/io/build-input.rkt"
         "component.rkt")

(provide run-app)

;; specs : (list (list component x y w h) ...)
;;         x, y 是 0-based 终端坐标
(define (run-app specs)
  (with-tui
    (cursor-hide)
    (define focus (box (for/or ([s specs])
                         (define comp (car s))
                         (and (component-show? comp)
                              (component-focusable? comp)
                              comp))))
    (define quit? (box #f))

    ;; 全局事件: q 退出, 鼠标左键切换焦点
    (define global
      (build-input
       #:char (λ (ch) (when (= ch (char->integer #\q))
                         (set-box! quit? #t)))
       #:mouse-press (λ (btn x y mods)
                       (when (eq? btn 'left)
                         (for/or ([s specs])
                           (match-let ([(list comp cx cy w h) s])
                             (and (component-show? comp)
                                  (component-focusable? comp)
                                  (<= cx x (+ cx w -1))
                                  (<= cy y (+ cy h -1))
                                  (begin (set-box! focus comp) #t))))))))

    (let loop ()
      ;; 绘制
      (screen-clear)
      (for ([s specs])
        (match-let ([(list comp x y w h) s])
          (when (component-show? comp)
            ((component-render comp) (eq? comp (unbox focus)) x y w h))))
      (flush-output)

      ;; 事件
      (unless (unbox quit?)
        (let-values ([(type data mods) (read-event)])
          (global type data mods)
          (when (unbox focus)
            ((component-handler (unbox focus)) type data mods))
          (loop))))))
