#lang racket
;; layout + border 测试

(require "../ui/main.rkt"
         "../base/io/output-color.rkt")

(style-define! 'bg-a (color256-bg 237) (color256-fg 255))
(style-define! 'bg-b (color256-bg 238) (color256-fg 255))
(style-define! 'bg-c (color256-bg 239) (color256-fg 255))
(style-define! 'bg-d (color256-bg 240) (color256-fg 255))

(define t-title (make-text #:text " Title " #:style 'bg-a))
(define t-left  (make-text #:text " Left " #:style 'bg-b))
(define t-right (make-text #:text " Right " #:style 'bg-c))
(define t-foot  (make-text #:text " Footer - q to quit " #:style 'bg-d))

(run-app-noblock
  (screen
   (t-title 1)
   ((h
     ((border (v (t-left 1)) #:title "Files") 1)
     (space 1)
     ((border (v (t-right 1)) #:title "Editor") 1)) 6)
   (t-foot 1)))
