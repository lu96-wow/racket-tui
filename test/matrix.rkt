;; test-matrix.rkt
#lang racket

(require "../main.rkt")

(for ([i 30])
  (style-define! (string->symbol (format "g~a" i)) (color256-fg (+ 22 i))))

(with-tui
    (cursor-hide)
  (screen-clear)
  (let-values ([(rows cols) (get-window-size)])

    ;; 每 3 列放一条鱼
    (define active-cols (for/list ([c (in-range 0 cols 3)]) c))
    (define drops (make-vector cols -10))
    (define tails (make-vector cols 0))
    (for ([c active-cols])
      (vector-set! drops c (- (random rows)))
      (vector-set! tails c (+ 4 (random 6))))
    (define chars "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()")
    (define running? #t)

    (let loop ()
      (when running?
        (change-noblock)
        (let drain ()
          (let-values ([(type data mods) (read-event)])
            (cond [(event-null? type) (void)]
                  [(and (event-key? type) (= (event->byte data) (char->integer #\q)))
                   (set! running? #f)]
                  [else (drain)])))

        (for ([col active-cols])
          (define old-row (vector-ref drops col))
          (define tail-len (vector-ref tails col))
          (define new-row (+ old-row 1))

          ;; 超出底部 → 自然流走消失，再随机重现
          (cond
            [(> new-row (+ rows tail-len))
             ;; 清除残留
             (for ([r (in-range (max 0 (- old-row tail-len)) (min rows (+ old-row 1)))])
               (put-at r col " "))
             ;; 随机延迟再开始
             (vector-set! drops col (- (random 20)))
             (vector-set! tails col (+ 4 (random 6)))]

            ;; 刚开始进入屏幕
            [(< new-row (- tail-len))
             (vector-set! drops col new-row)]

            ;; 正常下落（包括进入屏幕前先绘制可见部分）
            [else
             (vector-set! drops col new-row)

             ;; 清除尾迹末端
             (define clear-row (- new-row tail-len))
             (when (and (>= clear-row 0) (< clear-row rows))
               (put-at clear-row col " "))

             ;; 绘制头部
             (when (and (>= new-row 0) (< new-row rows))
               (define ch (string (string-ref chars (random (string-length chars)))))
               (put-styled-at new-row col (string->symbol (format "g~a" (+ 25 (random 5)))) ch))

             ;; 绘制尾迹
             (for ([i (in-range 1 tail-len)])
               (define r (- new-row i))
               (when (and (>= r 0) (< r rows))
                 (define ch (string (string-ref chars (random (string-length chars)))))
                 (put-styled-at r col (string->symbol (format "g~a" (max 0 (- 5 i)))) ch)))]))

        (sleep 0.06)
        (loop)))))