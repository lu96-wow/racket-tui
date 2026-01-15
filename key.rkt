#lang racket

(require "lib.rkt"
         "key_data.rkt")

(define (integer->key k)
  (cond
    ;; 超时：ncurses getch 返回 -1
    [(= k -1) #f]

    ;; 可打印 ASCII
    [(and (>= k 32) (<= k 126))
     (string->symbol (string (integer->char k)))]

    ;; 控制字符
    [(memq k '(10 13)) 'enter]
    [(= k 27) 'esc]
    [(= k 9)  'tab]
    [(= k 32) 'space]
    [(memq k '(8 127)) 'backspace]

    ;; 查表：功能键、鼠标、窗口调整等
    [(hash-ref KEYCODE->SYMBOL k #f) => values]

    ;; 未知键
    [else
     (string->symbol (format "key-~a" k))]))

(define-syntax-rule (get-key)
  (integer->key (getch)))

(provide get-key integer->key)