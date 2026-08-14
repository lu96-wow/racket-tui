#lang racket

;; bool-button / input 组件测试 — 离线断言
;; 运行: racket ui-rebuild-demo/widgets-test.rkt

(require "../ui-rebuild/main.rkt"
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

;; ═══ bool-button ═══

(define bb-on  (bool-button "OK" #:value #t #:on-toggle 'toggled))
(define bb-off (bool-button "OK" #:value #f #:on-toggle 'toggled))

(check "bool 开 渲染"
       (plain (let-values ([(s e c) (render-one bb-on 1 8)]) s))
       "[x] OK  ")
(check "bool 关 渲染"
       (plain (let-values ([(s e c) (render-one bb-off 1 8)]) s))
       "[ ] OK  ")

(define-values (bs be bc) (render-one bb-on 1 8))
(define bb-on-evt (hash-ref (widget-props bb-on) 'on-event))
(define bb-ctx (widget-ctx bb-on bc))
(define bb-rect (element-rect be))

(check "bool enter → 消息" (bb-on-evt bb-on 'enter #f bb-rect bb-ctx) 'toggled)
(check "bool space → 消息" (bb-on-evt bb-on 'space #f bb-rect bb-ctx) 'toggled)
(check "bool 点击 → 消息"
       (bb-on-evt bb-on 'mouse (list 'press 'left 0 0 '()) bb-rect bb-ctx)
       'toggled)

;; ═══ input ═══

(define (make-input-test value)
  (define captured (box #f))
  (define w (input #:value value #:key 'inp
                   #:on-change (λ (t) (set-box! captured t) (list 'ch t))
                   #:on-submit (λ (t) (list 'sub t))))
  (define-values (s e c) (render-one w 1 20))
  (values w (element-rect e) c captured))

;; 渲染（非聚焦，无光标）
(check "input 渲染"
       (plain (let-values ([(s e c) (render-one (input #:value "hi" #:key 'inp) 1 8)]) s))
       "hi      ")

;; insert
(define-values (iw1 ir1 ic1 cap1) (make-input-test "hi"))
(define iw1-evt (hash-ref (widget-props iw1) 'on-event))
(check "input insert → 消息"
       (iw1-evt iw1 #\! #f ir1 (widget-ctx iw1 ic1))
       '(ch "hi!"))
(check "input insert 光标前进"
       (hash-ref (widget-ctx iw1 ic1) 'local) 3)

;; backspace
(define-values (iw2 ir2 ic2 cap2) (make-input-test "hi"))
(define iw2-evt (hash-ref (widget-props iw2) 'on-event))
(check "input backspace → 消息"
       (iw2-evt iw2 'backspace #f ir2 (widget-ctx iw2 ic2))
       '(ch "h"))
(check "input backspace 光标后退"
       (hash-ref (widget-ctx iw2 ic2) 'local) 1)

;; delete
(define-values (iw3 ir3 ic3 cap3) (make-input-test "hi"))
(define iw3-evt (hash-ref (widget-props iw3) 'on-event))
;; 光标先移到 1（delete 删光标后的字符）
((hash-ref (widget-ctx iw3 ic3) 'set-local!) 1)
(check "input delete → 消息"
       (iw3-evt iw3 'delete #f ir3 (widget-ctx iw3 ic3))
       '(ch "h"))

;; enter
(define-values (iw4 ir4 ic4 cap4) (make-input-test "hi"))
(define iw4-evt (hash-ref (widget-props iw4) 'on-event))
(check "input enter → submit 消息"
       (iw4-evt iw4 'enter #f ir4 (widget-ctx iw4 ic4))
       '(sub "hi"))

;; ── 汇总 ──
(if (zero? (unbox failures))
    (printf "\nALL TESTS PASSED\n")
    (begin
      (printf "\n~a TEST(S) FAILED\n" (unbox failures))
      (exit 1)))
