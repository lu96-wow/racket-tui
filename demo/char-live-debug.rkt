#lang racket

;; 实时调试：生产者线程按时间喂输入，阻塞的主循环消费，char-log-enable!
;; 实时只打印变化。验证「不阻塞循环 + 历史比对 + 只在变化时输出」。
;; 运行: racket demo/char-live-debug.rkt

(require "../char.rkt")

(define items '("alpha" "beta" "gamma" "delta" "epsilon" "zeta" "eta" "theta"))
(define sel 0)
(define quit? #f)
(define view-h 4)                                   ; 可见行数

(define (clamp x lo hi) (max lo (min hi x)))
(define (top-index)
  (clamp (- sel (quotient view-h 2)) 0 (max 0 (- (length items) view-h))))

(define (draw)
  (define top (top-index))
  (put-bytes
   (bytes-append
    format-screen-clear
    (format-cursor-move 1 1) format-bold "Items" format-reset
    (apply bytes-append
           (for/list ([it (in-list (take (drop items top) view-h))] [i (in-naturals)])
             (define actual (+ top i))
             (bytes-append
              (format-cursor-move (+ 2 i) 1)
              (if (= actual sel)
                  (format-rgb-bg 60 60 120 (bytes-append "> " it " "))   ; 选中高亮
                  (bytes-append "  " it)))))
    (format-cursor-move (+ 3 view-h) 1)
    (format "sel=~a top=~a" sel top))))

(parameterize ([current-screen-size (cons (+ view-h 4) 24)]
               [current-frame-history-size 64])
 (with-tui
  (λ ()
    (char-input-clear!)
    (char-log-enable!)                            ; 默认只打印 diff，带帧号

    (draw) (flush!)                               ; 首帧

    ;; 生产者线程：模拟用户每隔 50ms 按一个键，最后 close 结束脚本
    (thread (λ ()
              (for ([e (in-list '(down down down down up up))])
                (sleep 0.05)
                (char-input-push! e))
              (char-input-close!)))

    (define handler
      (build-input
       #:key (λ (k m)
               (case k
                 [(down) (set! sel (min (sub1 (length items)) (add1 sel)))]
                 [(up)   (set! sel (max 0 (sub1 sel)))]
                 [else (void)]))))

    ;; stop? 是“每轮求值的表达式”，不是 thunk；close 后读尽即退出
    (loop-input/stop (or quit? (char-input-exhausted?))
                     (λ (ev) (handler ev) (draw) (flush!)))

    (displayln "────────")
    (displayln (format "history: ~a frames" (char-history-count)))
    (displayln "last frame attr ranges (dumped on demand):")
    (for ([row (in-list (screen-attr-ranges (the-screen)))])
      (displayln row)))))
