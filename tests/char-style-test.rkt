#lang racket

;; 颜色/属性信息：按需查询 + 样式 diff；以及「只有颜色变化也算变化」的去重修复。

(require rackunit
         racket/string
         "../char.rkt")

(define (draw-text color [bold? #f])
  (put-bytes (bytes-append format-screen-clear
                           (format-cursor-move 1 1)
                           (if bold? format-bold #"")
                           (format-rgb-fg color 0 0 "same")
                           format-reset)))

(module+ test

  (test-case "颜色/属性变化不被去重丢掉"
    (parameterize ([current-screen-size (cons 2 10)]
                   [current-frame-history-size 8])
      (with-tui
       (λ ()
         (draw-text 255) (flush!)
         (draw-text 0)   (flush!)
         ;; 文本完全一样，只有 fg 变了：旧实现会当成没变
         (check-equal? (char-history-count) 2)
         (check-equal? (char-diff) "")              ; 文本 diff 为空
         (define sd (char-style-diff))
         (check-true (string-contains? sd "fg(255,0,0)"))
         (check-true (string-contains? sd "fg(0,0,0)"))
         (check-true (string-contains? (char-diff #:styles? #t) "style"))))))

  (test-case "属性（bold）变化也能查"
    (parameterize ([current-screen-size (cons 2 10)]
                   [current-frame-history-size 8])
      (with-tui
       (λ ()
         (draw-text 255 #f) (flush!)
         (draw-text 255 #t) (flush!)
         (check-equal? (char-history-count) 2)
         (check-true (string-contains? (char-style-diff) "bold"))))))

  (test-case "screen-styled-cells / screen-attr-ranges 按需取色"
    (parameterize ([current-screen-size (cons 2 10)])
      (with-tui
       (λ ()
         (draw-text 46)
         (define g (the-screen))
         (check-equal? (car (screen-styled-cells g)) (list 0 0 "s" "fg(46,0,0)"))
         ;; attr ranges 把整行压成区间，颜色不塞进帧文本
         (define runs (cadr (first (screen-attr-ranges g))))
         (check-equal? (car runs) (list 0 3 "fg(46,0,0)"))
         (check-equal? (screen-style-at g 0 0) "fg(46,0,0)")
         (check-equal? (screen-style-at g 1 1) "")))))

  (test-case "style-diff 只列变化的列区间"
    (define (g-of color)
      (parameterize ([current-screen-size (cons 1 6)])
        (with-tui
         (λ ()
           (put-bytes (bytes-append format-screen-clear
                                    (format-cursor-move 1 1)
                                    (format-rgb-fg color 0 0 "ab")
                                    "cd"))
           (grid-copy (the-screen))))))
    (define d (style-diff (g-of 255) (g-of 0)))
    (check-true (string-contains? d "@@ row 0 style @@"))
    (check-true (string-contains? d "cols 0..1"))
    (check-true (string-contains? d "fg(255,0,0) -> fg(0,0,0)"))
    (check-false (string-contains? d "cols 2")))     ; "cd" 未变，不出现

  (test-case "char-run #:diff? #:styles? 带上样式 diff"
    (define color 255)
    (define out
      (char-run (list #\a)
                #:handle (λ (ev) (when (key-event? ev) (set! color 0)))
                #:render (λ () (draw-text color))
                #:rows 2 #:cols 10
                #:diff? #t #:styles? #t))
    (check-equal? (length out) 2)
    (check-true (string-contains? (cadr out) "style"))
    (check-true (string-contains? (cadr out) "fg(255,0,0) -> fg(0,0,0)")))
)
