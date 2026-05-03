#lang racket

(define registry (make-hash))

(define (register-thread! name start-fn stop-fn)
  (hash-set! registry name (list start-fn stop-fn #f)))

(define (start-thread! name)
  (match (hash-ref registry name #f)
    [(list start-fn stop-fn #f)
     (define t (start-fn))
     (hash-set! registry name (list start-fn stop-fn t))
     t]
    [_ #f]))

(define (stop-thread! name)
  (match (hash-ref registry name #f)
    [(list start-fn stop-fn (? thread? t))
     (stop-fn t)
     (hash-set! registry name (list start-fn stop-fn #f))]
    [_ (void)]))

(define (start-all!)
  (for ([(name _) (in-hash registry)]) (start-thread! name)))

(define (stop-all!)
  (for ([(name _) (in-hash registry)]) (stop-thread! name)))

(define (thread-running? name)
  (match (hash-ref registry name #f)
    [(list _ _ (? thread?)) #t]
    [_ #f]))

(provide register-thread! start-thread! stop-thread!
         start-all! stop-all! thread-running?)