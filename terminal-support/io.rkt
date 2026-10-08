#lang racket

;; ════════════════════════════════════════════════════════════════
;; terminal-support/io.rkt
;;
;; 查询的收发：一次写出所有查询，再一次读到"DA1 哨兵 / idle / 总超时"。
;;
;; 哨兵法取自 crossterm（"CSI ?u" + "CSI c"）与 termwiz（XTVERSION + DA1）：
;; 把 Primary DA (CSI c) 放在最后，收到它的回复即表示终端已处理完前面的查询；
;; 于是"收到 DA1 但没收到目标回复"= 确定不支持，而不是"还没回"。
;; 命中 DA1 立即收工，不再空等 idle。
;;
;; 性能：用 read-bytes-evt(1) 等"有数据"（它会把读到的 1 字节作为 sync 结果
;; 返回并消费掉，必须写回），再用 read-bytes-avail! 一次吸干当前可读的整批，
;; 避免逐字节 sync 的定时器开销。
;;
;; 前提：调用方已把终端置入 raw 模式（关闭 ECHO/ICANON）。
;; 本模块不做 FFI、不改 termios。
;; ════════════════════════════════════════════════════════════════

(require racket/port
         "query.rkt")

(provide read-reply exchange-queries exchange-queries/one)

;; 读到「done? 命中」或「idle 秒内无新数据」或总 timeout 为止，返回累积字节串。
(define (read-reply #:timeout [timeout 0.30] #:idle [idle 0.05] #:done? [done? #f])
  (define in (current-input-port))
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
      ;; 总超时 / 端口 EOF：收工
      [(eq? ev 'expired) (finish)]
      [(eof-object? ev) (finish)]
      ;; 这段 idle 没数据：已有数据且空闲够久 → 收工；否则继续等总超时
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
       ;; 哨兵命中就立即收工（终端按输入顺序回复，DA1 在最后）
       (if (and done? (done? all))
           all
           (loop (current-inexact-milliseconds) #t))])))

;; queries : (listof bytes)，调用方保证 DA1 在最后。
;; 一次性写完 → flush → 读到 idle / timeout。
;; 注意：#:done? 默认 #f。因为并非所有终端严格按序回复（xterm.js 就可能 DA1 先到），
;; 早停会把后续回复留给 shell。要早停请显式传 #:done? da1-reply?。
(define (exchange-queries queries #:timeout [timeout 0.30] #:idle [idle 0.05]
                         #:done? [done? #f])
  (for ([q (in-list queries)])
    (write-bytes q (current-output-port)))
  (flush-output)
  (read-reply #:timeout timeout #:idle idle #:done? done?))

;; 单个查询的便捷封装（默认读到 idle；除非自身就是 DA1）。
(define (exchange-queries/one query #:timeout [timeout 0.30] #:idle [idle 0.05]
                              #:done? [done? #f])
  (exchange-queries (list query) #:timeout timeout #:idle idle #:done? done?))
