#lang racket

;; 调试循环：不阻塞、去重、只在变化时打印差分行。
;; 运行: racket demo/char-debug-loop.rkt
;;
;; 输出里首帧是整屏，之后每次变化只出 @@/ -/+ 几行；没有变化的事件（如 q）
;; 不产生任何输出。

(require "../char.rkt")

(define count 0)
(define quit? #f)

(define (draw)
  (put-bytes
   (bytes-append
    format-screen-clear
    (format-cursor-move 1 1)
    (format "count = ~a" count)
    (format-cursor-move 2 1)
    "keys: + - q")))

(parameterize ([current-screen-size (cons 3 20)]
               [current-frame-history-size 16])
 (with-tui
  (λ ()
    (char-input-push! #\+ #\+ #\+ #\- #\q)
    (char-log-enable!)                    ; 默认 #:diff? #t，打到 stdout

    (draw) (flush!)                       ; 首帧

    (define handler
      (build-input
       #:key (λ (k m)
               (case k
                 [(#\+) (set! count (add1 count))]
                 [(#\-) (set! count (sub1 count))]
                 [(#\q) (set! quit? #t)]
                 [else (void)]))))

    (loop-input/stop quit?
                     (λ (ev) (handler ev) (draw) (flush!)))

    ;; 事后可查：历史全部保留（颜色/属性也在）
    (displayln "────────")
    (displayln (format "history frames: ~a" (char-history-count)))
    (displayln (format "last diff:\n~a" (char-diff))))))
