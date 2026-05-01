;; tui.rkt
#lang racket

(require "base.rkt"
         "autoresources.rkt"
         "output.rkt"
         "output-color.rkt")

(define (tui-init)
  (unless (terminal?) (error "tui-init: not a terminal"))
  (enter-raw-mode!)
  (start-thread! 'input)
  (start-thread! 'resize)
  (buffer-alt-enable))

(define (tui-exit)
  (cursor-show)
  (style-reset)
  (buffer-alt-disable)
  (stop-all!)
  (exit-raw-mode!))

(define-syntax-rule (with-tui body ...)
  (let ([exn #f])
    (dynamic-wind
     tui-init
     (λ ()
       (with-handlers ([exn:fail? (λ (e) (set! exn e))])
         body ...))
     (λ ()
       (tui-exit)
       (when exn
         (eprintf "Error: ~a\n" (exn-message exn))
         (raise exn))))))

(provide tui-init tui-exit with-tui)