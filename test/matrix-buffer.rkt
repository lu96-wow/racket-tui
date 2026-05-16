;; test-matrix-buffer.rkt — 字符雨 + 双缓冲 diff 渲染
;; 对比原版 matrix.rkt：每帧只输出变化格子，不重建整个 bytes buffer
#lang racket
(require "../main.rkt"
         "../build-input.rkt")

(define chars "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()")

(for ([i 30])
  (style-define! (string->symbol (format "g~a" i)) (color256-fg (+ 22 i))))

(define (get-style-bytes style-name)
  (call-with-output-bytes
   (λ (out)
     (parameterize ([current-output-port out]
                    [current-screen #f])
       (style-apply! style-name)))))

(with-tui
    (cursor-hide)
  (screen-clear)
  (let-values ([(rows cols) (get-window-size)])

    (define active-cols (for/list ([c (in-range 0 cols 2)]) c))
    (define drops (make-vector cols -10))
    (define tails (make-vector cols 0))
    (for ([c active-cols])
      (vector-set! drops c (- (random rows)))
      (vector-set! tails c (+ 4 (random 6))))

    (define running? #t)
    (define frame-count 0)
    (define start-time (current-inexact-milliseconds))

    ;; 双缓冲：整个运行期复用一个 buffer，跨帧 diff
    (define buf (make-screen-buffer))

    ;; 输入处理
    (define input-handler
      (build-input
       #:char (lambda (ch)
                (when (= ch (char->integer #\q))
                  (set! running? #f)))
       #:any (lambda (t d m) (void))))

    (let loop ()
      (when running?
        (change-noblock)
        (let drain ()
          (let-values ([(type data mods) (read-event)])
            (unless (event-null? type)
              (input-handler type data mods)
              (drain))))

        ;; resize 检测
        (let-values ([(new-rows new-cols) (get-window-size)])
          (when (and new-rows new-cols
                     (or (not (= new-rows rows)) (not (= new-cols cols))))
            (set! rows new-rows)
            (set! cols new-cols)
            (set! active-cols (for/list ([c (in-range 0 cols 2)]) c))
            (define new-drops (make-vector cols -10))
            (define new-tails (make-vector cols 0))
            (for ([c (in-range 0 (min cols (vector-length drops)))])
              (vector-set! new-drops c (vector-ref drops c))
              (vector-set! new-tails c (vector-ref tails c)))
            (for ([c active-cols])
              (when (>= c (vector-length drops))
                (vector-set! new-drops c (- (random rows)))
                (vector-set! new-tails c (+ 4 (random 6)))))
            (set! drops new-drops)
            (set! tails new-tails)))

        ;; ── 双缓冲 diff 渲染（复用 buf，跨帧比较）──
        (parameterize ([current-screen buf])
          (sb-ensure! buf rows cols)
          ;; 先清除上一帧尾迹位置（字符下落后旧位置变空）
          (sb-clear! buf)

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
              (define style-bytes (get-style-bytes
                                   (string->symbol (format "g~a" (+ 25 (random 5))))))
              (sb-put! buf new-row col
                       (bytes-append style-bytes (string->bytes/utf-8 ch) format-reset)))

            ;; 尾迹
            (for ([i (in-range 1 tail-len)])
              (define r (- new-row i))
              (when (and (>= r 0) (< r rows))
                (define ch (string (string-ref chars (random (string-length chars)))))
                (define style-bytes (get-style-bytes
                                     (string->symbol (format "g~a" (max 0 (- 5 i))))))
                (sb-put! buf r col
                         (bytes-append style-bytes (string->bytes/utf-8 ch) format-reset)))))

          (sb-flush! buf))

        (set! frame-count (+ frame-count 1))
        (sleep 0.06)
        (loop)))

    ;; 退出时显示帧率
    (define elapsed (- (current-inexact-milliseconds) start-time))
    (define fps (if (> elapsed 0) (/ frame-count (/ elapsed 1000.0)) 0))
    (printf "~a frames in ~ams = ~a fps\n" frame-count (exact-round elapsed) (real->decimal-string fps 1))))
