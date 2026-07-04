#lang racket
;; 调度器入口 — 组装所有模块, 启动事件循环
;;
;; 架构:
;;   run/render.rkt   — 渲染引擎 (render-all)
;;   run/focus.rkt    — 键盘焦点 (global handler)
;;   run/mouse.rkt    — 鼠标路由 (mouse-router)
;;   run/dispatch.rkt — 事件分发 (dispatch-and-render)
;;
;; 事件流:
;;   read-event → global → mouse-router → dispatch-and-render → render-all

(require "../base/main.rkt"
         "../base/io/build-input.rkt"
         "component.rkt"
         "run/render.rkt"
         "run/focus.rkt"
         "run/mouse.rkt"
         "run/dispatch.rkt"
         (for-syntax racket/base))

(provide run-app run-app-noblock
         run-app-nobuffer run-app-nobuffer-noblock)

;; ═══════════════════════════════════════════════════
;; 入口宏: 自动在 (comp x y w h) 前补 list
;;   用户写:  (run-app (out1 0 0 40 12) (inp 0 13 30 2))
;;   展开为:  (run-app* (list (list out1 0 0 40 12) (list inp 0 13 30 2)) #:noblock? #f)
;;   向后兼容: 单标识符或显式 (list ...) 原样透传

(define-for-syntax (wrap-spec arg)
  (cond
    [(identifier? arg) arg]
    [(not (pair? (syntax-e arg))) arg]
    [(and (identifier? (car (syntax-e arg)))
          (eq? 'list (syntax-e (car (syntax-e arg)))))
     arg]
    [else
     (with-syntax ([(e ...) (syntax->list arg)])
       #'(list e ...))]))

(define-for-syntax (collect-specs specs-stx)
  (define origs (syntax->list specs-stx))
  (if (and (= (length origs) 1)
           (let ([o (car origs)])
             (or (identifier? o)
                 (and (pair? (syntax-e o))
                      (identifier? (car (syntax-e o)))
                      (eq? 'list (syntax-e (car (syntax-e o))))))))
      (car origs)
      (let ([wrapped (map wrap-spec origs)])
        #`(list #,@wrapped))))

(define-syntax (run-app stx)
  (syntax-case stx ()
    [(_ spec ...)
     (with-syntax ([specs (collect-specs #'(spec ...))])
       #'(run-app* specs #:noblock? #f))]))

(define-syntax (run-app-noblock stx)
  (syntax-case stx ()
    [(_ spec ...)
     (with-syntax ([specs (collect-specs #'(spec ...))])
       #'(run-app* specs #:noblock? #t))]))

(define-syntax (run-app-nobuffer stx)
  (syntax-case stx ()
    [(_ spec ...)
     (with-syntax ([specs (collect-specs #'(spec ...))])
       #'(run-app-nobuffer* specs #:noblock? #f))]))

(define-syntax (run-app-nobuffer-noblock stx)
  (syntax-case stx ()
    [(_ spec ...)
     (with-syntax ([specs (collect-specs #'(spec ...))])
       #'(run-app-nobuffer* specs #:noblock? #t))]))

;; ═══════════════════════════════════════════════════
;; 内部 — 以下逻辑完全不动

(define (run-app* specs #:noblock? [noblock? #f])
  (with-tui (run-loop specs noblock?)))

(define (run-app-nobuffer* specs #:noblock? [noblock? #f])
  (with-tui-nobuffer (run-loop specs noblock?)))

(define (run-loop specs noblock?)
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
          global mouse-router dispatch-and-render)))
