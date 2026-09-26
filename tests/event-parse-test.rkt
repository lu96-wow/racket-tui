#lang racket

;; 输入解析回归测试（无需真实终端：用 pipe 伪造 stdin）
;;
;;   1. 带修饰键的滚轮不能被误判成按键（bit6 + 低 2 位掩码）
;;   2. 默认 xterm 编码下 Alt[+Ctrl]+键（ESC + 控制字节 / UTF-8）的还原
;;   3. char 脚本 spec 的 char → 命名键 归一化（与真实终端一致）

(require rackunit
         racket/port
         (prefix-in b: (file "../base/io/input.rkt"))
         (prefix-in be: (file "../base/io/event.rkt"))
         (prefix-in c: (file "../base-char/io/event.rkt")))

;; 把字节喂给解析器，取回一个规范化事件
(define (base-read1 bs)
  (define-values (in out) (make-pipe 4096))
  (write-bytes bs out)
  (close-output-port out)
  (parameterize ([current-input-port in])
    (let-values ([(t d m) (b:read-event/raw)])
      (be:normalize-event t d m))))

(define (key-mod ev)
  (list (be:key-event-key ev)
        (be:mods-ctrl? (be:key-event-mods ev))
        (be:mods-alt? (be:key-event-mods ev))))

(module+ test

  (test-case "滚轮：无修饰仍为 scroll"
    (define ev (base-read1 #"\e[<64;5;3M"))
    (check-true (be:mouse-event? ev))
    (check-equal? (be:mouse-event-action ev) 'scroll)
    (check-equal? (be:mouse-event-button ev) 'up))

  (test-case "滚轮 + 修饰键不能退化成按键（防回归）"
    ;; SGR: 64=上 65=下; +4=Shift +8=Alt +16=Ctrl
    (for ([case (list (cons #"\e[<80;5;3M" (list 'up #t #f #f))    ; Ctrl+上
                      (cons #"\e[<68;5;3M" (list 'up #f #f #t))    ; Shift+上
                      (cons #"\e[<73;5;3M" (list 'down #f #t #f))  ; Alt+下
                      (cons #"\e[<81;5;3M" (list 'down #t #f #f)))]) ; Ctrl+下
      (define ev (base-read1 (car case)))
      (define want (cdr case))
      (check-true (be:mouse-event? ev))
      (check-equal? (be:mouse-event-action ev) 'scroll)
      (check-equal? (be:mouse-event-button ev) (car want))
      (check-equal? (list (be:mods-ctrl? (be:mouse-event-mods ev))
                          (be:mods-alt? (be:mouse-event-mods ev))
                          (be:mods-shift? (be:mouse-event-mods ev)))
                    (cdr want))))

  (test-case "普通按键不受影响"
    (define ev (base-read1 #"\e[<0;5;3M"))
    (check-equal? (be:mouse-event-action ev) 'press)
    (check-equal? (be:mouse-event-button ev) 'left))

  (test-case "默认编码：Ctrl+Alt+字母 (ESC ^X)"
    (check-equal? (key-mod (base-read1 #"\e\x18")) (list #\X #t #t)))

  (test-case "默认编码：Alt+特殊键"
    (check-equal? (key-mod (base-read1 #"\e\r")) (list 'enter #f #t))
    (check-equal? (key-mod (base-read1 #"\e\t")) (list 'tab #f #t))
    (check-equal? (key-mod (base-read1 #"\e\x7f")) (list 'backspace #f #t)))

  (test-case "Alt + 非 ASCII 字符 (ESC + UTF-8)"
    (check-equal? (key-mod (base-read1 (bytes-append #"\e" #"\xc3\xa9")))
                  (list #\é #f #t)))

  (test-case "char 脚本 spec：char 经 byte->key 归一化"
    (define hits (box '()))
    (define handler
      (c:build-input
       #:text (λ (s) (set-box! hits (cons (list 'text s) (unbox hits))))
       #:tab (λ () (set-box! hits (cons '(tab) (unbox hits))))
       #:enter (λ () (set-box! hits (cons '(enter) (unbox hits))))
       #:backspace (λ () (set-box! hits (cons '(backspace) (unbox hits))))
       #:escape (λ () (set-box! hits (cons '(escape) (unbox hits))))
       #:space (λ () (set-box! hits (cons '(space) (unbox hits))))))
    (c:char-input-clear!)
    (c:char-input-push! #\tab #\return #\newline #\backspace #\u001b #\space)
    (c:char-input-close!)
    (let loop ()
      (unless (c:char-input-exhausted?)
        (handler (c:read-event))
        (loop)))
    (check-equal? (reverse (unbox hits))
                  '((tab) (enter) (enter) (backspace) (escape) (space)))))
