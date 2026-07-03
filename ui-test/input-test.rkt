#lang racket

(require "../ui/main.rkt"
         "../base/io/output-color.rkt")

;; ── 256 色深灰背景 (fg=255 白字, bg=238 深灰底) ──
(style-define! 'panel-title  (color256-fg 255) (color256-bg 238) attr-bold)
(style-define! 'panel-info   (color256-fg 255) (color256-bg 238))
(style-define! 'panel-input  (color256-fg 255) (color256-bg 238))
(style-define! 'panel-focus  (color256-fg 255) (color256-bg 238) attr-bold)
(style-define! 'cursor       (color256-fg 238) (color256-bg 255))

(define submitted (box "(none)"))

(define name-input
  (make-input #:placeholder "Enter text..."
              #:initial-text "line one: hello world\nline two: 你好世界\nline three: 中文测试"
              #:style 'panel-input
              #:focus-style 'panel-focus
              #:on-submit (λ (t) (set-box! submitted t))
              #:on-change void))

(define submit-btn
  (make-button #:text "Submit"
               #:on-activate (λ () (set-box! submitted "button clicked!"))))

(define specs
  (list (list (make-text #:text "┌────┤ Multi-line Input Test ├──┐" #:style 'panel-title)
              1 1 36 1)
        (list (make-text #:text "│ ESC=newline, Enter = submit    │" #:style 'panel-info)
              1 2 36 1)
        (list (make-text #:text "│ Up/Down/Left/Right = move     │" #:style 'panel-info)
              1 3 36 1)
        (list (make-text #:text (λ () (let ([t (regexp-replace* #rx"\n" (unbox submitted) "↵")])
                                        (define max-len (- 22 (string-length t)))
                                        (format "│ Submit: ~a~a" t
                                                (make-string (max 0 max-len) #\space))))
                         #:style 'panel-info)
              1 4 50 1)
        (list (make-text #:text "│ Press q to quit               │" #:style 'panel-info)
              1 5 36 1)
        (list (make-text #:text "└──────────────────────────────┘" #:style 'panel-title)
              1 6 36 1)
        (list name-input 2 8 30 3)
        (list submit-btn 2 12 0 0)))

(run-app specs)
