#lang racket

;; ═══════════════════════════════════════════════════════════════════════════
;; render.rkt — 把 element 树渲染到 surface（纯函数，只写格点）
;;
;; 顺序：先画子节点，再画父节点（父节点的边框可覆盖子节点边缘）。
;; 所有绘制都落到 surface，最后统一由 surface-diff-bytes 输出。
;; ═══════════════════════════════════════════════════════════════════════════

(require "surface.rkt"
         "layout.rkt"
         "widget.rkt")

(provide render-element!
         make-render-ctx
         widget-ctx)

;; rctx：渲染上下文（含焦点 key 与 keyed local state 表）
(define (make-render-ctx #:focus-key  [focus-key #f]
                         #:local-table [local-table (make-hasheq)]
                         #:mark-dirty! [mark-dirty! void])
  (hasheq 'focus-key focus-key 'local-table local-table 'mark-dirty! mark-dirty!))

;; 为某个 widget 构造其可见的 ctx（含局部状态访问器）
;; 局部状态按 widget-key 跨帧持久化；首次出现时用 #:local 初始化
(define (widget-ctx w rctx)
  (define key (widget-key w))
  (define table (hash-ref rctx 'local-table))
  (define init (hash-ref (widget-props w) 'local-init (λ () #f)))
  (define mark (hash-ref rctx 'mark-dirty! void))
  (when (and key (not (hash-has-key? table key)))
    (hash-set! table key (init)))
  (hasheq
   'focus-key (hash-ref rctx 'focus-key #f)
   'local (and key (hash-ref table key #f))
   'set-local! (λ (v) (when key (hash-set! table key v) (mark)))))

(define (render-element! e surf rctx)
  (for ([c (in-list (element-children e))])
    (render-element! c surf rctx))
  (define w (element-widget e))
  (define ctx (if (eq? (widget-kind w) 'leaf)
                  (widget-ctx w rctx)
                  (hasheq 'focus-key (hash-ref rctx 'focus-key #f))))
  ((render-fn w) w (element-rect e) ctx surf))

(define (render-fn w)
  (case (widget-kind w)
    [(leaf)  (hash-ref (widget-props w) 'render)]
    [(panel) render-panel]
    [else    (λ (w rect ctx surf) (void))]))

;; ── panel 边框 ──
(define (render-panel wdg rect ctx surf)
  (match-let ([(list x y w h) rect])
    (when (and (> w 0) (> h 0))
      (define style (hash-ref (widget-props wdg) 'style 'border))
      (define title (hash-ref (widget-props wdg) 'title #f))
      (define L x) (define R (+ x w -1))
      (define T y) (define B (+ y h -1))

      ;; 角
      (surface-put! surf T L #\┌ style)
      (surface-put! surf T R #\┐ style)
      (surface-put! surf B L #\└ style)
      (surface-put! surf B R #\┘ style)

      ;; 横边（w > 2 时）
      (when (> w 2)
        (for ([c (in-range (add1 L) R)])
          (surface-put! surf T c #\─ style)
          (surface-put! surf B c #\─ style)))

      ;; 竖边（h > 2 时）
      (when (> h 2)
        (for ([r (in-range (add1 T) B)])
          (surface-put! surf r L #\│ style)
          (surface-put! surf r R #\│ style)))

      ;; 标题（放在上边内侧）
      (when (and title (> w 2))
        (define ts (if (string? title) title (format "~a" title)))
        (define label (string-append " " ts " "))
        (define clip (min (string-length label) (max 0 (- w 2))))
        (when (positive? clip)
          (surface-put-string! surf T (add1 L) (substring label 0 clip) style))))))
