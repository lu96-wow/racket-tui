#lang racket

(require "../ui/main.rkt"
         "../base/io/output-color.rkt")

(style-define! 'panel-dim (color256-bg 234) (color256-fg 250))
(style-define! 'panel-blue (color256-bg 17) (color256-fg 231))
(style-define! 'input-style (color256-bg 236) (color256-fg 255))
(style-define! 'error-style (color256-bg 88) (color256-fg 231) attr-bold)
(style-define! 'ok-style (color256-bg 22) (color256-fg 231) attr-bold)

(define-values (out1 append1! _as1 _c1 _f1 _bf1 _ef1 _tf1 _s1)
  (make-output #:max-lines 100 #:style 'panel-dim))
(define-values (out2 append2! append2-styled! _c2 _f2 _bf2 _ef2 _tf2 _s2)
  (make-output #:max-lines 100 #:style 'panel-blue))

(define inp (make-input #:style 'input-style
                        #:nofocus-style 'panel-dim
                        #:placeholder "type here..."
                        #:on-submit (λ (txt) (append1! (format "→ ~a\n" txt)))))

(define (stream append! str #:delay [d 0.005])
  (for ([ch (in-string str)])
    (append! (string ch))
    (sleep d)))

(thread
  (λ ()
    (sleep 0.3)
    (stream append1! "Panel 1 (gray #234)\n")
    (for ([i (in-range 1 12)])
      (stream append1! (format "  log ~a: ok\n" i) #:delay 0.003))
    (sleep 0.3)
    (stream append2! "Panel 2 (blue #17)\n")
    (for ([i (in-range 1 20)])
      (stream append2! (format "  event ~a: pending\n" i) #:delay 0.002))
    (sleep 0.5)
    (stream append1! "─── done ───\n")
    (stream append2! "─── done ───\n")
    ;; styled 输出
    (sleep 0.3)
    (append2-styled! "[ERROR] connection refused\n" 'error-style)
    (append2-styled! "[OK]    retrying in 3s...\n" 'ok-style)
    ;; 折叠块
    (sleep 0.3)
    (_bf2 "Errors (click to toggle)" 'error-style)
    (for ([i (in-range 1 6)])
      (append2-styled! (format "error ~a: something went wrong\n" i) 'panel-blue))
    (_ef2)))

(run-app-noblock
  (out1 1 1 40 12)
  (out2 43 1 36 12)
  (inp 1 14 30 2))
