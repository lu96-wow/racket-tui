#lang racket

(require "lib.rkt"
         "key_data.rkt")

(define current-input-timeout (make-parameter -1))
(provide current-input-timeout)

(define (getch-with-short-timeout)
  (define original (current-input-timeout))
  (cond
    ;; 情况1: 当前是阻塞模式 (-1) → 需要临时设短超时
    [(= original -1)
     (timeout 50)
     (define k (getch))
     (timeout -1)  ; 恢复阻塞
     (if (= k -1) #f k)]

    ;; 情况2: 当前是非阻塞或有限超时 (0, 100, ...) → 直接读一次
    [else 
     (define k (getch))  ; 此时 getch 要么立即返回字符，要么返回 -1
     (if (= k -1) #f k)]))

;; 内部状态：保存最近一次解析出的 Unicode 字符串
(define last-unicode #f)
(define last-unicode-length 0)

;; 根据 UTF-8 首字节判断总字节数
(define (utf8-byte-length b)
  (cond
    [(<= b #x7F) 1]                     ; 0xxxxxxx
    [(<= b #xDF) 2]                     ; 110xxxxx
    [(<= b #xEF) 3]                     ; 1110xxxx
    [(<= b #xF7) 4]                     ; 11110xxx
    [else 1]))                          ; 无效，按单字节处理

;; 尝试从首字节 b 开始读取完整 UTF-8 序列并解码
(define (read-utf8-char b)
  (define len (utf8-byte-length b))
  (set! last-unicode-length len)
  (if (= len 1)
      #f  ; 不是多字节字符
      (let ([bytes-list (cons b (for/list ([i (- len 1)])
                                  (getch)))])
        (with-handlers ([exn:fail? (lambda (_) #f)])
          ;; 尝试解码为 UTF-8 字符串
          (bytes->string/utf-8 (list->bytes bytes-list))))))

(define (integer->key k)
  (set! last-unicode #f)
  (set! last-unicode-length 0)
  (cond
    ;; 超时
    [(= k -1) #f]

    ;; Ctrl 组合键
    [(and (>= k 1) (<= k 26))
     (string->symbol (format "ctrl-~a" (integer->char (+ k 64))))]
    [(= k 27)
     (let ([next (getch-with-short-timeout)])
       (if (and next (>= next 32) (<= next 126))
           (string->symbol (format "alt-~a" (integer->char next)))
           'esc))]
    
    [(= k 28) 'ctrl-backslash]
    [(= k 29) 'ctrl-right-bracket]
    [(= k 30) 'ctrl-caret]
    [(= k 31) 'ctrl-underscore]

    ;; 可打印 ASCII
    [(and (>= k 32) (<= k 126))
     (string->symbol (string (integer->char k)))]

    ;; 控制字符
    [(memq k '(10 13))
      'enter]
    [(= k 27)
      'esc]
    [(= k 9)
      'tab]
    [(= k 32)
      'space]
    [(memq k '(8 127))
      'backspace]

    ;; 功能键等（KEY_XXX >= 257）
    [(hash-ref KEYCODE->SYMBOL k #f)
     => (lambda (sym)
          sym)]

    ;; 检测 UTF-8 多字节起始字节（128–255）
    [(and (>= k 128) (<= k 255))
     (set! last-unicode (read-utf8-char k))
     'unicode]

    ;; 其他未知（包括续字节？理论上不应单独出现）
    [else
     (string->symbol (format "~a" k))]))

(define-syntax-rule (get-key)
  (integer->key (getch)))

;; 获取最近一次输入的 Unicode 字符串
(define (get-last-unicode)
  last-unicode)

(define (get-last-unicode-length)
  last-unicode-length)

(provide get-key integer->key get-last-unicode get-last-unicode-length)