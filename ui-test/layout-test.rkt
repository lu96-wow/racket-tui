#lang racket
;; 全组件集成测试

(require "../ui/main.rkt"
         "../base/io/output-color.rkt")

(style-define! 'bg-title (color256-bg 237) (color256-fg 255))
(style-define! 'bg-panel (color256-bg 235) (color256-fg 250))
(style-define! 'bg-status (color256-bg 240) (color256-fg 255))

(define t-title (make-text #:text " Demo App " #:style 'bg-title))
(define t-status (make-text #:text " status " #:style 'bg-status))

;; 输出面板
(define-values (out-log log-api) (make-output #:style 'bg-panel))
(define-values (out-files files-api) (make-output #:style 'bg-panel))
(append log-api "ready.\n")

(define file-panel (border (layout-row (out-files 1)) #:title "Files"))
(define log-panel (border (layout-row (out-log 1)) #:title "Log"))

;; 输入 + toggle
(define input-field (make-input #:placeholder "type command..."
                                #:on-submit (λ (text)
                                              (append-styled log-api
                                                             (format "> ~a\n" text) 'info))))

(define bool-auto (make-bool-button #:label "auto-scroll"
                                    #:initial? #t
                                    #:on-change (λ (v)
                                                  (if v (scroll-end log-api) (void)))))

(run-app-noblock
  (screen
    (t-title 1)
    ((layout-col
       (file-panel 1)
       (space 1)
       (log-panel 1)) 6)
    ((layout-col (input-field 1) (bool-auto 1)) 1)
    (t-status 1)))
