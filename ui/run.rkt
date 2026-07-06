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
         "layout.rkt"
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
  (if (= (length origs) 1)
      (car origs)   ;; 单参数原样透传：变量、list、或 screen 等宏调用
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
;; 内部

(define (run-app* arg #:noblock? [noblock? #f])
  (with-tui (run-loop arg noblock?)))

(define (run-app-nobuffer* arg #:noblock? [noblock? #f])
  (with-tui-nobuffer (run-loop arg noblock?)))

(define (run-loop arg noblock?)
    (cursor-hide)
    
    ;; ── 辅助 ──
    (define (maybe-unbox v) (if (box? v) (unbox v) v))

    ;; 从 spec 的 boxed 宽/高解析: 0 → 取组件期望尺寸
    (define (resolve-size spec-boxed comp-accessor comp)
      (define v (maybe-unbox spec-boxed))
      (if (zero? v) (comp-accessor comp) v))

    ;; ── 解析输入: layout 或 spec-list ──
    (define layout (and (layout? arg) arg))
    (define (compute-specs)
      (if layout
          (let-values ([(h w) (get-window-size)])
            ((layout-resolve layout) 1 1 w h))
          arg))
    (define specs-box (box (compute-specs)))

    ;; ── 状态 ──
    (define focus (box (for/or ([spec (unbox specs-box)])
                         (define comp (car spec))
                         (and (component-visible? comp)
                              (component-focusable? comp)
                              comp))))
    (define quit?        (box #f))
    (define mouse-focus  (box #f))
    (define last-bounds  (make-hasheq))
    (define render-cache (make-hasheq))
    (define last-focused (make-hasheq))

    ;; resize 回调: 重算 + 清缓存 + 标记全部 dirty
    (define (recalc!)
      (when layout
        (set-box! specs-box (compute-specs))
        (hash-clear! last-bounds)
        (hash-clear! render-cache)
        (hash-clear! last-focused)
        (for ([spec (unbox specs-box)])
          (set-box! (component-dirty (car spec)) #t))))

    ;; ── 模块组装 ──
    (define render-all
      (make-renderer specs-box maybe-unbox resolve-size focus last-bounds render-cache last-focused))

    (define global
      (make-global specs-box maybe-unbox resolve-size focus quit?))

    (define mouse-router
      (make-mouse-router specs-box maybe-unbox resolve-size mouse-focus))

    (define dispatch-and-render
      (make-dispatcher specs-box recalc! focus render-all))

    ;; ── 启动 ──
    (render-all)
    (if noblock?
        (loop-input-noblock/stop (unbox quit?)
          global mouse-router dispatch-and-render)
        (loop-input/stop (unbox quit?)
          global mouse-router dispatch-and-render)))
