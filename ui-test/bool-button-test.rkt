#lang racket
;; bool-button 测试

(require "../ui/main.rkt"
         "../base/io/output-color.rkt")

(style-define! 'bg (color256-bg 235) (color256-fg 255))

(define t-title (make-text #:text " Bool-Button Test " #:style 'heading))
(define t-info  (make-text #:text " click or press Enter/Space to toggle " #:style 'dim))
(define t-foot  (make-text #:text " q to quit " #:style 'dim))

(define-values (out api) (make-output #:style 'bg))
(append api "toggle log:\n")

(define (log label v)
  (append api (format "[~a] ~a\n" (if v "x" " ") label)))

(define b1 (make-bool-button #:label "Option A"
                             #:on-change (λ (v) (log "Option A" v))))
(define b2 (make-bool-button #:label "Option B"
                             #:initial? #t
                             #:on-change (λ (v) (log "Option B" v))))
(define b3 (make-bool-button #:label "Option C"
                             #:on-style 'error
                             #:off-style 'warning
                             #:on-change (λ (v) (log "Option C" v))))

(run-app-noblock
  (screen
   (t-title 1)
   (t-info  1)
   (b1 1)
   (b2 1)
   (b3 1)
   (out 4)
   (t-foot 1)))
