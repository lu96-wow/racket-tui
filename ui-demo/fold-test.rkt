#lang racket

;; output 折叠块测试（宽 12，cw=11，避免头行换行干扰）
;; 运行: racket ui-demo/fold-test.rkt

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

(define lines
  (list (fold-block 'e (cons "Errors" 'error) (list "e1" "e2"))))

;; ── 展开 ──
(define-values (s1 e1 c1)
  (render-one (output #:lines lines #:folded '() #:key 'o) 3 12))
(check "展开渲染" (plain s1)
       "▼ Errors    \ne1          \ne2          ")

;; ── 折叠 ──
(define-values (s2 e2 c2)
  (render-one (output #:lines lines #:folded '(e) #:key 'o) 3 12))
(check "折叠渲染" (plain s2)
       "▶ Errors    \n            \n            ")

;; ── 点击折叠头 → toggle 消息 ──
(define captured (box #f))
(define w3 (output #:lines lines #:folded '()
                   #:on-toggle-fold (λ (id) (set-box! captured id) id)
                   #:key 'o))
(define-values (s3 e3 c3) (render-one w3 3 12))
(define evt (hash-ref (widget-props w3) 'on-event))
(check "点击头 → 消息"
       (evt w3 'mouse (list 'press 'left 0 0 '()) (element-rect e3) (widget-ctx w3 c3))
       'e)
(check "回调收到 id" (unbox captured) 'e)

;; ── 嵌套折叠 ──
(define nested
  (list (fold-block 'outer (cons "Outer" 'info)
          (list "o1"
                (fold-block 'inner (cons "Inner" 'info) (list "i1"))
                "o2"))))

(define-values (s4 e4 c4)
  (render-one (output #:lines nested #:folded '() #:key 'o) 5 12))
(check "嵌套展开" (plain s4)
       "▼ Outer     \no1          \n▼ Inner     \ni1          \no2          ")

(define-values (s5 e5 c5)
  (render-one (output #:lines nested #:folded '(inner) #:key 'o) 5 12))
(check "嵌套只折 inner" (plain s5)
       "▼ Outer     \no1          \n▶ Inner     \no2          \n            ")

(define-values (s6 e6 c6)
  (render-one (output #:lines nested #:folded '(outer) #:key 'o) 5 12))
(check "折 outer 隐藏全部 body" (plain s6)
       "▶ Outer     \n            \n            \n            \n            ")

;; ── 汇总 ──
(if (zero? (unbox failures))
    (printf "\nALL TESTS PASSED\n")
    (begin
      (printf "\n~a TEST(S) FAILED\n" (unbox failures))
      (exit 1)))
