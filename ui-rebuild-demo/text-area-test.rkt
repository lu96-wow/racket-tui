#lang racket

;; text-area（多行输入）测试
;; 运行: racket ui-rebuild-demo/text-area-test.rkt

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

(define (make-ta value)
  (define captured (box #f))
  (define w (text-area #:value value #:key 'ta
                       #:on-change (λ (t) (set-box! captured t) (list 'ch t))
                       #:on-submit (λ (t) (list 'sub t))))
  (define-values (s e c) (render-one w 3 6))
  (values w (element-rect e) c captured))

(define (fire w rect c type data)
  ((hash-ref (widget-props w) 'on-event) w type data rect (widget-ctx w c)))

(define (cursor-of w c) (car (hash-ref (widget-ctx w c) 'local)))
(define (pref-of w c)   (cdr (hash-ref (widget-ctx w c) 'local)))

;; ── 渲染 ──
(check "多行渲染"
       (plain (let-values ([(s e c) (render-one (text-area #:value "ab\ncd" #:key 'ta) 3 6)]) s))
       "ab    \ncd    \n      ")

;; ── 编辑 ──
(define-values (w1 r1 c1 cap1) (make-ta "ab"))
(check "insert" (fire w1 r1 c1 #\c #f) '(ch "abc"))
(check "escape 插入换行" (fire w1 r1 c1 'escape #f) '(ch "ab\n"))
(check "alt-enter 插入换行" (fire w1 r1 c1 'alt-enter #f) '(ch "ab\n"))
(check "backspace" (fire w1 r1 c1 'backspace #f) '(ch "a"))

;; ── 光标移动（value = "abc\ndef"，len=7，行起点 (0 4)）──
(define-values (w2 r2 c2 cap2) (make-ta "abc\ndef"))

;; home：光标初始在末尾 7 → 第二行行首 4
(fire w2 r2 c2 'home #f)
(check "home 后光标" (cursor-of w2 c2) 4)
(check "home 后 pref-col" (pref-of w2 c2) 0)

;; end：回末尾 7
(fire w2 r2 c2 'end #f)
(check "end 后光标" (cursor-of w2 c2) 7)

;; up：设 pref-col=2（第二行 col 2），应到第一行 col 2 → pos 2
((hash-ref (widget-ctx w2 c2) 'set-local!) (cons 7 2))
(fire w2 r2 c2 'up #f)
(check "up 后光标=2" (cursor-of w2 c2) 2)
(check "up 后 pref-col=2" (pref-of w2 c2) 2)

;; 再 up：已在第一行，不动
(fire w2 r2 c2 'up #f)
(check "再 up 不动" (cursor-of w2 c2) 2)

;; down：pref-col=2 → 第二行 col 2 → pos 5
(fire w2 r2 c2 'down #f)
(check "down 后光标=6" (cursor-of w2 c2) 6)

;; ── 汇总 ──
(if (zero? (unbox failures))
    (printf "\nALL TESTS PASSED\n")
    (begin
      (printf "\n~a TEST(S) FAILED\n" (unbox failures))
      (exit 1)))
