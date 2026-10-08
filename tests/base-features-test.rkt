#lang racket

;; ════════════════════════════════════════════════════════════════
;; tests/base-features-test.rkt
;;
;; features-of 是纯函数：直接构造 caps（绕过 I/O）做穷举断言。
;;   raco test tests/base-features-test.rkt
;; ════════════════════════════════════════════════════════════════

(require rackunit
         "../base/terminal/features.rkt"
         "../terminal-support/main.rkt")

;; 构造一个 caps；modes 里给的私有模式 Pm=1（可用）。
(define (mk-caps #:private [private '()]
                 #:xtgettcap [tc '()]
                 #:kitty-flags [kitty-flags #f]
                 #:env [env (hash)])
  (define results (make-hash))
  (for ([m (in-list private)])
    (hash-set! results (cons 'decrqm-private m) 1))
  (when kitty-flags
    (hash-set! results 'kitty-flags kitty-flags))
  (when (pair? tc)
    (hash-set! results 'xtgettcap tc))
  (assemble-caps results #"" #:env env))

(module+ test

  ;; ── 保守默认 ──
  (define f0 (features-of (mk-caps)))
  (check-equal? (features-color f0) '16 "无来源 → 16")
  (check-false (features-mouse? f0) "默认无鼠标")
  (check-false (features-paste? f0) "默认无括号粘贴")
  (check-false (features-alt-screen? f0) "默认无备用屏")
  (check-false (features-kitty-keys? f0) "默认无 kitty 键盘")
  (check-false (features-sync? f0) "默认无同步输出")
  (check-equal? (features-of #f) default-features "无 caps → 保守默认")

  ;; ── 全开 ──
  (define fall
    (features-of (mk-caps #:private '(1000 1002 1006 2004 1049 2026)
                          #:kitty-flags 0)))
  (check-true (features-mouse? fall) "1006+1000 → 鼠标可用")
  (check-true (features-paste? fall) "2004 → 括号粘贴")
  (check-true (features-alt-screen? fall) "1049 → 备用屏")
  (check-true (features-kitty-keys? fall) "kitty flags=0 仍算支持")
  (check-true (features-sync? fall) "2026 → 同步输出")

  ;; ── 鼠标必须同时有 SGR(1006) ──
  (check-false (features-mouse? (features-of (mk-caps #:private '(1000 1002)))) "只有跟踪、无 1006 → 鼠标关")
  (check-true (features-mouse? (features-of (mk-caps #:private '(1006 1002)))) "1006+1002 → 鼠标开")

  ;; ── 色深 ──
  (check-equal? (features-color
                 (features-of (mk-caps #:xtgettcap (list (list "RGB" #t #f)))))
                'truecolor "XTGETTCAP RGB → truecolor")
  (check-equal? (features-color
                 (features-of (mk-caps #:xtgettcap (list (list "Co" #t "256")))))
                '256 "Co=256 → 256")
  (check-equal? (features-color
                 (features-of (mk-caps #:env (hash "COLORTERM" "truecolor"))))
                'truecolor "COLORTERM → truecolor")
  (check-equal? (features-color
                 (features-of (mk-caps #:env (hash "TERM" "xterm-256color"))))
                '256 "TERM=256color → 256")

  ;; ── 永久置位/复位也算「可用」；永久复位不可用 ──
  (define results (make-hash))
  (hash-set! results (cons 'decrqm-private 1049) 3)   ; permanently set
  (hash-set! results (cons 'decrqm-private 2004) 4)   ; permanently reset
  (define f-perm (features-of (assemble-caps results #"")))
  (check-true (features-alt-screen? f-perm) "Pm=3 永久置位 → 可用")
  (check-false (features-paste? f-perm) "Pm=4 永久复位 → 不可用"))
