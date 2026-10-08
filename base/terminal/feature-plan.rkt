#lang racket

;; ════════════════════════════════════════════════════════════════
;; base/terminal/feature-plan.rkt —— 统一的「能力 → 启用/禁用」控制表
;;
;; 每条 faction 声明一个能力的启用/禁用动作：
;;   · 声明顺序 = 启用顺序；退出按 reverse 逆序
;;   · 启用/禁用成对，不会漏掉 disable
;;   · active 是引用计数：嵌套 with-tui 下内层退出不误关外层
;;   · `#:skip` 让 no-buffer 变体跳过 alt
;;
;; 纯控制逻辑，不依赖具体终端动作 → 可用假动作单独测试。
;; ════════════════════════════════════════════════════════════════

(require "features.rkt")

(provide (struct-out faction)
         plan-enable! plan-disable!)

;; 一条规则：
;;   label       : symbol，用于 #:skip 与日志
;;   applicable? : (-> features boolean?)
;;   enable      : (-> void)
;;   disable     : (-> void)
;;   active      : 引用计数（0 = 未启用）
(struct faction (label applicable? enable disable [active #:mutable]) #:transparent)

;; 按声明顺序启用所有 applicable 且未被 skip 的项；只有 0→1 才真正调用 enable。
(define (plan-enable! plan f #:skip [skip '()])
  (for ([a (in-list plan)])
    (when (and ((faction-applicable? a) f)
               (not (memq (faction-label a) skip)))
      (when (zero? (faction-active a))
        ((faction-enable a)))
      (set-faction-active! a (add1 (faction-active a))))))

;; 逆序禁用；只有 1→0 才真正调用 disable。
;; on-error 默认重抛；tui-exit 传入"记录并继续"，保证某一步失败不中断其余清理。
(define (plan-disable! plan #:on-error [on-error (λ (a e) (raise e))])
  (for ([a (in-list (reverse plan))])
    (when (positive? (faction-active a))
      (define n (sub1 (faction-active a)))
      (set-faction-active! a n)
      (when (zero? n)
        (with-handlers ([exn? (λ (e) (on-error a e))])
          ((faction-disable a)))))))
