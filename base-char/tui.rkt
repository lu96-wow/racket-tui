#lang racket

;; char 后端的生命周期 —— 与 base/tui.rkt 同名 API，但不碰 termios，
;; 只负责准备/清理当前 grid。

(require "screen/session.rkt"
         "screen/grid.rkt"
         "terminal/resize.rkt"
         "io/output.rkt"
         "io/output-color.rkt"
         "ansi/ansi-var.rkt")

(define (init-newline-var) (set-box! newline-var "\r\n"))
(define (reset-newline-var) (set-box! newline-var "\n"))

(define (char-init! #:rows [rows #f] #:cols [cols #f])
  (when (and rows cols) (current-screen-size (cons rows cols)))
  (define size (current-screen-size))
  (current-screen (make-grid (car size) (cdr size)))
  (frame-reset!)
  (init-newline-var)
  (use-color-auto!))

(define (char-exit!) (reset-newline-var))

;; ── 与 base 同名 ─────────────────────────────────────────

(define (tui-init #:rows [rows #f] #:cols [cols #f]) (char-init! #:rows rows #:cols cols))
(define (tui-exit) (char-exit!))
(define tui-init-no-buffer tui-init)
(define tui-exit-no-buffer tui-exit)
(define tui-init-no-buffer-echo tui-init)
(define tui-exit-no-buffer-echo tui-exit)

(define (with-tui thunk #:rows [rows #f] #:cols [cols #f])
  (dynamic-wind (λ () (char-init! #:rows rows #:cols cols)) thunk char-exit!))

(define (with-tui-nobuffer thunk #:rows [rows #f] #:cols [cols #f])
  (with-tui thunk #:rows rows #:cols cols))

(define (with-tui-nobuffer-echo thunk #:rows [rows #f] #:cols [cols #f])
  (with-tui thunk #:rows rows #:cols cols))

(define (enable-mouse!) (void))
(define (disable-mouse!) (void))
(define (enable-bracketed-paste!) (void))
(define (disable-bracketed-paste!) (void))

(provide tui-init tui-exit
         tui-init-no-buffer tui-exit-no-buffer
         tui-init-no-buffer-echo tui-exit-no-buffer-echo
         init-newline-var reset-newline-var
         with-tui with-tui-nobuffer with-tui-nobuffer-echo
         enable-mouse! disable-mouse!
         enable-bracketed-paste! disable-bracketed-paste!)
