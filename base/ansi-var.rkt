#lang racket

;; ════════════════════════════════════════════════════════════════
;; 可变的 ANSI 运行时变量（box 化，可在运行时切换）
;; ════════════════════════════════════════════════════════════════

;; 换行序列
;; 默认 "\n"：普通（非 raw）模式下终端 ONLCR 会自动把 \n 转成 \r\n
;; 进入 raw 模式后由 tui.rkt 的 init-newline-var 设为 "\r\n"
;; （raw 模式关闭了 OPOST/ONLCR，需手动回车）
(define newline-var (box "\n"))

(provide newline-var)
