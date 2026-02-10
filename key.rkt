#lang racket

(require "lib.rkt"
         "key_data.rkt")

;; 内部状态：保存最近一次解析出的 Unicode 字符串
(define last-unicode #f)

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
  (if (= len 1)
      #f  ; 不是多字节字符
      (let ([bytes-list (cons b (for/list ([i (- len 1)])
                                  (getch)))])
        (with-handlers ([exn:fail? (lambda (_) #f)])
          ;; 尝试解码为 UTF-8 字符串
          (bytes->string/utf-8 (list->bytes bytes-list))))))

(define (integer->key k)
  (cond
    ;; 超时
    [(= k -1) #f]

    ;; 可打印 ASCII
    [(and (>= k 32) (<= k 126))
     (set! last-unicode #f)
     (string->symbol (string (integer->char k)))]

    ;; 控制字符
    [(memq k '(10 13))
     (set! last-unicode #f) 'enter]
    [(= k 27)
     (set! last-unicode #f) 'esc]
    [(= k 9)
     (set! last-unicode #f) 'tab]
    [(= k 32)
     (set! last-unicode #f) 'space]
    [(memq k '(8 127))
     (set! last-unicode #f) 'backspace]

    ;; 功能键等（KEY_XXX >= 257）
    [(hash-ref KEYCODE->SYMBOL k #f)
     => (lambda (sym)
          (set! last-unicode #f)
          sym)]

    ;; 检测 UTF-8 多字节起始字节（128–255）
    [(and (>= k 128) (<= k 255))
     (set! last-unicode (read-utf8-char k))
     'unicode]

    ;; 其他未知（包括续字节？理论上不应单独出现）
    [else
     (set! last-unicode #f)
     (string->symbol (format "~a" k))]))

(define-syntax-rule (get-key)
  (integer->key (getch)))

;; 新增：获取最近一次输入的 Unicode 字符串
(define (get-last-unicode)
  last-unicode)

(provide get-key integer->key get-last-unicode)