#lang racket

;; ═══════════════════════════════════════════════════════════════════════════
;; widget.rkt — 声明式 widget（不可变值）
;;
;;   widget = (widget key kind props children)
;;
;;   - key      : (or/c #f any) — 身份标识（焦点、keyed local state 用）
;;   - kind     : symbol        — 'leaf / 'vstack / 'hstack / 'panel / 'rect
;;   - props    : hash          — 纯配置（不可变）
;;   - children : (listof (cons widget (or/c #f real?)))
;;               weight 为 #f 表示填充父容器（panel/rect 的单子节点）
;;
;; widget 只是数据，不持有 box、不产生副作用。view 每次从 state 重建。
;; ═══════════════════════════════════════════════════════════════════════════

(provide widget widget? widget-key widget-kind widget-props widget-children
         child-spec child-spec? child-spec-weight child-spec-min child-spec-max
         spec child
         leaf vstack hstack panel rect
         normalize-children)

(struct widget (key kind props children) #:transparent)

;; ── child-spec — 容器子节点的布局约束（主轴上）──
;;   weight : 权重（>0 参与分配；0 = 不占空间）
;;   min    : 最小尺寸（默认 0）
;;   max    : 最大尺寸（默认 +inf.0，无上限）
(struct child-spec (weight min max) #:transparent)

(define (spec weight #:min [mn 0] #:max [mx +inf.0])
  (child-spec weight mn mx))

;; child — 在容器里给子节点附加布局约束的便捷构造器
;;   (child w)                          → 权重 1
;;   (child w #:weight 2 #:min 3 #:max n)
(define (child w #:weight [weight 1] #:min [mn 0] #:max [mx +inf.0])
  (cons w (child-spec weight mn mx)))

;; 子节点规范化。可接受的 item 形式：
;;   widget                    → 权重 1
;;   (child w ...)             → (cons w child-spec)
;;   (cons widget number)      → 权重 number（手写）
;;   (cons widget child-spec)  → 完整约束（手写）
(define (normalize-children items)
  (map normalize-child-item items))

(define (normalize-child-item it)
  (cond
    [(widget? it)
     (cons it (child-spec 1 0 +inf.0))]
    [(and (pair? it) (widget? (car it)))
     (cond
       [(child-spec? (cdr it)) it]
       [(number? (cdr it)) (cons (car it) (child-spec (cdr it) 0 +inf.0))]
       [else (error 'vstack/hstack "bad child item: ~a" it)])]
    [else (error 'vstack/hstack "bad child item: ~a" it)]))

;; ── leaf — 自定义叶节点的逃生舱（组件层会基于它封装 text/button/...）──
;;
;;   #:size      '(w . h) 期望尺寸，0 = 填满父分配区域（默认 '(0 . 0)）
;;   #:render    (λ (w rect ctx surf) → void)
;;   #:on-event  (λ (w type data rect ctx) → (or/c #f message))
;;   #:focusable? bool
;;   #:local     (λ () → 初始值) — keyed local state 的初始化（需 #:key）
;;   ctx: (hash 'focus-key key-or-#f
;;              'local 本组件局部状态值
;;              'set-local! (λ (v) → void) 更新局部状态)
(define (leaf #:key         [key #f]
              #:size        [size '(0 . 0)]
              #:render      [render (λ (w rect ctx surf) (void))]
              #:on-event    [on-event (λ (w type data rect ctx) #f)]
              #:focusable?  [focusable? #f]
              #:local       [local-init (λ () #f)]
              #:props       [props (hasheq)])
  (widget key 'leaf
          (hash-set* props 'size size 'render render
                     'on-event on-event 'focusable? focusable?
                     'local-init local-init)
          '()))

;; ── 容器 ──

;; 垂直堆叠：子节点按权重分配高度
(define (vstack #:key [key #f] . items)
  (widget key 'vstack (hasheq) (normalize-children items)))

;; 水平堆叠：子节点按权重分配宽度
(define (hstack #:key [key #f] . items)
  (widget key 'hstack (hasheq) (normalize-children items)))

;; 面板（带边框的容器）：子节点内缩 (1,1,-2,-2)，边框由框架绘制
(define (panel child
               #:key   [key #f]
               #:title [title #f]
               #:style [style 'border])
  (widget key 'panel
          (hasheq 'title title 'style style)
          (list (cons child #f))))

;; 绝对定位容器：子节点相对本容器左上角偏移 (x y)，尺寸 (w h)
(define (rect child
              #:key [key #f]
              #:x   [x 0] #:y [y 0]
              #:w   [w #f] #:h [h #f])
  (widget key 'rect
          (hasheq 'x x 'y y 'w w 'h h)
          (list (cons child #f))))
