#lang racket

;; 用新的输入 DSL 写一个最小行编辑器场景，验证「写起来顺手」。
;; 运行: racket demo/char-input-dsl.rkt

(require "../char.rkt")

(define line "")
(define submitted '())
(define quit? #f)

(define (draw)
  (put-bytes
   (bytes-append
    format-screen-clear
    (format-cursor-move 1 1) format-bold "char-input DSL demo" format-reset
    (format-cursor-move 3 1) "line: " line
    (format-cursor-move 5 1) (format "submitted: ~a" (reverse submitted))
    (format-cursor-move 7 1) "type / Enter submit / Ctrl-C quit")))

(define (handle ev)
  (cond
    [(paste-event? ev)
     (set! line (string-append line (paste-event-text ev)))]
    [(key-event? ev)
     (define k (key-event-key ev))
     (define m (key-event-mods ev))
     (cond
       [(and (char? k) (mods-ctrl? m) (eqv? k #\c)) (set! quit? #t)]
       [(eqv? k #\backspace)
        (unless (string=? line "")
          (set! line (substring line 0 (sub1 (string-length line)))))]
       [(eq? k 'enter) (set! submitted (cons line submitted)) (set! line "")]
       [(char? k) (set! line (string-append line (string k)))]
       [else (void)])]
    [else (void)]))

(define frames
  (char-run
   (list "he" #\l #\l #\o     ; 敲 "hello"
         'backspace          ; 删一个
         'shift "!"          ; shift + !
         'enter              ; 提交
         'paste " world"     ; 粘贴
         'ctrl #\c)          ; 退出
   #:handle handle
   #:render draw
   #:stop (λ () quit?)
   #:rows 9 #:cols 44))

(for ([f frames])
  (displayln f)
  (displayln "────────────────"))
