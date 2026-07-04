#lang racket

(require "../ui/main.rkt"
         "../base/io/output-color.rkt")

;; ── 256 色深灰背景 (自动回退 16 色白字黑底) ──
(define fg-panel  (color-fg* 255 7))
(define bg-panel  (color-bg* 238 0))
(define fg-cursor (color-fg* 238 0))
(define bg-cursor (color-bg* 255 7))

(style-define! 'panel-title  fg-panel bg-panel attr-bold)
(style-define! 'panel-info   fg-panel bg-panel)
(style-define! 'panel-input  fg-panel bg-panel)
(style-define! 'panel-focus  fg-panel bg-panel attr-bold)
(style-define! 'cursor       fg-cursor bg-cursor)

(define submitted (box "(none)"))

(define name-input
  (make-input #:placeholder "Enter text..."
              #:initial-text "line one: hello world\nline two: 你好世界\nline three: 中文测试"
              #:style 'panel-focus
              #:nofocus-style 'panel-input
              #:on-submit (λ (t) (set-box! submitted t))
              #:on-change void))

(define submit-btn
  (make-button #:text "Submit"
               #:on-activate (λ () (set-box! submitted "button clicked!"))))

(define specs
  (list (list (make-text #:text "┌────┤ Multi-line Input Test ├──┐" #:style 'panel-title)
              0 0 36 1)
        (list (make-text #:text "│ ESC=newline, Enter = submit    │" #:style 'panel-info)
              0 1 36 1)
        (list (make-text #:text "│ Up/Down/Left/Right = move     │" #:style 'panel-info)
              0 2 36 1)
        (list (make-text #:text (λ () (let ([t (regexp-replace* #rx"\n" (unbox submitted) "↵")])
                                        (define max-len (- 22 (string-length t)))
                                        (format "│ Submit: ~a~a" t
                                                (make-string (max 0 max-len) #\space))))
                         #:style 'panel-info)
              0 3 50 1)
        (list (make-text #:text "│ Press q to quit               │" #:style 'panel-info)
              0 4 36 1)
        (list (make-text #:text "└──────────────────────────────┘" #:style 'panel-title)
              0 5 36 1)
        (list name-input 1 7 30 3)
        (list submit-btn 1 11 0 0)))

(run-app specs)
