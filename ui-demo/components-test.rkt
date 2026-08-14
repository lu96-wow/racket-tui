#lang racket

;; text / button 组件测试 — 离线断言
;; 运行: racket ui-demo/components-test.rkt

(require "../ui/main.rkt"
         "../base/io/input.rkt")

(define failures (box 0))
(define (check label got want)
  (if (equal? got want)
      (printf "PASS  ~a\n" label)
      (begin
        (set-box! failures (add1 (unbox failures)))
        (printf "FAIL  ~a\n  got : ~v\n  want: ~v\n" label got want))))

;; 渲染单个 widget → surface + element + ctx
(define (render-one w rows cols)
  (define e (resolve w 0 0 cols rows))
  (define rctx (make-render-ctx #:local-table (make-hasheq)))
  (define surf (make-surface rows cols))
  (render-element! e surf rctx)
  (values surf e rctx))

(define (plain s) (surface->ascii s #:mode 'plain))

;; ── text ──
(check "text 左对齐"
       (plain (let-values ([(s e c) (render-one (text "hi") 1 6)]) s))
       "hi    ")
(check "text 居中"
       (plain (let-values ([(s e c) (render-one (text "hi" #:h-align 'center) 1 6)]) s))
       "  hi  ")
(check "text 右对齐"
       (plain (let-values ([(s e c) (render-one (text "hi" #:h-align 'right) 1 6)]) s))
       "    hi")
(check "text 截断"
       (plain (let-values ([(s e c) (render-one (text "hello world") 1 6)]) s))
       "hello ")

;; ── button ──
(define b (button "OK" #:on-activate 'submit #:key 'b))
(define-values (bs be brctx) (render-one b 1 6))

(check "button 渲染"
       (plain bs)
       " OK   ")

(define on-evt (hash-ref (widget-props b) 'on-event))
(define wctx (widget-ctx b brctx))
(define rect (element-rect be))

(check "button enter → 消息"
       (on-evt b 'enter #f rect wctx)
       'submit)
(check "button space → 消息"
       (on-evt b 'space #f rect wctx)
       'submit)

;; press 置 pressed，不产生消息
(check "button press 无消息"
       (on-evt b 'mouse (list 'press 'left 0 0 '()) rect wctx)
       #f)
(check "button press 后 local=pressed"
       (hash-ref (widget-ctx b brctx) 'local)
       #t)

;; release 在按钮内 → 激活
(check "button release 内 → 消息"
       (on-evt b 'mouse (list 'release 'left 0 0 '()) rect wctx)
       'submit)

;; release 在按钮外 → 不激活
(check "button release 外 → 无消息"
       (on-evt b 'mouse (list 'release 'left 20 20 '()) rect wctx)
       #f)

;; ── 汇总 ──
(if (zero? (unbox failures))
    (printf "\nALL TESTS PASSED\n")
    (begin
      (printf "\n~a TEST(S) FAILED\n" (unbox failures))
      (exit 1)))
