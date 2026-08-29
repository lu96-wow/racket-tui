;; test-matrix.rkt
#lang racket

(require "../main.rkt")

(for ([i 30])
  (style-define! (string->symbol (format "g~a" i)) (color256-fg (+ 22 i))))

(define chars "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()")

(define (get-style-bytes style-name)
  (call-with-output-bytes
   (λ (out)
     (parameterize ([current-output-port out])
       (style-apply! style-name)))))

(define (generate-frame rows cols drops tails active-cols)
  (define frame-buffer (bytes))

  (define (add-to-frame . parts)
    (for ([p parts])
      (set! frame-buffer (bytes-append frame-buffer p))))

  (add-to-frame format-screen-clear)

  (for ([col active-cols])
    (define old-row (vector-ref drops col))
    (define tail-len (vector-ref tails col))
    (define new-row (+ old-row 1))

    (vector-set! drops col new-row)

    (when (> new-row (+ rows tail-len))
      (vector-set! drops col (- (random 20)))
      (vector-set! tails col (+ 4 (random 6))))

    ;; 头部
    (when (and (>= new-row 0) (< new-row rows))
      (define ch (string (string-ref chars (random (string-length chars)))))
      (define style-name (string->symbol (format "g~a" (+ 25 (random 5)))))
      (define style-bytes (get-style-bytes style-name))
      (add-to-frame (format-cursor-move new-row col)
                    style-bytes (format-content ch) format-reset))

    ;; 尾迹
    (for ([i (in-range 1 tail-len)])
      (define r (- new-row i))
      (when (and (>= r 0) (< r rows))
        (define ch (string (string-ref chars (random (string-length chars)))))
        (define style-name (string->symbol (format "g~a" (max 0 (- 5 i)))))
        (define style-bytes (get-style-bytes style-name))
        (add-to-frame (format-cursor-move r col)
                      style-bytes (format-content ch) format-reset))))

  frame-buffer)

(with-tui
 (λ ()
   (cursor-hide)
   (screen-clear)
   (let-values ([(rows cols) (get-window-size)])

    (define active-cols (for/list ([c (in-range 0 cols 3)]) c))
    (define drops (make-vector cols -10))
    (define tails (make-vector cols 0))
    (for ([c active-cols])
      (vector-set! drops c (- (random rows)))
      (vector-set! tails c (+ 4 (random 6))))

    (define running? #t)

    (let loop ()
      (when running?
        ;; read-event-noblock 内部使用 select(timeout=0), 不阻塞
        (let drain ()
          (let-values ([(type data mods) (read-event-noblock)])
            (cond [(event-null? type) (void)]
                  [(event-resize? type)
                   (let-values ([(nr nc) (get-resize-size data)])
                     (set! rows nr)
                     (set! cols nc)
                     (set! active-cols (for/list ([c (in-range 0 nc 3)]) c))
                     (define new-drops (make-vector nc -10))
                     (define new-tails (make-vector nc 0))
                     (for ([c (in-range 0 (min nc (vector-length drops)))])
                       (vector-set! new-drops c (vector-ref drops c))
                       (vector-set! new-tails c (vector-ref tails c)))
                     (for ([c active-cols])
                       (when (>= c (vector-length drops))
                         (vector-set! new-drops c (- (random nr)))
                         (vector-set! new-tails c (+ 4 (random 6)))))
                     (set! drops new-drops)
                     (set! tails new-tails))
                   (drain)]
                  [(and (event-key? type) (= (event->byte data) (char->integer #\q)))
                   (set! running? #f)]
                  [else (drain)])))

        (define frame (generate-frame rows cols drops tails active-cols))
        (put-bytes frame)

        (sleep 0.06)
        (loop))))))