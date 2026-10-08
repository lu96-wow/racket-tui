#lang racket

;; ════════════════════════════════════════════════════════════════
;; terminal-support/run.rkt —— 按表查询
;;
;; 执行一张表（listof query）：把全部 request 一次性写出，读回整段，
;; 再对每项用它的 parse 从原始回复里取值。不做任何决策。
;;
;; 结果容器：id -> value 的 hash。**id 必须唯一**；重复 id 直接报错，
;; 而不是静默覆盖（覆盖会丢掉一整条结果，难以察觉）。
;; ════════════════════════════════════════════════════════════════

(require racket/list
         "query.rkt"
         "io.rkt")

(provide run-queries run-queries/raw check-query-ids)

;; 表里 id 必须唯一；有重复则报错（返回 ids）
(define (check-query-ids queries)
  (define ids (for/list ([q (in-list queries)]) (query-id q)))
  (define dup (check-duplicates ids))
  (when dup
    (error 'run-queries
           "duplicate query id: ~a（表的 id 必须唯一；同一查询不要放两次）" dup))
  ids)

;; → (values raw-bytes result-hash)   result-hash : id -> value
(define (run-queries/raw queries #:timeout [timeout 0.30] #:idle [idle 0.05] #:done? [done? #f])
  (check-query-ids queries)
  (define raw (exchange-queries (for/list ([q (in-list queries)]) (query-request q))
                                #:timeout timeout #:idle idle #:done? done?))
  (values raw
          (for/hash ([q (in-list queries)])
            (values (query-id q) ((query-parse q) raw)))))

;; → result-hash
(define (run-queries queries #:timeout [timeout 0.30] #:idle [idle 0.05] #:done? [done? #f])
  (call-with-values
   (λ () (run-queries/raw queries #:timeout timeout #:idle idle #:done? done?))
   (λ (_raw res) res)))
