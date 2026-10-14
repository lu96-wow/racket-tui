#lang racket

;; 帧历史 + 帧间 diff：验证「只在变化时输出新内容、且历史信息不丢」。

(require rackunit
         racket/string
         "../char.rkt")

(define (draw-at text color)
  (put-bytes (bytes-append format-screen-clear
                           (format-cursor-move 1 1)
                           (format-rgb-fg color 0 0 text))))

(module+ test

  (test-case "历史按去重后的帧记录，diff 只列变化行"
    (parameterize ([current-screen-size (cons 4 20)]
                   [current-frame-history-size 8])
      (with-tui
       (λ ()
         (draw-at "aaa" 255) (flush!)
         (draw-at "bbb" 255) (flush!)
         (check-equal? (char-history-count) 2)
         (check-equal? (string-trim (char-frame-at 0)) "aaa")
         (check-equal? (string-trim (char-frame-at 1)) "bbb")
         (check-equal? (map string-trim (char-history)) (list "aaa" "bbb"))
         (define d (char-diff))
         (check-true (string-contains? d "-aaa"))
         (check-true (string-contains? d "+bbb"))
         ;; 信息没丢：旧帧整块 grid 仍在，能事后查颜色
         (define old (char-history-ref 0))
         (check-equal? (car (screen-styled-cells old)) (list 0 0 "a" "fg(255,0,0)"))))))

  (test-case "同帧重复 flush! 不入历史（默认去重）"
    (parameterize ([current-screen-size (cons 3 10)]
                   [current-frame-history-size 8])
      (with-tui
       (λ ()
         (draw-at "x" 0) (flush!)
         (flush!) (flush!)
         (check-equal? (char-history-count) 1)))))

  (test-case "char-log-enable! 默认只打印 diff"
    (define out (open-output-string))
    (parameterize ([current-screen-size (cons 3 10)]
                   [current-frame-history-size 0])
      (with-tui
       (λ ()
         (char-log-enable! #:to out)
         (draw-at "a" 0) (flush!)
         (draw-at "b" 0) (flush!))))
    (define s (get-output-string out))
    (check-true (string-contains? s "── frame 1 ──"))   ; 首帧整屏
    (check-true (string-contains? s "── diff 2 ──"))    ; 变化只出差分
    (check-true (string-contains? s "-a"))
    (check-true (string-contains? s "+b")))

  (test-case "char-run #:diff? 返回首帧 + 逐帧 diff"
    (define n 0)
    (define out
      (char-run (list #\a #\b #\c)
                #:handle (λ (ev) (when (key-event? ev) (set! n (add1 n))))
                #:render (λ () (put-bytes (bytes-append format-screen-clear
                                                        (format-cursor-move 1 1)
                                                        (format "n=~a" n))))
                #:rows 1 #:cols 8
                #:diff? #t))
    (check-equal? (length out) 4)                       ; 首帧 + 3 个 diff
    (check-equal? (car out) "n=0")
    (check-true (string-contains? (cadr out) "+n=1"))
    (check-true (string-contains? (list-ref out 3) "+n=3"))
    (check-equal? (char-history-count) 4)
    (check-equal? (string-trim (char-frame-at 3)) "n=3"))

  (test-case "frame-diff 多行只列变化行、连续变化合并"
    (define a "r0\nr1\nr2\nr3")
    (define b "r0\nX1\nX2\nr3")
    (define d (frame-diff a b))
    (check-true (string-contains? d "@@ rows 1..2 @@"))
    (check-false (string-contains? d "r0"))
    (check-false (string-contains? d "r3"))))
