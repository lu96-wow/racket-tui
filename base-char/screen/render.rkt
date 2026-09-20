#lang racket

;; 网格 → 纯字符图（默认调试产物），以及按需的属性/颜色查询。
;;
;; 默认渲染不带任何转义序列，直接就是终端里看到的字符布局。
;; 属性/颜色不进入默认输出，需要时用 screen-ref / screen-styled-cells /
;; screen-attr-ranges 单独取。

(require "grid.rkt")

(provide grid->lines
         grid->text
         screen->lines
         screen->text
         screen-ref
         screen-cursor-cell
         screen-size
         screen-cursor
         screen-style-at
         screen-current-style
         screen-styled-cells
         screen-attr-ranges
         style->string)

;; 单元格在纯字符图里的可见文本：
;;   普通文本 → 原文
;;   宽字符右半格(#f) → ""（宽度已由左邻字符体现）
;;   空白 → " "
(define (cell->display c)
  (define t (cell-text c))
  (cond [(string? t) t]
        [(eq? t #f) ""]
        [else " "]))

(define (grid->lines g #:trim-right? [trim? #t])
  (for/list ([r (in-range (grid-rows g))])
    (define s (string-append*
               (for/list ([c (in-range (grid-cols g))])
                 (cell->display (grid-ref g r c)))))
    (if trim?
        (string-trim s #:left? #f #:right? #t)
        s)))

(define (grid->text g #:trim-right? [trim? #t])
  (string-join (grid->lines g #:trim-right? trim?) "\n"))

;; 与 screen-* 查询族保持命名一致的别名
(define screen->lines grid->lines)
(define screen->text grid->text)

;; ── 按需查询 ─────────────────────────────────────────────

(define (screen-ref g row col) (grid-ref g row col))
(define (screen-cursor-cell g) (grid-ref g (grid-cursor-row g) (grid-cursor-col g)))
(define (screen-size g) (values (grid-rows g) (grid-cols g)))
(define (screen-cursor g) (grid-cursor g))

;; 某一格的属性字符串（避免手动两步）
(define (screen-style-at g row col)
  (style->string (grid-ref g row col)))

;; 当前 SGR 状态（下一个字符会带上的属性）
(define (screen-current-style g)
  (style->string (cell #f (grid-fg g) (grid-bg g) (grid-attrs g))))

;; 属性序列化成可读字符串，例如 "fg#9 bold"
(define (style->string c)
  (define parts
    (append
     (cond [(cell-fg c) => (λ (v) (list (string-append "fg" (color->string v))))]
           [else '()])
     (cond [(cell-bg c) => (λ (v) (list (string-append "bg" (color->string v))))]
           [else '()])
     (sort (map symbol->string (cell-attrs c)) string<?)))
  (string-join parts " "))

(define (color->string v)
  (case (car v)
    [(idx) (string-append "#" (number->string (cadr v)))]
    [(rgb) (format "(~a,~a,~a)" (cadr v) (caddr v) (cadddr v))]
    [else ""]))

;; 只列出非默认（带属性/颜色，或非空格）的格；宽字符的右半格(#f)不算内容
(define (screen-styled-cells g)
  (for*/list ([r (in-range (grid-rows g))]
              [c (in-range (grid-cols g))]
              #:when (let ([cell (grid-ref g r c)])
                       (and (string? (cell-text cell))
                            (not (cell-default? cell)))))
    (define cell (grid-ref g r c))
    (list r c (cell-text cell) (style->string cell))))

;; 按行把属性压成区间，token 更省
(define (screen-attr-ranges g)
  (for/list ([r (in-range (grid-rows g))])
    (define runs '())
    (define cur #f)
    (for ([c (in-range (grid-cols g))])
      (define s (style->string (grid-ref g r c)))
      (cond
        [(or (not cur) (not (equal? s (vector-ref cur 0))))
         (set! cur (vector s c c))
         (set! runs (cons cur runs))]
        [else (vector-set! cur 2 c)]))
    (list r (reverse (map (λ (x) (list (vector-ref x 1) (vector-ref x 2) (vector-ref x 0))) runs)))))
