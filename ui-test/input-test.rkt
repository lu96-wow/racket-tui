#lang racket

(require "../ui/main.rkt")

(define submitted (box "(none)"))

(define name-input
  (make-input #:placeholder "Enter your name..."
              #:on-submit (λ (t) (set-box! submitted t))
              #:on-change void))

(define submit-btn
  (make-button #:text "Submit"
               #:on-activate (λ () (set-box! submitted "button clicked!"))))

(define specs
  (list (list (make-text #:text "┌────┤ Input Widget Test ├────┐" #:style 'title)
              1 1 36 1)
        (list (make-text #:text "│ Type in the input field       │" #:style 'info)
              1 2 36 1)
        (list (make-text #:text "│ Enter = submit, Esc = clear   │" #:style 'info)
              1 3 36 1)
        (list (make-text #:text (λ () (format "│ Last submit: ~a~a"
                                              (unbox submitted)
                                              (make-string (max 0 (- 26 (string-length (unbox submitted))))
                                                           #\space)))
                         #:style 'info)
              1 4 36 1)
        (list (make-text #:text "│ Press q to quit               │" #:style 'info)
              1 5 36 1)
        (list (make-text #:text "└──────────────────────────────┘" #:style 'title)
              1 6 36 1)
        (list name-input 2 8 20 2)
        (list submit-btn 2 10 0 0)))

(run-app specs)
