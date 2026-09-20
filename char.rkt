#lang racket

;; 字符图后端入口：与 (require tui) 同 API，但输出为纯字符网格。
;;
;;   (require tui)        ; 真实终端
;;   (require tui/char)   ; 字符图（适合 AI 调试 / 测试 / 无 tty 环境）

(require "base-char/main.rkt")
(provide (all-from-out "base-char/main.rkt"))
