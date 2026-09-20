#lang racket

;; char 后端测试
;;  1. bytes-append 确实被覆盖成 ops-append
;;  2. 同一段 UI：op 路径（base-char）与 ANSI 解析路径（base-char/screen/ansi-parse）
;;     渲染出的字符图完全一致 —— 用独立实现互为对照

(require rackunit
         (rename-in racket/base [bytes-append raw-bytes-append])
         (prefix-in b: "../base/ansi/ansi-format.rkt")
         (prefix-in be: "../base/io/event.rkt")
         "../char.rkt")

(define (op-path thunk #:rows [rows 8] #:cols [cols 24])
  (with-tui (λ () (thunk) (char-frame)) #:rows rows #:cols cols))

(define (parse-path bs #:rows [rows 8] #:cols [cols 24])
  (define p (make-ansi-parser rows cols))
  (ansi-parser-feed-bytes! p bs)
  (grid->text (ansi-parser-grid p)))

(module+ test

  (test-case "bytes-append 被 base-char 覆盖为 op 拼接"
    (check-true (op-seq? (bytes-append format-screen-clear)))
    (check-true (op-seq? (bytes-append format-screen-clear (format-cursor-move 1 1) "hi")))
    (check-equal? (length (bytes-append format-reset format-reset)) 2))

  (test-case "op 路径与 ANSI 解析路径一致"
    (define op-text
      (op-path
       (λ ()
         (screen-clear)
         (put-at 3 5 "hi")
         (put-rgb-fg 255 0 0 "R")
         (put-256-fg 46 "G")
         (put-bold)
         (put-string "B")
         (put-reset)
         (cursor-move 5 2)
         (put-string "end"))
       #:rows 8 #:cols 24))

    (define ansi-bytes
      (raw-bytes-append
       b:format-screen-clear
       (b:format-cursor-move 1 1)          ; 对齐 screen-clear 的归位
       (b:format-content-at 3 5 "hi")
       (b:format-rgb-fg 255 0 0 "R")
       (b:format-256-fg 46 "G")
       b:format-bold #"B" b:format-reset
       (b:format-cursor-move 5 2) #"end"))

    (check-equal? op-text (parse-path ansi-bytes #:rows 8 #:cols 24)))

  (test-case "宽度 / 宽字符两路径一致"
    (define op-text
      (op-path
       (λ () (screen-clear) (put-at 1 1 "a你b好c"))
       #:rows 4 #:cols 16))
    (define ansi-bytes
      (raw-bytes-append
       b:format-screen-clear
       (b:format-content-at 1 1 (string->bytes/utf-8 "a你b好c"))))
    (check-equal? op-text (parse-path ansi-bytes #:rows 4 #:cols 16)))

  (test-case "消隐/擦除两路径一致"
    (define op-text
      (op-path
       (λ ()
         (screen-clear)
         (put-at 1 1 "abcdef")
         (cursor-move 1 3)
         (line-clear-right))
       #:rows 4 #:cols 12))
    (define ansi-bytes
      (raw-bytes-append
       b:format-screen-clear (b:format-cursor-move 1 1)
       (b:format-content-at 1 1 "abcdef")
       (b:format-cursor-move 1 3) b:format-line-clear-right))
    (check-equal? op-text (parse-path ansi-bytes #:rows 4 #:cols 12)))

  (test-case "归一化行为与 base 一致（防漂移）"
    ;; char 与 base 的事件结构体类型不同，比较语义摘要
    (define (char-sum ev)
      (cond [(key-event? ev) (list 'key (key-event-key ev) (mods->list (key-event-mods ev)))]
            [(null-event? ev) '(null)]
            [(resize-event? ev) (list 'resize (resize-event-rows ev) (resize-event-cols ev))]
            [(mouse-event? ev) (list 'mouse (mouse-event-action ev) (mouse-event-button ev)
                                     (mouse-event-x ev) (mouse-event-y ev))]
            [(paste-event? ev) (list 'paste (paste-event-bytes ev) (paste-event-text ev))]
            [else (list 'other)]))
    (define (base-sum ev)
      (cond [(be:key-event? ev) (list 'key (be:key-event-key ev) (be:mods->list (be:key-event-mods ev)))]
            [(be:null-event? ev) '(null)]
            [(be:resize-event? ev) (list 'resize (be:resize-event-rows ev) (be:resize-event-cols ev))]
            [(be:mouse-event? ev) (list 'mouse (be:mouse-event-action ev) (be:mouse-event-button ev)
                                        (be:mouse-event-x ev) (be:mouse-event-y ev))]
            [(be:paste-event? ev) (list 'paste (be:paste-event-bytes ev) (be:paste-event-text ev))]
            [else (list 'other)]))
    (define cases
      (list '(null #f #f)
            '(resize (10 . 20) #f)
            '(key #"a" #f)
            '(key #"\r" #f)
            '(key #"\x7f" #f)
            '(ctrl #"\x01" #f)
            '(alt #"\x1bb" #f)
            '(up #f #f)
            '(home #f #f)
            '(mod-seq #"\x1b[1;5A" #f)
            '(mod-seq #"\x1b[3;5~" #f)
            '(utf8 #"\xe4\xbd\xa0" #f)
            '(paste #"hi" #f)
            '(mouse (press left 3 4 #f) #f)))
    (for ([c cases])
      (check-equal? (char-sum (apply normalize-event c))
                    (base-sum (apply be:normalize-event c))
                    (format "case ~a" c))))

  (test-case "样式系统写入 grid（按需属性）"
    (define cells
      (with-tui
       (λ ()
         (screen-clear)
         (put-at 1 1 "X")
         (put-styled-at 2 1 'error "E")
         (screen-styled-cells (the-screen)))
       #:rows 6 #:cols 16))
    (check-not-false (member '(0 0 "X" "") cells))
    (define e (findf (λ (c) (equal? (cadr c) 0)) (filter (λ (c) (equal? (car c) 1)) cells)))
    (check-true (and e (string-contains? (cadddr e) "fg#1")))))
