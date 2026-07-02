#lang racket
;; 调度器入口 — 组装所有模块, 启动事件循环
;;
;; 架构:
;;   run-render.rkt   — 渲染引擎 (render-all)
;;   run-focus.rkt    — 键盘焦点 (global handler)
;;   run-mouse.rkt    — 鼠标路由 (mouse-router)
;;   run-dispatch.rkt — 事件分发 (dispatch-and-render)
;;
;; 事件流:
;;   read-event → global → mouse-router → dispatch-and-render → render-all

(require "../base/main.rkt"
         "../base/io/build-input.rkt"
         "component.rkt"
         "run-render.rkt"
         "run-focus.rkt"
         "run-mouse.rkt"
         "run-dispatch.rkt")

(provide run-app)

(define (run-app specs #:noblock? [noblock? #f])
  (with-tui
    (cursor-hide)
    (define (unbox* v) (if (box? v) (unbox v) v))

    ;; ── 状态 ──
    (define focus (box (for/or ([s specs])
                         (define comp (car s))
                         (and (component-show? comp)
                              (component-focusable? comp)
                              comp))))
    (define quit?        (box #f))
    (define mouse-focus  (box #f))
    (define last-bounds  (make-hasheq))
    (define render-cache (make-hasheq))
    (define last-focused (make-hasheq))

    ;; ── 模块组装 ──
    (define render-all
      (make-renderer specs unbox* focus last-bounds render-cache last-focused))

    (define global
      (make-global specs unbox* focus quit?))

    (define mouse-router
      (make-mouse-router specs unbox* mouse-focus))

    (define dispatch-and-render
      (make-dispatcher specs focus render-all))

    ;; ── 启动 ──
    (render-all)
    (if noblock?
        (loop-input-noblock/stop (unbox quit?)
          global mouse-router dispatch-and-render)
        (loop-input/stop (unbox quit?)
          global mouse-router dispatch-and-render))))
