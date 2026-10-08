#lang racket

;; ════════════════════════════════════════════════════════════════
;; base/terminal/probe.rkt —— 能力探测适配器
;;
;; 把 terminal-support 的三步组合成 base 需要的一个调用：
;;   ① 定查哪些   group->queries / profile->queries
;;   ② 调 api 查   run-queries/raw（显式端口）
;;   ③ 建能力表    assemble-caps #:env
;;
;; 契约：
;;   · **必须在 enter-raw-mode! 之后调用**（否则回显 + 行缓冲会污染回复）。
;;   · 端口、env 都显式传入；默认 env = (env-snapshot)，不读 $TERM 猜测。
;;   · 探测异常 → 返回 #f（降级），由 features-of 落到保守默认；
;;     无回复不算异常，会得到一份"全 unknown"的 caps，同样保守。
;; ════════════════════════════════════════════════════════════════

(require "../../terminal-support/main.rkt")

(provide probe-caps)

(define (default-on-error e)
  (eprintf "terminal probe failed (degrading to conservative defaults): ~a\n"
           (exn-message e))
  #f)

;; → caps 或 #f
(define (probe-caps
        #:in [in (current-input-port)]
        #:out [out (current-output-port)]
        #:profile [profile default-profile]
        #:env [env (env-snapshot)]
        #:timeout [timeout 0.30]
        #:idle [idle 0.05]
        #:on-error [on-error default-on-error])
  (with-handlers ([exn? on-error])
    (define queries (profile->queries profile))
    (define-values (raw results)
      (run-queries/raw queries
                       #:in in #:out out
                       #:timeout timeout #:idle idle))
    (assemble-caps results raw #:env env)))
