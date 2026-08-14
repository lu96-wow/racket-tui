#lang racket

;; 核心单元测试 — 不依赖终端，用 surface->ascii / 布局 / 局部状态断言
;; 运行: racket ui-rebuild-demo/core-tests.rkt

(require "../ui-rebuild/main.rkt")

(define failures (box 0))

(define (check label got want)
  (if (equal? got want)
      (printf "PASS  ~a\n" label)
      (begin
        (set-box! failures (add1 (unbox failures)))
        (printf "FAIL  ~a\n  got : ~v\n  want: ~v\n" label got want))))

;; ── 布局 min/max ──
(define (vstack-heights w span)
  (map (λ (c) (fourth (element-rect c)))
       (element-children (resolve w 0 0 10 span))))

(check "min/max 约束"
       (vstack-heights
        (vstack (child (leaf #:key 'a) #:min 1 #:max 1)
                (child (leaf #:key 'b) #:weight 2 #:min 3)
                (child (leaf #:key 'c) #:weight 1 #:max 2))
        10)
       '(1 7 2))

(check "max 上限"
       (vstack-heights
        (vstack (child (leaf #:key 'a) #:max 2)
                (child (leaf #:key 'b) #:weight 2)
                (child (leaf #:key 'c) #:max 1))
        10)
       '(2 7 1))

(check "min 超限溢出"
       (vstack-heights
        (vstack (child (leaf #:key 'a) #:min 5)
                (child (leaf #:key 'b) #:min 5)
                (child (leaf #:key 'c) #:min 5))
        10)
       '(5 5 5))

(check "纯权重"
       (vstack-heights (vstack (leaf #:key 'a) (leaf #:key 'b)) 10)
       '(5 5))

;; ── 命中测试（panel 边框不吞内部事件）──
(define panel-elem (resolve (panel (leaf #:key 'x)) 0 0 10 5))

(check "边框不命中" (element-hit panel-elem 0 0) #f)
(check "内容命中 leaf"
       (widget-key (element-widget (element-hit panel-elem 1 1)))
       'x)

;; ── 焦点顺序 ──
(define focus-elem
  (resolve (vstack (leaf #:key 'a #:focusable? #t)
                   (leaf #:key 'b)
                   (leaf #:key 'c #:focusable? #t))
           0 0 10 10))

(check "焦点顺序 DFS"
       (map (λ (e) (widget-key (element-widget e)))
            (element-focusables focus-elem))
       '(a c))

;; ── surface + ascii dump ──
(define surf (make-surface 3 10))
(surface-put-string! surf 0 0 "HELLO" 'info)
(surface-put-string! surf 1 0 "world" 'selection)

(check "ascii plain"
       (surface->ascii surf #:mode 'plain #:space-char #\·)
       "HELLO·····\nworld·····\n··········")

(check "ascii grid 样式行"
       (surface->ascii surf #:mode 'grid #:space-char #\·)
       (string-join
        '("Legend (2 styles + default):"
          "  . default"
          "  A info"
          "  B selection"
          "style: AAAAA....."
          "text : HELLO·····"
          "style: BBBBB....."
          "text : world·····"
          "style: .........."
          "text : ··········")
        "\n"))

;; ── keyed local state ──
(define lt (make-hasheq))
(define rctx (make-render-ctx #:focus-key 'k #:local-table lt))
(define lw (leaf #:key 'k #:local (λ () 1)))
(define lctx (widget-ctx lw rctx))

(check "local 初始化" (hash-ref lctx 'local) 1)
((hash-ref lctx 'set-local!) 2)
(check "local 更新" (hash-ref (widget-ctx lw rctx) 'local) 2)

;; ── 汇总 ──
(if (zero? (unbox failures))
    (printf "\nALL TESTS PASSED\n")
    (begin
      (printf "\n~a TEST(S) FAILED\n" (unbox failures))
      (exit 1)))
