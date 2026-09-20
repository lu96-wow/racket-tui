#lang racket

;; char 后端总入口。
;;
;; 关键：这里 provide 一个自己的 bytes-append（= ops-append）。
;; 由于 Racket 允许显式 require 覆盖 `#lang` 的初始导入，用户
;;   (require tui/char)
;; 之后，本模块内的 bytes-append 会顶掉 racket 自带的那个，
;; 于是 README 里的批量写法可以原样工作，无需任何解析。

(require "tui.rkt"
         "terminal/base.rkt"
         "terminal/resize.rkt"
         "terminal/cursor-state.rkt"
         "terminal/config.rkt"
         "ansi/ansi-var.rkt"
         "ansi/ansi-format.rkt"
         "ansi/input-var.rkt"
         "io/event.rkt"
         "io/build-input.rkt"
         "io/output.rkt"
         "io/output-color.rkt"
         "io/output-styles.rkt"
         "screen/ops.rkt"
         "screen/session.rkt"
         "screen/grid.rkt"
         "screen/render.rkt"
         "screen/frame.rkt"
         "screen/ansi-parse.rkt"
         "run.rkt")

;; 覆盖 racket 的 bytes-append：把 parts（op / op-seq / bytes / string）拼成 op-seq
(define (bytes-append . parts)
  (apply ops-append parts))

(provide bytes-append
         (all-from-out "tui.rkt")
         (all-from-out "terminal/base.rkt")
         (all-from-out "terminal/resize.rkt")
         (all-from-out "terminal/cursor-state.rkt")
         (all-from-out "terminal/config.rkt")
         (all-from-out "ansi/ansi-var.rkt")
         (all-from-out "ansi/ansi-format.rkt")
         (all-from-out "ansi/input-var.rkt")
         (all-from-out "io/event.rkt")
         (all-from-out "io/build-input.rkt")
         (all-from-out "io/output.rkt")
         (all-from-out "io/output-color.rkt")
         (all-from-out "io/output-styles.rkt")
         (all-from-out "screen/ops.rkt")
         (all-from-out "screen/session.rkt")
         (all-from-out "screen/grid.rkt")
         (all-from-out "screen/render.rkt")
         (all-from-out "screen/frame.rkt")
         (all-from-out "screen/ansi-parse.rkt")
         (all-from-out "run.rkt"))
