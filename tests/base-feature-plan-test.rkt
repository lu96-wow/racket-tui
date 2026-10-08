#lang racket

;; ════════════════════════════════════════════════════════════════
;; tests/base-feature-plan-test.rkt
;;   raco test tests/base-feature-plan-test.rkt
;; ════════════════════════════════════════════════════════════════

(require rackunit
         "../base/terminal/feature-plan.rkt"
         "../base/terminal/features.rkt")

(define log (box '()))
(define (rec! x) (set-box! log (cons x (unbox log))))
(define (reset!) (set-box! log '()))

(define (make-test-plan)
  (list (faction 'alt   features-alt-screen? (λ () (rec! 'e-alt))   (λ () (rec! 'd-alt))   0)
        (faction 'mouse features-mouse?      (λ () (rec! 'e-mouse)) (λ () (rec! 'd-mouse)) 0)
        (faction 'paste features-paste?      (λ () (rec! 'e-paste)) (λ () (rec! 'd-paste)) 0)))

(module+ test
  (define on  (features '16 #t #t #t #f #f))   ; mouse?/paste?/alt-screen? 全开
  (define off (features '16 #f #f #f #f #f))

  ;; 启用顺序 = 声明顺序；禁用 = 逆序
  (define p1 (make-test-plan))
  (reset!) (plan-enable! p1 on) (plan-disable! p1)
  (check-equal? (reverse (unbox log))
                '(e-alt e-mouse e-paste d-paste d-mouse d-alt)
                "顺序：alt→mouse→paste，逆序禁用")

  ;; skip（no-buffer 不切 alt）
  (define p2 (make-test-plan))
  (reset!) (plan-enable! p2 on #:skip '(alt)) (plan-disable! p2)
  (check-equal? (reverse (unbox log)) '(e-mouse e-paste d-paste d-mouse) "skip alt")

  ;; 引用计数：嵌套时只真正 enable/disable 一次
  (define p3 (make-test-plan))
  (reset!)
  (plan-enable! p3 on)     ; 0→1：enable
  (plan-enable! p3 on)     ; 1→2：无
  (plan-disable! p3)       ; 2→1：无
  (plan-disable! p3)       ; 1→0：disable
  (check-equal? (reverse (unbox log))
                '(e-alt e-mouse e-paste d-paste d-mouse d-alt)
                "引用计数：嵌套不重复开关")

  ;; 不适用则完全不动
  (define p4 (make-test-plan))
  (reset!) (plan-enable! p4 off) (plan-disable! p4)
  (check-equal? (unbox log) '() "无适用项 → 无动作")

  ;; disable 抛错不阻断后续；on-error 收到失败项
  (define errors (box '()))
  (define p5
    (list (faction 'a (λ (f) #t) (λ () (rec! 'e-a)) (λ () (error 'boom)) 0)
          (faction 'b (λ (f) #t) (λ () (rec! 'e-b)) (λ () (rec! 'd-b)) 0)))
  (reset!)
  (plan-enable! p5 on)
  (plan-disable! p5 #:on-error (λ (a e) (set-box! errors (cons (faction-label a) (unbox errors)))))
  (check-equal? (reverse (unbox log)) '(e-a e-b d-b) "a 禁用失败仍继续 b")
  (check-equal? (unbox errors) '(a) "on-error 收到失败项"))
