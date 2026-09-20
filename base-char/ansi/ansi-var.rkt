#lang racket

;; 复用 base 的 ANSI 常量 / 可变运行时变量（纯数据，无副作用）

(require "../../base/ansi/ansi-var.rkt")
(provide (all-from-out "../../base/ansi/ansi-var.rkt"))
