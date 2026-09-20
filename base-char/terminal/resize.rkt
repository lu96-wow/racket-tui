#lang racket

;; char 后端的尺寸来源：concurrent 参数 current-screen-size，而不是 ioctl。

(require "../screen/session.rkt")

(provide get-window-size
         resize-monitor-start resize-monitor-stop
         make-resize-evt)

(define (get-window-size (fd 1))
  (values (car (current-screen-size))
          (cdr (current-screen-size))))

(define (resize-monitor-start) (void))
(define (resize-monitor-stop) (void))

(define (make-resize-evt) never-evt)
