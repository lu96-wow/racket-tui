#lang racket

;; output 测试
;; 运行: racket ui-demo/output-test.rkt

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

;; ── 自动滚动到末尾（10 行，视口高 3）──
(define out1 (output #:lines (map number->string (range 10)) #:key 'o))
(define-values (s1 e1 c1) (render-one out1 3 6))
(check "output 自动滚动到底"
       (plain s1)
       "7    │\n8    │\n9    █")

;; ── 样式行 ──
(define out2 (output #:lines (list "a" (cons "err" 'error) "c")
                     #:style 'info #:auto-scroll? #f #:key 'o2))
(define-values (s2 e2 c2) (render-one out2 3 6))
(check "output 样式行"
       (surface->ascii s2 #:mode 'grid #:space-char #\·)
       (string-join
        '("Legend (2 styles + default):"
          "  . default"
          "  A error"
          "  B info"
          "style: BBBBBB"
          "text : a·····"
          "style: AAABBB"
          "text : err···"
          "style: BBBBBB"
          "text : c·····")
        "\n"))

;; ── 滚动事件 ──
(define oevt (hash-ref (widget-props out1) 'on-event))
(define orect (element-rect e1))
(define octx (widget-ctx out1 c1))

(check "初始 scroll=7（已 auto-scroll）"
       (car (hash-ref octx 'local)) 7)

(oevt out1 'up #f orect octx)
(check "up → scroll=6"
       (car (hash-ref (widget-ctx out1 c1) 'local)) 6)

(oevt out1 'home #f orect octx)
(check "home → scroll=0"
       (car (hash-ref (widget-ctx out1 c1) 'local)) 0)

(oevt out1 'end #f orect octx)
(check "end → scroll=7"
       (car (hash-ref (widget-ctx out1 c1) 'local)) 7)

;; ── 滚动条拖拽 ──
(check "press 滚动条 → dragging"
       (oevt out1 'mouse (list 'press 'left 5 0 '()) orect octx)
       #f)
(check "press 后 dragging?"
       (let ([l (hash-ref (widget-ctx out1 c1) 'local)]) (caddr l))
       #t)
(oevt out1 'mouse (list 'move 'left 5 0 '()) orect octx)
(oevt out1 'mouse (list 'release 'left 5 0 '()) orect octx)
(check "release 后 dragging? 清除"
       (let ([l (hash-ref (widget-ctx out1 c1) 'local)]) (caddr l))
       #f)

;; ── 长行自动换行（width 6, cw 5）──
(define-values (sw ew cw_)
  (render-one (output #:lines (list "abcdefghij") #:auto-scroll? #f #:key 'w) 3 6))
(check "长行换行" (plain sw) "abcde \nfghij \n      ")

;; ── 汇总 ──
(if (zero? (unbox failures))
    (printf "\nALL TESTS PASSED\n")
    (begin
      (printf "\n~a TEST(S) FAILED\n" (unbox failures))
      (exit 1)))
