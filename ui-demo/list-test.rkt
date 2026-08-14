#lang racket

;; list / scrollbar 测试
;; 运行: racket ui-demo/list-test.rkt

(require "../ui/main.rkt"
         "../base/io/input.rkt")

(define failures (box 0))
(define (check label got want)
  (if (equal? got want)
      (printf "PASS  ~a\n" label)
      (begin
        (set-box! failures (add1 (unbox failures)))
        (printf "FAIL  ~a\n  got : ~v\n  want: ~v\n" label got want))))

(define (render-one w rows cols)
  (define e (resolve w 0 0 cols rows))
  (define rctx (make-render-ctx #:local-table (make-hasheq)))
  (define surf (make-surface rows cols))
  (render-element! e surf rctx)
  (values surf e rctx))

(define (plain s) (surface->ascii s #:mode 'plain))

(define (make-list items selected)
  (define w (list-box #:items items #:selected selected
                      #:on-select (λ (i) (list 'select i))
                      #:key 'l))
  (define-values (s e c) (render-one w 3 6))
  (values w (element-rect e) c s))

;; ── 渲染 ──
(define-values (lw lr lc ls) (make-list '("a" "b" "c") 1))

(check "list 内容"
       (plain ls)
       "a     \nb     \nc     ")

(check "list 选中行高亮"
       (surface->ascii ls #:mode 'grid #:space-char #\·)
       (string-join
        '("Legend (2 styles + default):"
          "  . default"
          "  A info"
          "  B selection"
          "style: AAAAAA"
          "text : a·····"
          "style: BBBBBA"
          "text : b·····"
          "style: AAAAAA"
          "text : c·····")
        "\n"))

;; ── 键盘 ──
(define levt (hash-ref (widget-props lw) 'on-event))

(check "list down → 选中 2"
       (levt lw 'down #f lr (widget-ctx lw lc))
       '(select 2))
(check "list up → 选中 0"
       (levt lw 'up #f lr (widget-ctx lw lc))
       '(select 0))
(check "list home → 选中 0"
       (levt lw 'home #f lr (widget-ctx lw lc))
       '(select 0))
(check "list end → 选中 2"
       (levt lw 'end #f lr (widget-ctx lw lc))
       '(select 2))

;; ── 滚动条拖拽（10 项，视口高 3）──
(define lw2 (list-box #:items (map number->string (range 10))
                      #:selected 0
                      #:on-select (λ (i) (list 'select i))
                      #:key 'l2))
(define-values (ls2 le2 lc2) (render-one lw2 3 8))
(define lr2 (element-rect le2))

(define l2evt (hash-ref (widget-props lw2) 'on-event))

;; press 在滚动条列（x=7, y=0）→ 开始拖拽
(check "scrollbar press 开始拖拽"
       (l2evt lw2 'mouse (list 'press 'left 7 0 '()) lr2 (widget-ctx lw2 lc2))
       #f)
(check "press 后 dragging?"
       (let ([l (hash-ref (widget-ctx lw2 lc2) 'local)])
         (cadr l))
       #t)

;; move 到 y=2 → 滚到底
(l2evt lw2 'mouse (list 'move 'left 7 2 '()) lr2 (widget-ctx lw2 lc2))
(check "move 后 scroll=7"
       (let ([l (hash-ref (widget-ctx lw2 lc2) 'local)])
         (car l))
       7)

;; release 停止拖拽
(l2evt lw2 'mouse (list 'release 'left 7 2 '()) lr2 (widget-ctx lw2 lc2))
(check "release 后 dragging? 清除"
       (let ([l (hash-ref (widget-ctx lw2 lc2) 'local)])
         (cadr l))
       #f)

;; ── 汇总 ──
(if (zero? (unbox failures))
    (printf "\nALL TESTS PASSED\n")
    (begin
      (printf "\n~a TEST(S) FAILED\n" (unbox failures))
      (exit 1)))
