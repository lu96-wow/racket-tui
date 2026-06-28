#lang racket
;; 调度器 — 只管三件事: 焦点(鼠标切换) / 布局(用户给定) / 绘制(组件自己画)
(require "../base/main.rkt"
         "../base/io/input.rkt"
         "../base/ansi/input-var.rkt"
         "component.rkt")

(provide run-app)

;; specs : (list (list component x y w h) ...)
;;         x, y 是 0-based 终端坐标
;;         调度器不干预布局, 照给定的位置绘制
(define (run-app specs)
  (with-tui
    (cursor-hide)

    ;; 初始焦点: 第一个 focusable + show? 的组件
    (define (first-focusable)
      (for/or ([s specs])
        (define comp (car s))
        (and (component-show? comp)
             (component-focusable? comp)
             comp)))

    (let loop ([focus (first-focusable)])
      ;; ─── 绘制 ───
      (screen-clear)
      (for ([s specs])
        (match-let ([(list comp x y w h) s])
          (when (component-show? comp)
            ((component-render comp) (eq? comp focus) x y w h))))
      (flush-output)

      ;; ─── 事件 ───
      (let-values ([(type data mods) (read-event)])
        ;; q 退出循环
        (define quit?
          (and (eq? type EVENT-KEY)
               (bytes? data)
               (= (bytes-length data) 1)
               (= (bytes-ref data 0) (char->integer #\q))))

        (if quit?
            (void)
            (let* ([next-focus
                    ;; 鼠标左键点击 → 切换焦点 (命中测试)
                    (if (and (eq? type EVENT-MOUSE)
                             (mouse-press? data)
                             (mouse-left? data))
                        (let ([mx (mouse-x data)]
                              [my (mouse-y data)])
                          (for/or ([s specs])
                            (match-let ([(list comp x y w h) s])
                              (and (component-show? comp)
                                   (component-focusable? comp)
                                   (<= x mx (+ x w -1))
                                   (<= y my (+ y h -1))
                                   comp))))
                        focus)])
              ;; 路由给焦点组件
              (when next-focus
                ((component-handler next-focus) type data mods))
              (loop next-focus)))))))
