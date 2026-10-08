#lang racket

;; ════════════════════════════════════════════════════════════════
;; terminal-support/io.rkt —— 传输
;;
;; 一次写出所有 request，读到"DA1 哨兵 / idle / 总超时"。
;; 入/出端口是**显式参数**（默认 current-*-port，可覆盖）——不藏隐式 I/O 状态。
;; ════════════════════════════════════════════════════════════════

(require racket/port
         "query.rkt")

(provide read-reply exchange-queries)

;; 读到「done? 命中」或「idle 秒内无新数据」或总 timeout 为止，返回累积字节串。
(define (read-reply #:in [in (current-input-port)]
                    #:timeout [timeout 0.30] #:idle [idle 0.05] #:done? [done? #f])
  (define out (open-output-bytes))
  (define buf (make-bytes 4096))
  (define t0 (current-inexact-milliseconds))
  (define (finish) (get-output-bytes out))
  (let loop ([last t0] [got? #f])
    (define left (- (+ t0 (* timeout 1000.0)) (current-inexact-milliseconds)))
    (define ev (if (<= left 0.0)
                   'expired
                   (sync/timeout (min idle (/ left 1000.0)) (read-bytes-evt 1 in))))
    (cond
      [(eq? ev 'expired) (finish)]
      [(eof-object? ev) (finish)]
      [(not ev)
       (if (and got? (>= (- (current-inexact-milliseconds) last) (* idle 1000.0)))
           (finish)
           (loop last got?))]
      [else
       ;; ev 是 read-bytes-evt 读到的 1 字节，先写回
       (write-bytes ev out)
       ;; 再一次吸干当前可读的剩余部分
       (define n (read-bytes-avail! buf in))
       (when (and (exact-nonnegative-integer? n) (positive? n))
         (write-bytes buf out 0 n))
       (define all (finish))
       (if (and done? (done? all))
           all
           (loop (current-inexact-milliseconds) #t))])))

;; queries : (listof bytes)。一次性写完 → flush → 读到 DA1 回复 / idle / timeout。
(define (exchange-queries queries
                          #:in [in (current-input-port)]
                          #:out [out (current-output-port)]
                          #:timeout [timeout 0.30] #:idle [idle 0.05] #:done? [done? #f])
  (for ([q (in-list queries)]) (write-bytes q out))
  (flush-output out)
  (read-reply #:in in #:timeout timeout #:idle idle #:done? done?))
