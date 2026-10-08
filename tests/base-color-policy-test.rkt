#lang racket

;; ════════════════════════════════════════════════════════════════
;; tests/base-color-policy-test.rkt
;;   raco test tests/base-color-policy-test.rkt
;; ════════════════════════════════════════════════════════════════

(require rackunit
         "../base/io/color-policy.rkt"
         "../base/terminal/features.rkt"
         "../base/io/output-color.rkt")

(define (f color) (features color #f #f #f #f #f))

(module+ test
  ;; 返回值 = 选中的档位
  (check-equal? (use-color-from-features! (f '16)) '16)
  (check-equal? (use-color-from-features! (f '256)) '256)
  (check-equal? (use-color-from-features! (f 'truecolor)) 'truecolor)

  ;; 确实切换了 base 的 registry
  (define r16 (begin (use-color-from-features! (f '16)) (current-registry)))
  (define r256 (begin (use-color-from-features! (f '256)) (current-registry)))
  (define rtrue (begin (use-color-from-features! (f 'truecolor)) (current-registry)))
  (check-not-eq? r16 r256 "16 与 256 是不同 registry")
  (check-eq? r256 rtrue "truecolor 复用 256 档（命名样式）"))
