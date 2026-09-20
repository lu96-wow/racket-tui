#lang racket

;; 无终端 / 无 tty 的完整事件循环演示。
;;
;; 用 char-run：给一串脚本事件，每个事件处理并渲染一次，脚本跑完即结束。
;; 帧数有界（≤ 事件数+1），不会因为非阻塞循环而无限输出。
;;
;; 运行: racket demo/char-app.rkt

(require "../char.rkt")

(define count 0)
(define quit? #f)

(define (draw)
  (put-bytes
   (bytes-append
    format-screen-clear
    (format-cursor-move 1 1)
    (format-rgb-fg 0 255 0 "Counter demo")
    (format-cursor-move 3 1)
    (format-256-fg 46 (format "count = ~a" count))
    (format-cursor-move 5 1)
    format-bold "keys: + - q" format-reset)))

(define frames
  (char-run (list #\+ #\+ #\- #\q)
            #:handle (λ (ev)
                       (when (key-event? ev)
                         (case (key-event-key ev)
                           [(#\+) (set! count (add1 count))]
                           [(#\-) (set! count (sub1 count))]
                           [(#\q) (set! quit? #t)]
                           [else (void)])))
            #:render draw
            #:stop (λ () quit?)
            #:rows 7 #:cols 24))

(for ([f frames])
  (displayln f)
  (displayln "────────"))
