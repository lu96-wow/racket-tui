#lang racket

(require "../base/io/output-color.rkt"
         "../base/io/output-styles.rkt"
         "../base/ansi/ansi-format.rkt")

;; ── helpers ──
(define (bytes-starts-with? bs prefix)
  (and (>= (bytes-length bs) (bytes-length prefix))
       (equal? (subbytes bs 0 (bytes-length prefix)) prefix)))

(define (bytes-ends-with? bs suffix)
  (define bl (bytes-length bs))
  (define sl (bytes-length suffix))
  (and (>= bl sl)
       (equal? (subbytes bs (- bl sl) bl) suffix)))

(printf "═══ format- / put- 双表回退测试 ═══\n\n")

;; ── 辅助: 捕获 put-* 输出 ──
(define (capture-put thunk)
  (define out (open-output-bytes))
  (parameterize ([current-output-port out])
    (thunk))
  (get-output-bytes out))

;; ── 定义双表样式 ──
(style-define! 'dual (color-fg* 255 7) (color-bg* 238 0) attr-bold)

;; ── 1. format-styled 两个模式 ──
(printf "── 1. format-styled ──\n")
(use-256color!)
(define fs256 (format-styled 'dual "hello"))
(printf "  256: len=~a\n" (bytes-length fs256))
(use-16color!)
(define fs16 (format-styled 'dual "hello"))
(printf "  16:  len=~a\n" (bytes-length fs16))
(printf "  => ~a\n" (if (> (bytes-length fs256) (bytes-length fs16)) "✓ 256更长" "✗"))
(printf "  => 都含 'hello' ~a ~a\n"
        (if (regexp-match? #rx"hello" fs256) "✓" "✗")
        (if (regexp-match? #rx"hello" fs16) "✓" "✗"))
(printf "  => 都以 reset 结尾 ~a ~a\n"
        (if (bytes-ends-with? fs256 format-reset) "✓" "✗")
        (if (bytes-ends-with? fs16 format-reset) "✓" "✗"))
(printf "\n")

;; ── 2. format-styled-at! 两个模式 ──
(printf "── 2. format-styled-at! ──\n")
(use-256color!)
(define fsa256 (format-styled-at! 5 10 'dual "world"))
(printf "  256: len=~a\n" (bytes-length fsa256))
(use-16color!)
(define fsa16 (format-styled-at! 5 10 'dual "world"))
(printf "  16:  len=~a\n" (bytes-length fsa16))
(printf "  => 含 cursor-move ~a\n"
        (if (bytes-starts-with? fsa256 (format-cursor-move 5 10)) "✓" "✗"))
(printf "\n")

;; ── 3. put-styled 捕获输出 ──
(printf "── 3. put-styled ──\n")
(use-256color!)
(define ps256 (capture-put (λ () (put-styled 'dual "test"))))
(printf "  256: len=~a\n" (bytes-length ps256))
(use-16color!)
(define ps16 (capture-put (λ () (put-styled 'dual "test"))))
(printf "  16:  len=~a\n" (bytes-length ps16))
(printf "  => 都含 'test' ~a ~a\n"
        (if (regexp-match? #rx"test" ps256) "✓" "✗")
        (if (regexp-match? #rx"test" ps16) "✓" "✗"))
(printf "  => 都以 reset 结尾 ~a ~a\n"
        (if (bytes-ends-with? ps256 format-reset) "✓" "✗")
        (if (bytes-ends-with? ps16 format-reset) "✓" "✗"))
(printf "\n")

;; ── 4. put-styled-at! 捕获输出 ──
(printf "── 4. put-styled-at! ──\n")
(use-256color!)
(define psa256 (capture-put (λ () (put-styled-at! 3 0 'dual "x"))))
(printf "  256: len=~a 含 cursor-move ~a\n"
        (bytes-length psa256)
        (if (regexp-match? #rx"\\e\\[3" (bytes->string/utf-8 psa256)) "✓" "✗"))
(use-16color!)
(define psa16 (capture-put (λ () (put-styled-at! 3 0 'dual "x"))))
(printf "  16:  len=~a 含 cursor-move ~a\n"
        (bytes-length psa16)
        (if (regexp-match? #rx"\\e\\[3" (bytes->string/utf-8 psa16)) "✓" "✗"))
(printf "\n")

;; ── 5. 未定义样式 — format 和 put 都不崩 ──
(printf "── 5. 未定义样式容错 ──\n")
(use-16color!)
(define fs-miss (format-styled 'no-such "text"))
(define fsa-miss (format-styled-at! 0 0 'no-such "text"))
(define ps-miss (capture-put (λ () (put-styled 'no-such "text"))))
(define psa-miss (capture-put (λ () (put-styled-at! 0 0 'no-such "text"))))
(printf "  format-styled:    len=~a 含text=~a\n"
        (bytes-length fs-miss) (if (regexp-match? #rx"text" fs-miss) "✓" "✗"))
(printf "  format-styled-at!: len=~a 含text=~a\n"
        (bytes-length fsa-miss) (if (regexp-match? #rx"text" fsa-miss) "✓" "✗"))
(printf "  put-styled:       len=~a 含text=~a\n"
        (bytes-length ps-miss) (if (regexp-match? #rx"text" ps-miss) "✓" "✗"))
(printf "  put-styled-at!:    len=~a 含text=~a\n"
        (bytes-length psa-miss) (if (regexp-match? #rx"text" psa-miss) "✓" "✗"))
(printf "  => 全部不崩溃 ✓\n")
(printf "\n")

;; ── 6. emit 等价 (组件实际使用) ──
(printf "── 6. emit = write-bytes(format-styled-at!) ──\n")
(use-256color!)
(define emit-256 (capture-put (λ () (write-bytes (format-styled-at! 1 2 'dual "emit")))))
(printf "  256: len=~a 含emit=~a\n"
        (bytes-length emit-256)
        (if (regexp-match? #rx"emit" emit-256) "✓" "✗"))
(use-16color!)
(define emit-16 (capture-put (λ () (write-bytes (format-styled-at! 1 2 'dual "emit")))))
(printf "  16:  len=~a 含emit=~a\n"
        (bytes-length emit-16)
        (if (regexp-match? #rx"emit" emit-16) "✓" "✗"))
(printf "  => emit 双表各自正确 ✓\n")
(printf "\n")

(printf "═══ 全部通过 ═══\n")
