#lang racket
;; 全组件集成测试: text + input + output + border + layout

(require "../ui/main.rkt"
         "../base/io/output-color.rkt")

;; ── 样式 ──
(style-define! 'bg-title  (color256-bg 237) (color256-fg 255))
(style-define! 'bg-panel  (color256-bg 235) (color256-fg 250))
(style-define! 'bg-status (color256-bg 240) (color256-fg 255))

;; ── 组件 ──
(define t-title  (make-text #:text " Demo App " #:style 'bg-title))

;; 输出面板
(define-values (out-log log-api) (make-output #:style 'bg-panel))
(define-values (out-files files-api) (make-output #:style 'bg-panel))
(append log-api "ready.\n")

;; 文件列表
(define file-panel
  (border (layout-row (out-files 1)) #:title "Files"))

;; 日志面板
(define log-panel
  (border (layout-row (out-log 1)) #:title "Log"))

;; 输入 + 状态
(define input-field (make-input #:placeholder "type command..."))
(define t-status  (make-text #:text " status " #:style 'bg-status))

;; ── 布局 ──
(run-app-noblock
  (screen
   (t-title 1)
   ((layout-col
     (file-panel 1)
     (space 1)
     (log-panel 1)) 6)
   (input-field 1)
   (t-status 1)))
