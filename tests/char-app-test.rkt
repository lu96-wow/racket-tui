#lang racket

;; char 后端：脚本输入 + 事件循环 + 帧钩子（无需 tty / FFI 终端）

(require rackunit
         "../char.rkt")

;; 与 base 一致：with-tui 不带尺寸关键字，尺寸走 current-screen-size
(define (with-sized-tui rows cols thunk)
  (parameterize ([current-screen-size (cons rows cols)])
    (with-tui thunk)))

(module+ test

  (test-case "push 各种 spec 形态"
    (char-input-clear!)
    (char-input-push! #\x 'enter
                      (key-event #\y (mods #t #f #f))
                      '(ctrl #"\x01" #f))
    (check-equal? (char-input-remaining) 4)
    (define evs (for/list ([_ 4]) (read-event)))
    (check-true (key-event? (list-ref evs 0)))
    (check-equal? (key-event-key (list-ref evs 0)) #\x)
    (check-equal? (key-event-key (list-ref evs 1)) 'enter)
    (check-true (mods-ctrl? (key-event-mods (list-ref evs 2))))
    (check-true (key-event? (list-ref evs 3)))
    (check-true (char-input-empty?))
    (char-input-close!)
    (check-true (char-input-exhausted?))
    (check-true (null-event? (read-event))))

  (test-case "read-event 默认阻塞，push 后才返回"
    (char-input-clear!)
    (define result (box #f))
    (thread (λ () (set-box! result (read-event))))
    (sleep 0.05)
    (check-false (unbox result))                 ; 仍在阻塞（不空转）
    (char-input-push! #\z)
    (sleep 0.05)
    (check-true (key-event? (unbox result)))
    (check-equal? (key-event-key (unbox result)) #\z))

  (test-case "完整事件循环：build-input + loop-input/stop"
    (define hits (box 0))
    (define result
      (with-sized-tui 6 20
       (λ ()
         (char-input-clear!)
         (char-input-push! #\a #\b 'up #\c)
         (char-input-close!)
         (define handler
           (build-input
            #:key (λ (k m) (when (char? k) (set-box! hits (add1 (unbox hits)))))
            #:up (λ () (set-box! hits (+ (unbox hits) 100)))))
         (loop-input/stop (char-input-exhausted?) handler)
         (unbox hits))))
    (check-equal? result 103)                 ; 3 个字符 + 1 次 up
    (check-true (char-input-empty?)))

  (test-case "帧钩子：flush! 触发快照，且默认去重"
    (define frames '())
    (parameterize ([current-frame-hook
                    (λ (g) (set! frames (cons (grid->text g) frames)))])
      (with-sized-tui 3 10
       (λ ()
         (screen-clear)
         (put-string "hi")
         (flush!)
         (flush!)                               ; 与上一帧相同 → 不触发
         (put-string "!"))))                     ; 未 flush
    (check-equal? (length frames) 1)
    (check-equal? (car frames) "hi\n\n"))

  (test-case "逐帧落盘 + 去重"
    (define path (make-temporary-file "charframe~a.txt"))
    (dynamic-wind
      void
      (λ ()
        (with-sized-tui 3 10
         (λ ()
           (screen-frame-log-enable! path)
           (screen-clear) (put-string "A") (flush!)
           (flush!)                             ; 与上一帧相同 → 去重
           (screen-clear) (put-string "B") (flush!)
           (screen-frame-log-disable!)))
        (define txt (file->string path))
        (check-true (string-contains? txt "── frame 1 ──"))
        (check-true (string-contains? txt "A"))
        (check-true (string-contains? txt "── frame 2 ──"))
        (check-true (string-contains? txt "B"))
        (check-equal? (regexp-match* #rx"── frame" txt) '("── frame" "── frame")))
      (λ () (when (file-exists? path) (delete-file path)))))

  (test-case "光标位置与局部属性查询"
    (with-sized-tui 5 12
     (λ ()
       (screen-clear)
       (put-at 3 5 "hi")
       (put-styled-at 1 1 'error "E")
       (define g (the-screen))
       ;; put-at 用 save/restore，光标回到之前位置
       (check-equal? (call-with-values (λ () (screen-cursor g)) list) '(0 0))
       (check-equal? (call-with-values (λ () (get-cursor)) list) '(1 1))
       (check-equal? (call-with-values (λ () (screen-size g)) list) '(5 12))
       ;; 局部属性
       (check-equal? (cell-text (screen-ref g 0 0)) "E")
       (check-equal? (cell-fg (screen-ref g 0 0)) '(idx 1))
       (check-equal? (cell-attrs (screen-ref g 0 0)) '(bold))
       (check-equal? (screen-style-at g 0 0) "fg#1 bold")
       (check-equal? (screen-style-at g 2 4) "")
       ;; 当前待写入属性
       (check-equal? (screen-current-style g) "")
       (put-256-fg-base 46)
       (check-equal? (screen-current-style g) "fg#46"))))

  (test-case "char-run：有界脚本 → 帧序列，不会无限输出"
    (define count (box 0))
    (define frames
      (char-run (list #\+ #\+ #\-)
                #:handle (λ (ev)
                           (when (key-event? ev)
                             (case (key-event-key ev)
                               [(#\+) (set-box! count (add1 (unbox count)))]
                               [(#\-) (set-box! count (sub1 (unbox count)))]
                               [else (void)])))
                #:render (λ ()
                           (put-bytes
                            (bytes-append
                             format-screen-clear
                             (format-cursor-move 1 1)
                             (format "count=~a" (unbox count)))))
                #:rows 3 #:cols 12))
    (check-equal? (length frames) 4)             ; 初始 + 3 个事件
    (check-equal? (unbox count) 1)
    (check-true (string-contains? (last frames) "count=1")))

  (test-case "字符图与按需属性同源"
    (define g
      (with-sized-tui 5 16
       (λ ()
         (screen-clear)
         (put-at 1 1 "OK")
         (put-styled-at 3 1 'error "bad")
         (the-screen))))
    (check-equal? (grid->text g) "OK\n\nbad\n\n")
    (check-not-false (member '(2 0 "b" "fg#1 bold")
                             (screen-styled-cells g)))))
