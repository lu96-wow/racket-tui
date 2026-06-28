#lang racket

(require "../main.rkt"
         "../ui/widgets/panel.rkt")

(define px (box 5))
(define py (box 2))
(define pw (box 12))
(define ph (box 3))
(define panel (make-panel px py pw ph #:color 'selection))

(run-app (list (list panel px py pw ph)))

(printf "quit~n")
