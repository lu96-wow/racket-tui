#lang racket

;; op 表示：char 后端里 format-* 不再返回 ANSI 字节，而是返回 op（op-seq）。
;; put-* 在应用时才把 op 作用到 grid。这样全程无需解析。
;;
;; op-seq 就是 op 的 list（空 list 也合法）。
;; bytes-append 在 char 后端被覆盖为 ops-append，因此
;;   (bytes-append format-screen-clear (format-cursor-move 5 10) "hi")
;; 这类批量写法可以原样工作。

(provide (struct-out op)
         make-op
         op-seq?
         ops-append
         ->ops)

(struct op (kind args) #:transparent)

(define (op-seq? x)
  (and (list? x) (andmap op? x)))

(define (make-op kind . args)
  (op kind args))

(define (->ops x)
  (cond
    [(op? x) (list x)]
    [(op-seq? x) x]
    [(bytes? x) (list (op 'text (list x)))]
    [(string? x) (list (op 'text (list x)))]
    [(char? x) (list (op 'text (list (string x))))]
    [else (list (op 'text (list (format "~a" x))))]))

(define (ops-append . parts)
  (append* (map ->ops parts)))
