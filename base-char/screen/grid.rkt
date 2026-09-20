#lang racket

;; 字符网格模型 —— 一个最小屏幕缓冲。
;; ANSI 解析器（ansi-parse.rkt）把字节流解释成这里的原语调用，
;; render.rkt 再把网格渲染成纯字符图。
;;
;; 坐标约定：内部一律 0-based（ANSI 是 1-based，在解析器里换算）。
;; 单元格 text 用 string 以兼容宽字符 / 组合记号；
;;   - " "  = 空白格
;;   - #f   = 宽字符的右半格（被左邻覆盖）
;;   - 其他 = 实际内容（组合记号会追加到前一格）

(require "width.rkt")

(provide (struct-out cell) (struct-out grid)
         make-grid blank-cell cell-default?
         grid-ref grid-set-cell!
         grid-clear! grid-resize!
         grid-cursor grid-move! grid-move-rel!
         grid-put-char!
         grid-index! grid-reverse-index! grid-wrap!
         grid-carriage-return! grid-backspace! grid-tab!
         grid-erase-display! grid-erase-line!
         grid-scroll-up! grid-scroll-down! grid-set-scroll-region!
         grid-save! grid-restore! grid-saved?
         set-grid-fg! set-grid-bg! set-grid-attrs!
         grid-add-attr! grid-remove-attr!)

;; fg/bg 表示：
;;   #f                = 默认色
;;   (list 'idx n)     = 索引色（0-15 走 ANSI，0-255 走 256 色）
;;   (list 'rgb r g b) = 真彩
;; attrs：symbol 列表（'bold 'dim 'italic 'underline 'blink 'reverse）

(struct cell (text fg bg attrs) #:transparent)

(define blank-cell (cell " " #f #f '()))

(define (cell-default? c)
  (and (equal? (cell-text c) " ")
       (not (cell-fg c))
       (not (cell-bg c))
       (null? (cell-attrs c))))

(struct grid
  (cells                                   ; (vectorof (vectorof cell))
   rows cols
   cursor-row cursor-col
   fg bg attrs
   wrap-pending?                           ; 光标停在右边界，下一字符需换行
   saved                                   ; #f | (list row col fg bg attrs)
   cursor-visible? alt-active?
   scroll-top scroll-bottom)               ; 0-based inclusive
  #:mutable #:transparent)

(define (make-grid rows cols)
  (grid (for/vector ([_ rows]) (make-vector cols blank-cell))
        rows cols
        0 0
        #f #f '()
        #f #f #t #f
        0 (max 0 (- rows 1))))

(define (grid-ref g row col)
  (vector-ref (vector-ref (grid-cells g) row) col))

(define (grid-set-cell! g row col c)
  (vector-set! (vector-ref (grid-cells g) row) col c))

(define (grid-fill-row! g row c0 c1)
  (for ([c (in-range c0 (add1 c1))])
    (grid-set-cell! g row c blank-cell)))

(define (grid-clear! g)
  (for ([r (in-range (grid-rows g))])
    (grid-fill-row! g r 0 (sub1 (grid-cols g))))
  (set-grid-cursor-row! g 0)
  (set-grid-cursor-col! g 0)
  (set-grid-wrap-pending?! g #f)
  (set-grid-fg! g #f)
  (set-grid-bg! g #f)
  (set-grid-attrs! g '()))

;; ── 光标 ─────────────────────────────────────────────────

(define (grid-move! g row col)
  (set-grid-wrap-pending?! g #f)
  (set-grid-cursor-row! g (max 0 (min (sub1 (grid-rows g)) row)))
  (set-grid-cursor-col! g (max 0 (min (sub1 (grid-cols g)) col))))

(define (grid-move-rel! g drow dcol)
  (grid-move! g (+ (grid-cursor-row g) drow)
              (+ (grid-cursor-col g) dcol)))

(define (grid-cursor g)
  (values (grid-cursor-row g) (grid-cursor-col g)))

;; ── 滚动 ─────────────────────────────────────────────────

(define (grid-scroll-up! g n)
  (define top (grid-scroll-top g))
  (define bot (grid-scroll-bottom g))
  (define cells (grid-cells g))
  (for ([i (in-range top (add1 (- bot n)))])
    (vector-set! cells i (vector-copy (vector-ref cells (+ i n)))))
  (for ([i (in-range (add1 (- bot n)) (add1 bot))])
    (vector-set! cells i (make-vector (grid-cols g) blank-cell))))

(define (grid-scroll-down! g n)
  (define top (grid-scroll-top g))
  (define bot (grid-scroll-bottom g))
  (define cells (grid-cells g))
  (for ([i (in-range bot (+ top n -1) -1)])
    (vector-set! cells i (vector-copy (vector-ref cells (- i n)))))
  (for ([i (in-range top (+ top n))])
    (vector-set! cells i (make-vector (grid-cols g) blank-cell))))

(define (grid-set-scroll-region! g top bottom)
  (set-grid-scroll-top! g (max 0 (min (sub1 (grid-rows g)) top)))
  (set-grid-scroll-bottom! g (max (grid-scroll-top g)
                                  (min (sub1 (grid-rows g)) bottom))))

;; ── 控制字符 ─────────────────────────────────────────────

(define (grid-index! g)                     ; LF / IND：下移一行，保持列
  (set-grid-wrap-pending?! g #f)
  (define r (+ (grid-cursor-row g) 1))
  (if (> r (grid-scroll-bottom g))
      (grid-scroll-up! g 1)
      (set-grid-cursor-row! g r)))

(define (grid-reverse-index! g)             ; RI：上移一行
  (set-grid-wrap-pending?! g #f)
  (define r (- (grid-cursor-row g) 1))
  (if (< r (grid-scroll-top g))
      (grid-scroll-down! g 1)
      (set-grid-cursor-row! g r)))

(define (grid-wrap! g)                      ; 自动换行：回到列首并下移
  (set-grid-cursor-col! g 0)
  (grid-index! g)
  (set-grid-wrap-pending?! g #f))

(define (grid-carriage-return! g)
  (set-grid-cursor-col! g 0)
  (set-grid-wrap-pending?! g #f))

(define (grid-backspace! g)
  (set-grid-cursor-col! g (max 0 (- (grid-cursor-col g) 1)))
  (set-grid-wrap-pending?! g #f))

(define (grid-tab! g)
  (set-grid-wrap-pending?! g #f)
  (define c (grid-cursor-col g))
  (set-grid-cursor-col! g
                        (min (sub1 (grid-cols g))
                             (* 8 (add1 (quotient c 8))))))

;; ── 写字符 ───────────────────────────────────────────────

(define (grid-put-char! g ch)
  (define w (char-width ch))
  (cond
    ;; 组合记号 / 零宽：追加到前一个可见格
    [(= w 0)
     (define r (grid-cursor-row g))
     (define c (grid-cursor-col g))
     (define target
       (cond [(> c 0) (cons r (sub1 c))]
             [(> r 0) (cons (sub1 r) (sub1 (grid-cols g)))]
             [else #f]))
     (when target
       (define target-cell (grid-ref g (car target) (cdr target)))
       (when (string? (cell-text target-cell))
         (grid-set-cell! g (car target) (cdr target)
                         (cell (string-append (cell-text target-cell) (string ch))
                               (cell-fg target-cell)
                               (cell-bg target-cell)
                               (cell-attrs target-cell)))))]
    [else
     (when (grid-wrap-pending? g) (grid-wrap! g))
     (when (> (+ (grid-cursor-col g) w) (grid-cols g)) (grid-wrap! g))
     (define r (grid-cursor-row g))
     (define c (grid-cursor-col g))
     (grid-set-cell! g r c (cell (string ch) (grid-fg g) (grid-bg g) (grid-attrs g)))
     (when (= w 2)
       (when (< (add1 c) (grid-cols g))
         (grid-set-cell! g r (add1 c) (cell #f #f #f '()))))
     (define nc (+ c w))
     (cond
       [(>= nc (grid-cols g))
        (set-grid-cursor-col! g (sub1 (grid-cols g)))
        (set-grid-wrap-pending?! g #t)]
       [else (set-grid-cursor-col! g nc)])]))

;; ── 擦除 ─────────────────────────────────────────────────

(define (grid-erase-line! g mode)
  (define r (grid-cursor-row g))
  (define c (grid-cursor-col g))
  (define last (sub1 (grid-cols g)))
  (case mode
    [(0) (grid-fill-row! g r c last)]
    [(1) (grid-fill-row! g r 0 c)]
    [(2) (grid-fill-row! g r 0 last)]
    [else (void)]))

(define (grid-erase-display! g mode)
  (define r (grid-cursor-row g))
  (define c (grid-cursor-col g))
  (define rows (grid-rows g))
  (define cols (grid-cols g))
  (case mode
    [(0)
     (grid-fill-row! g r c (sub1 cols))
     (for ([i (in-range (add1 r) rows)])
       (grid-fill-row! g i 0 (sub1 cols)))]
    [(1)
     (for ([i (in-range 0 r)])
       (grid-fill-row! g i 0 (sub1 cols)))
     (grid-fill-row! g r 0 c)]
    [(2)
     (for ([i (in-range 0 rows)])
       (grid-fill-row! g i 0 (sub1 cols)))]
    [else (void)]))

;; ── 保存 / 恢复（DECSC/DECRC）────────────────────────────

(define (grid-save! g)
  (set-grid-saved! g (list (grid-cursor-row g) (grid-cursor-col g)
                           (grid-fg g) (grid-bg g) (grid-attrs g))))

(define (grid-restore! g)
  (define s (grid-saved g))
  (when s
    (define-values (r c fg bg at) (apply values s))
    (set-grid-cursor-row! g (max 0 (min (sub1 (grid-rows g)) r)))
    (set-grid-cursor-col! g (max 0 (min (sub1 (grid-cols g)) c)))
    (set-grid-fg! g fg)
    (set-grid-bg! g bg)
    (set-grid-attrs! g at)
    (set-grid-wrap-pending?! g #f)))

(define (grid-saved? g) (and (grid-saved g) #t))

;; ── 属性 ─────────────────────────────────────────────────

(define (grid-add-attr! g a)
  (unless (memq a (grid-attrs g))
    (set-grid-attrs! g (cons a (grid-attrs g)))))

(define (grid-remove-attr! g a)
  (set-grid-attrs! g (remq a (grid-attrs g))))

;; ── resize ───────────────────────────────────────────────

(define (grid-resize! g rows cols)
  (define old (grid-cells g))
  (define old-rows (grid-rows g))
  (define old-cols (grid-cols g))
  (define new-cells
    (for/vector ([r rows])
      (define row (make-vector cols blank-cell))
      (when (< r old-rows)
        (for ([c (in-range (min cols old-cols))])
          (vector-set! row c (vector-ref (vector-ref old r) c))))
      row))
  (set-grid-cells! g new-cells)
  (set-grid-rows! g rows)
  (set-grid-cols! g cols)
  (set-grid-scroll-top! g 0)
  (set-grid-scroll-bottom! g (max 0 (- rows 1)))
  (set-grid-cursor-row! g (min (grid-cursor-row g) (max 0 (- rows 1))))
  (set-grid-cursor-col! g (min (grid-cursor-col g) (max 0 (- cols 1))))
  (set-grid-wrap-pending?! g #f))
