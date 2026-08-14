#lang racket

;; ═══════════════════════════════════════════════════════════════════════════
;; layout.rkt — 布局：把 widget 树解析成 element 树（带 rect）
;;
;;   element = (element widget rect children)
;;   rect    = (list x y w h)，0-based
;;
;; 布局是纯函数，返回真正的树。命中测试、焦点顺序都沿树走，
;; 因此 panel 的边框不会吞掉内部子节点的鼠标事件（修复旧 ui/ 的 bug）。
;; ═══════════════════════════════════════════════════════════════════════════

(require "widget.rkt")

(provide element element-widget element-rect element-children element?
         resolve element-hit element-focusables widget-focusable?)

(struct element (widget rect children) #:transparent)

;; resolve : widget x y w h → element
(define (resolve w x y tw th)
  (define rect (list x y tw th))
  (define children
    (case (widget-kind w)
      [(vstack) (resolve-stack w x y tw th 'v)]
      [(hstack) (resolve-stack w x y tw th 'h)]
      [(panel)  (resolve-panel w x y tw th)]
      [(rect)   (resolve-rect w x y tw th)]
      [else '()]))
  (element w rect children))

;; 权重分配（垂直/水平），支持 min/max 约束
(define (resolve-stack w x y tw th dir)
  (define vertical? (eq? dir 'v))
  (define span (if vertical? th tw))
  (define items (widget-children w))
  (if (null? items)
      '()
      (let* ([specs (map cdr items)]
             [sizes (distribute-axis span specs)])
        (let loop ([items items]
                   [sizes sizes]
                   [offset (if vertical? y x)]
                   [acc '()])
          (cond
            [(null? items) (reverse acc)]
            [else
             (define child (caar items))
             (define size (car sizes))
             (define cx (if vertical? x offset))
             (define cy (if vertical? offset y))
             (define cw (if vertical? tw size))
             (define ch (if vertical? size th))
             (loop (cdr items) (cdr sizes) (+ offset size)
                   (cons (resolve child cx cy cw ch) acc))])))))

;; ── distribute-axis：按权重分配，并满足 min/max ──
;; 算法：先按权重给比例尺寸，再迭代 clamp 到 [min,max] 并把
;; 剩余空间在未锁定的子项间重分配，直到稳定。
;; 约束语义：
;;   - max 是硬上限（绝不超出）
;;   - min 是硬下限；若所有 min 之和 > span（无法满足），允许溢出，
;;     由 surface 裁剪（与 CSS flexbox 的 overflow 行为一致）
(define (distribute-axis span specs)
  (define n (length specs))
  (define sizes (make-vector n 0))
  (define locked (make-vector n #f))
  (define total-w (for/sum ([sp (in-list specs)]) (child-spec-weight sp)))

  ;; 初始：weight 0 → 0 并锁定；否则按权重比例
  (for ([i (in-range n)])
    (define sp (list-ref specs i))
    (if (zero? (child-spec-weight sp))
        (vector-set! locked i #t)
        (vector-set! sizes i
          (if (zero? total-w) 0
              (quotient (* span (child-spec-weight sp)) total-w)))))

  (let loop ()
    ;; clamp 违反约束的子项
    (define changed? #f)
    (for ([i (in-range n)] #:unless (vector-ref locked i))
      (define sp (list-ref specs i))
      (define s (vector-ref sizes i))
      (cond
        [(< s (child-spec-min sp))
         (vector-set! sizes i (child-spec-min sp))
         (vector-set! locked i #t)
         (set! changed? #t)]
        [(> s (child-spec-max sp))
         (vector-set! sizes i (child-spec-max sp))
         (vector-set! locked i #t)
         (set! changed? #t)]))

    (define free (for/list ([i (in-range n)] #:unless (vector-ref locked i)) i))
    (cond
      [(and changed? (pair? free))
       (define used (for/sum ([i (in-range n)] #:when (vector-ref locked i))
                      (vector-ref sizes i)))
       (define rem (- span used))
       (define free-w (for/sum ([i (in-list free)])
                        (child-spec-weight (list-ref specs i))))
       (for ([i (in-list free)])
         (vector-set! sizes i
           (if (zero? free-w) 0
               (quotient (* rem (child-spec-weight (list-ref specs i))) free-w))))
       (loop)]
      [else
       (vector->list sizes)])))

;; panel：子节点内缩 (1,1,-2,-2)
(define (resolve-panel w x y tw th)
  (define child (first-child w))
  (if child
      (list (resolve child (add1 x) (add1 y)
                     (max 0 (- tw 2)) (max 0 (- th 2))))
      '()))

;; rect：子节点绝对定位（相对父容器）
(define (resolve-rect w x y tw th)
  (define child (first-child w))
  (if child
      (let* ([p  (widget-props w)]
             [rx (hash-ref p 'x 0)] [ry (hash-ref p 'y 0)]
             [rw (hash-ref p 'w #f)] [rh (hash-ref p 'h #f)])
        (list (resolve child (+ x rx) (+ y ry) (or rw tw) (or rh th))))
      '()))

(define (first-child w)
  (and (pair? (widget-children w))
       (car (car (widget-children w)))))

;; ── 焦点顺序：深度优先，收集 focusable 叶节点 ──
(define (element-focusables elem)
  (let walk ([e elem])
    (if (widget-focusable? (element-widget e))
        (list e)
        (apply append (map walk (element-children e))))))

(define (widget-focusable? w)
  (eq? (hash-ref (widget-props w) 'focusable? #f) #t))

;; ── 命中测试：返回最上层命中的叶 element（或 #f）──
(define (element-hit e x y)
  (case (widget-kind (element-widget e))
    [(leaf)
     (and (rect-contains? (element-rect e) x y) e)]
    [(panel)
     ;; 边框不参与交互：只有内缩的内容区才向下递归
     (define r (element-rect e))
     (define ix (add1 (first r)))
     (define iy (add1 (second r)))
     (define iw (- (third r) 2))
     (define ih (- (fourth r) 2))
     (if (and (> iw 0) (> ih 0)
              (<= ix x (+ ix iw -1))
              (<= iy y (+ iy ih -1)))
         (hit-children (element-children e) x y)
         #f)]
    [else
     (hit-children (element-children e) x y)]))

(define (hit-children children x y)
  (for/or ([c (in-list (reverse children))])
    (element-hit c x y)))

(define (rect-contains? r x y)
  (and (<= (first r) x (+ (first r) (third r) -1))
       (<= (second r) y (+ (second r) (fourth r) -1))))
