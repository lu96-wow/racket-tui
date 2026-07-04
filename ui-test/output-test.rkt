#lang racket

(require "../ui/main.rkt"
         "../base/io/output-color.rkt")

(style-define! 'panel-dim  (color256-bg 234) (color256-fg 250))
(style-define! 'panel-blue (color256-bg  17) (color256-fg 231))
(style-define! 'input-style (color256-bg 236) (color256-fg 255))

(define-values (out1 append1! _c1 _f1 _s1)
  (make-output #:max-lines 100 #:style 'panel-dim))
(define-values (out2 append2! _c2 _f2 _s2)
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
   (stream append2! "─── done ───\n")))

(run-app-noblock
 (out1 0  0  40 12)
 (out2 42 0  36 12)
 (inp  0  13 30 2))
