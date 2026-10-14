#lang racket

;; ════════════════════════════════════════════════════════════════
;; base/terminal/session.rkt —— 会话级能力状态
;;
;; features 是"当前这次会话已确认的能力"。tui-init 探测后写入，
;; tui-exit 恢复成进入前的值（支持嵌套 with-tui，LIFO）。
;;
;; 用 parameter 而不是全局变量：可被 parameterize 覆盖，测试友好。
;; 注意：base 是单线程 TUI；多线程并发会话不受支持（同 base 的其余状态）。
;; ════════════════════════════════════════════════════════════════

(require "features.rkt")

(provide current-features)

(define current-features (make-parameter default-features))
