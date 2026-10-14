#lang racket

;; char 后端复用 base 的 features 纯数据模块（无 FFI / 无终端探测）。
;;
;; 这样 (features? / features-color / features-mouse? ... / default-features)
;; 在两个后端同名可用，用户代码可原样切换；char 不提供 probe-caps（那是
;; 终端查询，属于 base 专有），default-features 即「全部不支持」的保守值。

(require "../../base/terminal/features.rkt")

(provide (all-from-out "../../base/terminal/features.rkt"))
