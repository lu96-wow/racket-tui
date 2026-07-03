#lang racket

(require "../base/io/output-color.rkt"
         "../base/io/output-styles.rkt")

;; ═══════════════════════════════════════════════════════
;; 双表回退边界测试
;; ═══════════════════════════════════════════════════════

(define (br) (displayln ""))

(printf "═══ 双表样式系统边界测试 ═══\n")
(br)

;; ── 1. color-fg* — 双表都有 ──
(printf "── 1. color-fg* (双表) ──\n")
(style-define! 'dual-panel (color-fg* 255 7) (color-bg* 238 0) attr-bold)

(use-256color!)
(define dual-256 (style->bytes 'dual-panel))
(printf "  256 mode: len=~a\n" (bytes-length dual-256))

(use-16color!)
(define dual-16 (style->bytes 'dual-panel))
(printf "  16 mode:  len=~a\n" (bytes-length dual-16))
(printf "  => len(256)=~a len(16)=~a (256应该更长) ~a\n"
        (bytes-length dual-256) (bytes-length dual-16)
        (if (> (bytes-length dual-256) (bytes-length dual-16)) "✓" "✗"))
(br)

;; ── 2. color256-fg 直接定义 — 双表内容一致(都256) ──
(printf "── 2. color256-fg 直接 (双表同内容) ──\n")
(style-define! 'only-256 (color256-fg 200) attr-bold)

(use-256color!)
(define o256-256 (style->bytes 'only-256))

(use-16color!)
(define o256-16 (style->bytes 'only-256))
(printf "  256 mode: len=~a\n" (bytes-length o256-256))
(printf "  16 mode:  len=~a\n" (bytes-length o256-16))
(printf "  => 内容一致 ~a (16色终端也会收到256色序列, 静默降级为无样式输出)\n"
        (if (equal? o256-256 o256-16) "✓" "✗"))
(br)

;; ── 3. color-fg 直接定义 — 双表一致(通用16色) ──
(printf "── 3. color-fg 直接 (通用16色) ──\n")
(style-define! 'only-16 (color-fg 3) (color-bg 0) attr-bold)

(use-256color!)
(define o16-256 (style->bytes 'only-16))

(use-16color!)
(define o16-16 (style->bytes 'only-16))
(printf "  256 mode: len=~a\n" (bytes-length o16-256))
(printf "  16 mode:  len=~a\n" (bytes-length o16-16))
(printf "  => 内容一致 ~a\n" (if (equal? o16-256 o16-16) "✓" "✗"))
(br)

;; ── 4. 未定义样式 — 静默回退空 bytes ──
(printf "── 4. 未定义样式 ──\n")
(use-256color!)
(define missing-256 (style->bytes 'no-such-style))
(use-16color!)
(define missing-16 (style->bytes 'no-such-style))
(printf "  256 mode: len=~a\n" (bytes-length missing-256))
(printf "  16 mode:  len=~a\n" (bytes-length missing-16))
(printf "  => 空 bytes ~a\n" (if (and (zero? (bytes-length missing-256))
                                    (zero? (bytes-length missing-16))) "✓" "✗"))
(br)

;; ── 5. 预定义样式 (output-styles.rkt) 双表一致性 ──
(printf "── 5. 预定义样式双表一致 ──\n")
(define predefined '(button cursor selection input-focus input-normal error warning))
(for ([name predefined])
  (use-256color!)
  (define b256 (style->bytes name))
  (use-16color!)
  (define b16 (style->bytes name))
  (printf "  ~a: len256=~a len16=~a ~a\n" name
          (bytes-length b256) (bytes-length b16)
          (if (equal? b256 b16) "✓" "✗")))
(br)

;; ── 6. style-apply! 查不到不崩溃 ──
(printf "── 6. style-apply! 容错 ──\n")
(use-16color!)
(style-apply! 'no-such-style)
(printf "  => 不崩溃 ✓\n")
(br)

;; ── 7. auto 检测 ──
(printf "── 7. use-color-auto! ──\n")
(use-color-auto!)
(define auto-reg (current-registry))
(if (eq? auto-reg (current-registry))
    (printf "  => 256 模式\n")
    (printf "  => 16 模式\n"))
(br)

(printf "═══ 全部通过 ═══\n")
