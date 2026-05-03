;; test-matrix.rkt
#lang racket

(require "../main.rkt")

(for ([i 30])
  (style-define! (string->symbol (format "g~a" i)) (color256-fg (+ 22 i))))

(define chars "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()")

;; 辅助函数：将样式名称转换为字节串
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

  ;; 清屏
  (add-to-frame format-screen-clear)

  ;; 绘制所有活动的列
  (for ([col active-cols])
    (define old-row (vector-ref drops col))
    (define tail-len (vector-ref tails col))
    (define new-row (+ old-row 1))

    ;; 更新位置
    (vector-set! drops col new-row)

    ;; 超出底部处理
    (when (> new-row (+ rows tail-len))
      (vector-set! drops col (- (random 20)))
      (vector-set! tails col (+ 4 (random 6))))

    ;; 绘制头部（在可见范围内）
    (when (and (>= new-row 0) (< new-row rows))
      (define ch (string (string-ref chars (random (string-length chars)))))
      (define style-name (string->symbol (format "g~a" (+ 25 (random 5)))))
      (define style-bytes (get-style-bytes style-name))
      (add-to-frame (format-cursor-move new-row col)
                    (format-styled style-bytes ch)))

    ;; 绘制尾迹
    (for ([i (in-range 1 tail-len)])
      (define r (- new-row i))
      (when (and (>= r 0) (< r rows))
        (define ch (string (string-ref chars (random (string-length chars)))))
        (define style-name (string->symbol (format "g~a" (max 0 (- 5 i)))))
        (define style-bytes (get-style-bytes style-name))
        (add-to-frame (format-cursor-move r col)
                      (format-styled style-bytes ch)))))

  frame-buffer)

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

    (define running? #t)

    (let loop ()
      (when running?
        ;; 处理输入
        (change-noblock)
        (let drain ()
          (let-values ([(type data mods) (read-event)])
            (cond [(event-null? type) (void)]
                  [(and (event-key? type) (= (event->byte data) (char->integer #\q)))
                   (set! running? #f)]
                  [else (drain)])))

        ;; 处理窗口大小变化
        (let-values ([(new-rows new-cols) (get-window-size)])
          (when (and new-rows new-cols
                     (or (not (= new-rows rows)) (not (= new-cols cols))))
            (set! rows new-rows)
            (set! cols new-cols)
            ;; 更新活动列
            (set! active-cols (for/list ([c (in-range 0 cols 3)]) c))
            ;; 调整数组大小
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

        ;; 生成并输出一帧
        (define frame (generate-frame rows cols drops tails active-cols))
        (put-bytes frame)

        (sleep 0.06)
        (loop)))))