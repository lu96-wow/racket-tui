#lang racket

;; char 后端的终端壳：不碰 termios / FFI，一切 no-op。
;; 保持与 base/terminal/base.rkt 同名的 API。

(provide terminal? enter-raw-mode! exit-raw-mode!
         enter-raw-mode-keep-echo!
         call-with-terminal-reply
         make-stdin-evt
         STDIN_FILENO)

(define STDIN_FILENO 0)

(define (terminal?) #t)
(define (enter-raw-mode!) (void))
(define (exit-raw-mode!) (void))
(define (enter-raw-mode-keep-echo!) (void))

(define (call-with-terminal-reply thunk #:vtime [vtime 1])
  (call-with-values thunk list))

(define (make-stdin-evt)
  (read-bytes-evt 1 (current-input-port)))
