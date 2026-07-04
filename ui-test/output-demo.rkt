#lang racket
;; ui-test/output-demo.rkt — begin-fold 新 API

(require "../ui/main.rkt"
         "../base/io/output-color.rkt")

(style-define! 'panel (color256-bg 235) (color256-fg 250))
(style-define! 'error-style (color256-bg 88) (color256-fg 231) attr-bold)
(style-define! 'ok-style (color256-bg 28) (color256-fg 231) attr-bold)
(style-define! 'warn-style (color256-bg 94) (color256-fg 231) attr-bold)

(define-values (out api) (make-output #:max-lines 500 #:style 'panel))

(append          api "═══ Fold Test ═══\n\n")

;; header + begin-fold + body
(append-styled   api "▼ Errors" 'error-style)
(append          api "\n")
(void (begin-fold api))
(for ([i (in-range 1 4)])
  (append-styled api (format "error ~a: overflow\n" i) 'panel))
;; nested
(append-styled   api "  ▼ traces" 'warn-style)
(append          api "\n")
(void (begin-fold api))
(for ([i (in-range 1 4)])
  (append-styled api (format "    trace ~a: mod.rkt:42\n" i) 'panel))
(end-fold        api)
(for ([i (in-range 4 6)])
  (append-styled api (format "error ~a: timeout\n" i) 'panel))
(end-fold        api)

(append api "\n─── click headers to fold ───\n")

(run-app-noblock (out 1 1 50 20))
