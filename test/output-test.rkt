#lang racket

(require "../ui/main.rkt"
         "../base/io/output-color.rkt")

;; 强制 256 色模式
(use-256color!)

;; 256 色样式
;; 灰度: 232(黑) ~ 255(白)
;; RGB方块: 16~231 (6×6×6)
(style-define! 'panel-dim  (color256-bg 234) (color256-fg 250))  ; 深灰底
(style-define! 'panel-blue (color256-bg  17) (color256-fg 231))  ; 深蓝底

;; 两个输出面板
(define-values (out1 append1! clear1! __1 __2)
  (make-output #:max-lines 100 #:style 'panel-dim))
(define-values (out2 append2! clear2! __3 __4)
  (make-output #:max-lines 100 #:style 'panel-blue))

(define (stream append! str #:delay [d 0.008])
  (for ([ch (in-string str)])
    (append! (string ch))
    (sleep d)))

(thread
 (λ ()
   (sleep 0.3)
   (stream append1! "Panel 1 (dark gray, 256c #236)\n")
   (stream append1! "═══════════════════════╗\n")
   (for ([i (in-range 1 10)])
     (stream append1! (format "  log ~a: ok\n" i) #:delay 0.003))
   (sleep 0.5)
   (stream append2! "Panel 2 (deep blue, 256c #17)\n")
   (stream append2! "═══════════════════════╗\n")
   (for ([i (in-range 1 15)])
     (stream append2! (format "  event ~a: pending\n" i) #:delay 0.002))
   (sleep 1)
   (clear1!)
   (clear2!)
   (stream append1! "[done] ↑↓ scroll, q quit\n")
   (stream append2! "[done]\n")))

;; 布局: panel1 占左上, panel2 占右下
(run-app-nobuffer
 (list (list out1 0  0  20 10)
       (list out2 22 0  20 10))
 #:noblock? #t)
