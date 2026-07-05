#lang racket
;; layout + border 测试

(require "../ui/main.rkt"
         "../base/io/output-color.rkt"
         "../base/terminal/resize.rkt")

;; 灰底调试样式
(style-define! 'bg-a (color256-bg 237) (color256-fg 255))
(style-define! 'bg-b (color256-bg 238) (color256-fg 255))
(style-define! 'bg-c (color256-bg 239) (color256-fg 255))
(style-define! 'bg-d (color256-bg 240) (color256-fg 255))

(define t-title  (make-text #:text " Title " #:style 'bg-a))
(define t-left   (make-text #:text " Left "  #:style 'bg-b))
(define t-right  (make-text #:text " Right " #:style 'bg-c))
(define t-foot   (make-text #:text " Footer - q to quit " #:style 'bg-d))

;; 打印终端尺寸和每个 spec 的坐标
(let-values ([(h w) (get-window-size)])
  (printf "terminal: ~a rows x ~a cols\n" h w))

(define specs
  (screen
   (t-title 1)
   ((h
     ((border (v (t-left 1)) #:title "Files")  1)
     (space 1)
     ((border (v (t-right 1)) #:title "Editor") 1)) 6)
   (t-foot 1)))

(printf "specs count: ~a\n" (length specs))
(for ([s specs])
  (printf "  x=~a y=~a w=~a h=~a\n" (second s) (third s) (fourth s) (fifth s)))

(run-app-noblock specs)
