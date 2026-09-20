#lang racket

;; char 后端的事件循环宏。
;; build-input 由 io/event.rkt 提供（与 base 同名同签名）；
;; loop-input 宏必须在这里定义，因为宏模板里的 read-event 在定义处绑定，
;; 必须指向 char 的脚本输入。

(require "event.rkt")

(define-syntax loop-input
  (syntax-rules ()
    [(_ handler ...)
     (let event-loop ()
       (define ev (read-event))
       (handler ev) ...
       (event-loop))]))

(define-syntax loop-input-noblock
  (syntax-rules ()
    [(_ handler ...)
     (let event-loop ()
       (define ev (read-event-noblock))
       (handler ev) ...
       (event-loop))]))

(define-syntax loop-input/stop
  (syntax-rules ()
    [(_ stop? handler ...)
     (let event-loop ()
       (define ev (read-event))
       (handler ev) ...
       (unless stop? (event-loop)))]))

(define-syntax loop-input-noblock/stop
  (syntax-rules ()
    [(_ stop? handler ...)
     (let event-loop ()
       (define ev (read-event-noblock))
       (handler ev) ...
       (unless stop? (event-loop)))]))

(provide build-input loop-input loop-input-noblock
         loop-input/stop loop-input-noblock/stop)
