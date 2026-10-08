#lang racket

;; ════════════════════════════════════════════════════════════════
;; tests/base-probe-test.rkt
;;
;; probe-caps 用内存端口喂假回复，验证：
;;   · 组合三步后得到 caps，features 正确
;;   · 确实发出了 standard profile 的模式查询
;;   · env 流进 caps
;;   · 端口异常 → 降级 #f；无回复 → 保守 caps
;;   raco test tests/base-probe-test.rkt
;; ════════════════════════════════════════════════════════════════

(require rackunit
         racket/port
         racket/string
         "../base/terminal/probe.rkt"
         "../base/terminal/features.rkt"
         "../terminal-support/main.rkt")

(define E (string (integer->char 27)))
(define (j . xs) (apply string-append xs))
(define (silent e) #f)

;; 跑一次探测，返回 (values caps out-bytes)
(define (run replies #:env [env (hash)])
  (define out (open-output-bytes))
  (define c (probe-caps #:in (open-input-bytes (string->bytes/latin-1 replies))
                        #:out out
                        #:env env
                        #:timeout 0.02 #:idle 0.005
                        #:on-error silent))
  (values c (get-output-bytes out)))

(module+ test

  (define replies
    (j E "[?1000;1$y" E "[?1002;1$y" E "[?1006;1$y"
       E "[?2004;1$y" E "[?1049;1$y" E "[?2026;1$y"
       E "[?0u" E "[>0;276;0c" E "[?1;2c"))

  (define-values (c out) (run replies))
  (check-true (caps? c) "探测得到 caps")
  (define f (features-of c))
  (check-true (features-mouse? f) "mouse 开")
  (check-true (features-paste? f) "paste 开")
  (check-true (features-alt-screen? f) "alt-screen 开")
  (check-true (features-kitty-keys? f) "kitty 开")
  (check-true (features-sync? f) "sync 开")
  (check-equal? (features-color f) '16 "无颜色来源 → 16")

  ;; standard profile 应真的发出这些 DECRQM
  (for ([mode '("1006" "1049" "2004" "2026")])
    (check-true (string-contains? (bytes->string/latin-1 out)
                                  (j E "[?" mode "$p"))
                (format "probe 发出 DECRQM ~a" mode)))

  ;; env 流进 caps（无 XTGETTCAP 时靠 COLORTERM）
  (define-values (c2 ignored2) (run (j E "[?1;2c") #:env (hash "COLORTERM" "truecolor")))
  (check-equal? (features-color (features-of c2)) 'truecolor "env COLORTERM → truecolor")

  ;; 端口异常 → 降级 #f
  (check-false (probe-caps #:in 'not-a-port #:out (open-output-nowhere)
                           #:timeout 0.02 #:idle 0.005
                           #:on-error silent)
               "端口异常 → #f")

  ;; 无回复 → 仍返回 caps，features 保守
  (define-values (c3 ignored3) (run ""))
  (check-true (caps? c3) "无回复仍是 caps")
  (check-equal? (features-of c3) default-features "无回复 → 保守默认"))
