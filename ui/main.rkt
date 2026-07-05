#lang racket
;; ui/main.rkt — ui 层入口，聚合所有 ui 模块

(require "component.rkt"
         "run.rkt"
         "layout.rkt"
         "widgets/input.rkt"
         "widgets/button.rkt"
         "widgets/text.rkt"
         "widgets/output.rkt"
         "widgets/border.rkt")

(provide (all-from-out "component.rkt")
         (all-from-out "run.rkt")
         (all-from-out "layout.rkt")
         (all-from-out "widgets/input.rkt")
         (all-from-out "widgets/button.rkt")
         (all-from-out "widgets/text.rkt")
         (all-from-out "widgets/output.rkt")
         (all-from-out "widgets/border.rkt"))
