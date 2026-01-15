#lang racket

(require "lib_help.rkt")

;; 辅助函数：组合颜色对与属性
;; 例如：(color-attr 1 A_BOLD) 表示“使用颜色对1 + 粗体”
(define (color-attr pair-id . attrs)
  (apply bitwise-ior (help_COLOR_PAIR pair-id) attrs))

;;将任意多个 ncurses 属性（如 A_BOLD、A_REVERSE、A_UNDERLINE 等）
;;通过按位或（bitwise OR）组合成一个单一的属性值
(define (combined_attribute . attribute_list)
  (apply bitwise-ior attribute_list))

(provide (all-defined-out))