#lang racket

(require "../ui/main.rkt"
         "../base/io/output-color.rkt")

(style-define! 'panel-dim (color256-bg 234) (color256-fg 250))
(style-define! 'panel-blue (color256-bg 17) (color256-fg 231))
(style-define! 'input-style (color256-bg 236) (color256-fg 255))
(style-define! 'error-style (color256-bg 88) (color256-fg 231) attr-bold)
(style-define! 'ok-style (color256-bg 22) (color256-fg 231) attr-bold)

(define-values (out1 api1) (make-output #:max-lines 100 #:style 'panel-dim))
(define-values (out2 api2) (make-output #:max-lines 100 #:style 'panel-blue))

(define inp (make-input #:style 'input-style
                        #:nofocus-style 'panel-dim
                        #:placeholder "type here..."
                        #:on-submit (λ (txt) (for ([ch (in-string (format "→ ~a\n" txt))])
                                               (append api1 (string ch))))))

(define (type api str #:delay [d 0.04])
  (for ([ch (in-string str)])
    (append api (string ch))
    (sleep d)))

(define (type-styled api str style #:delay [d 0.04])
  (for ([ch (in-string str)])
    (append-styled api (string ch) style)
    (sleep d)))

(thread
  (λ ()
    (sleep 0.3)
    (type api1 "Panel 1 (gray #234)\n")
    (for ([i (in-range 1 12)])
      (type api1 (format "  log ~a: ok\n" i)))
    (sleep 0.3)
    (type api2 "Panel 2 (blue #17)\n")
    (for ([i (in-range 1 20)])
      (type api2 (format "  event ~a: pending\n" i)))
    (sleep 0.5)
    (type api1 "─── done ───\n")
    (type api2 "─── done ───\n")

    (sleep 0.3)
    (type-styled api2 "[ERROR] connection refused\n" 'error-style)
    (type-styled api2 "[OK]    retrying in 3s...\n" 'ok-style)

    (sleep 0.3)
    (type-styled api2 "▼ Errors (click)" 'error-style)
    (type api2 "\n")
    (void (begin-fold api2))
    (for ([i (in-range 1 6)])
      (type-styled api2 (format "error ~a: something went wrong\n" i) 'panel-blue))
    (end-fold api2)
    (sleep 0.3)
    (type-styled api2 "--- block closed ---\n" 'panel-blue)

    (sleep 0.3)
    (type-styled api2 "▼ Warnings" 'ok-style)
    (type api2 "\n")
    (void (begin-fold api2))
    (for ([i (in-range 1 4)])
      (type-styled api2 (format "warning ~a: low memory\n" i) 'panel-blue))
    (end-fold api2)

    (sleep 0.3)
    (type api2 "all done.\n")))

(run-app-noblock
  (out1 1 1 40 12)
  (out2 43 1 36 12)
  (inp 1 14 30 2))
