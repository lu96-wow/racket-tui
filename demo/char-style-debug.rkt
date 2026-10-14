#lang racket

;; 颜色调试：文本不变、只变颜色时也要能看到差异。
;; 运行: racket demo/char-style-debug.rkt
;;
;; space 切换 "SELECTED" 的颜色（文本不动）→ 输出 style diff；
;; + / - 改数字 → 输出文本 diff。

(require "../char.rkt")

(define count 0)
(define sel 0)                          ; 0 / 1
(define quit? #f)

(define (color-for n) (case n [(0) 240] [(1) 46] [else 196]))

(define (draw)
  (put-bytes
   (bytes-append
    format-screen-clear
    (format-cursor-move 1 1) (format "count = ~a" count)
    (format-cursor-move 2 1)
    (format-256-fg (color-for sel) "SELECTED")   ; 文本恒为 SELECTED
    format-reset
    (format-cursor-move 3 1) "keys: space toggle, + - q")))

(parameterize ([current-screen-size (cons 4 30)]
               [current-frame-history-size 16])
 (with-tui
  (λ ()
    (char-input-push! #\+ #\space #\- #\space #\q)
    (char-log-enable!)

    (draw) (flush!)

    (define handler
      (build-input
       #:key (λ (k m)
               (case k
                 [(#\+) (set! count (add1 count))]
                 [(#\-) (set! count (sub1 count))]
                 [(#\space) (set! sel (if (= sel 0) 1 0))]
                 [(#\q) (set! quit? #t)]
                 [else (void)]))))

    (loop-input/stop quit? (λ (ev) (handler ev) (draw) (flush!)))

    (displayln "────────")
    (displayln (format "last style diff:\n~a" (char-style-diff))))))
