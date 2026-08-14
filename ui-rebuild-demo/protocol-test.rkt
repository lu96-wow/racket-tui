#lang racket

;; widget 协议测试 — 用 input / output 验证 leaf 协议
;; 运行: racket ui-rebuild-demo/protocol-test.rkt

(require "../ui-rebuild/main.rkt"
         "../base/io/input.rkt")

(define failures (box 0))
(define (check label got want)
  (if (equal? got want)
      (printf "PASS  ~a\n" label)
      (begin
        (set-box! failures (add1 (unbox failures)))
        (printf "FAIL  ~a\n  got : ~v\n  want: ~v\n" label got want))))

;; ── 协议：ctx 契约（focus-key / local / set-local!）──

(define seen (box #f))
(define lw (leaf #:key 'k #:local (λ () 42) #:focusable? #t
                 #:render (λ (w rect ctx surf) (set-box! seen ctx))))
(define lt (make-hasheq))
(define rctx (make-render-ctx #:focus-key 'k #:local-table lt))
(render-element! (resolve lw 0 0 5 5) (make-surface 5 5) rctx)
(define ctx (unbox seen))

(check "ctx 有 focus-key" (hash-ref ctx 'focus-key #f) 'k)
(check "ctx 有 local 初始值" (hash-ref ctx 'local #f) 42)
(check "ctx 有 set-local!" (procedure? (hash-ref ctx 'set-local! #f)) #t)
((hash-ref ctx 'set-local!) 99)
(check "set-local! 持久化" (hash-ref (widget-ctx lw rctx) 'local) 99)

;; ── 协议：keyed local state 按 key 独立 ──

(define lt2 (make-hasheq))
(define i1 (input #:value "abc" #:key 'a))
(define i2 (input #:value "x" #:key 'b))
(render-element! (resolve (vstack i1 i2) 0 0 2 10)
                 (make-surface 2 10)
                 (make-render-ctx #:local-table lt2))
(check "input a 光标=3" (hash-ref lt2 'a) 3)
(check "input b 光标=1" (hash-ref lt2 'b) 1)

;; ── 协议：focus-key 影响组件渲染（input 聚焦样式）──

(define (render-input-focused? focused?)
  (define lt3 (make-hasheq))
  (define w (input #:value "hi" #:key 'inp))
  (define e (resolve w 0 0 6 1))
  (define surf (make-surface 1 6))
  (render-element! e surf (make-render-ctx #:focus-key (and focused? 'inp) #:local-table lt3))
  (surface->ascii surf #:mode 'grid #:space-char #\·))

;; 非聚焦 → input-normal；聚焦 → input-focus
(check "input 非聚焦用 nofocus 样式"
       (render-input-focused? #f)
       (string-join
        '("Legend (1 styles + default):"
          "  . default"
          "  A input-normal"
          "style: AAAAAA"
          "text : hi····")
        "\n"))

(check "input 聚焦用 focus 样式"
       (render-input-focused? #t)
       (string-join
        '("Legend (2 styles + default):"
          "  . default"
          "  A cursor"
          "  B input-focus"
          "style: BBABBB"
          "text : hi····")
        "\n"))

;; ── 协议：output 局部状态形状 + 持久化 ──

(define lt4 (make-hasheq))
(define o (output #:lines (map number->string (range 10)) #:key 'out))
(render-element! (resolve o 0 0 8 3) (make-surface 3 8)
                 (make-render-ctx #:local-table lt4))
(check "output 局部状态形状 (scroll last-total dragging?)"
       (hash-ref lt4 'out)
       '(7 10 #f))

;; ── 汇总 ──
(if (zero? (unbox failures))
    (printf "\nALL TESTS PASSED\n")
    (begin
      (printf "\n~a TEST(S) FAILED\n" (unbox failures))
      (exit 1)))
