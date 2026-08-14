#lang racket

;; ui-rebuild/main.rkt — 声明式 UI 核心入口

(require "surface.rkt"
         "widget.rkt"
         "layout.rkt"
         "render.rkt"
         "ascii-dump.rkt"
         "widgets/text.rkt"
         "widgets/button.rkt"
         "widgets/bool-button.rkt"
         "widgets/input.rkt"
         "widgets/scrollbar.rkt"
         "widgets/list.rkt"
         "widgets/output.rkt"
         "widgets/text-area.rkt"
         "run.rkt")

(provide (all-from-out "surface.rkt")
         (all-from-out "widget.rkt")
         (all-from-out "layout.rkt")
         (all-from-out "render.rkt")
         (all-from-out "ascii-dump.rkt")
         (all-from-out "widgets/text.rkt")
         (all-from-out "widgets/button.rkt")
         (all-from-out "widgets/bool-button.rkt")
         (all-from-out "widgets/input.rkt")
         (all-from-out "widgets/scrollbar.rkt")
         (all-from-out "widgets/list.rkt")
         (all-from-out "widgets/output.rkt")
         (all-from-out "widgets/text-area.rkt")
         (all-from-out "run.rkt"))
