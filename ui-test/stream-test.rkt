#lang racket

(require "../ui/main.rkt")

(define blocks (box (list "")))
(define full-text
  "Hello World! 你好世界!\nThis is a streaming test.\nEach character appears one by one.\n\nThe end.")
(define pos (box 0))

;; 背景线程: 每 50ms 追加一个字符
(thread
 (λ ()
   (let loop ()
     (sleep 0.05)
     (when (< (unbox pos) (string-length full-text))
       (define ch (substring full-text (unbox pos) (add1 (unbox pos))))
       (set-box! pos (add1 (unbox pos)))
       (define c (string-ref ch 0))
       (define bs (unbox blocks))
       (if (char=? c #\newline)
           (set-box! blocks (append bs (list "")))
           (set-box! blocks (append (drop-right bs 1)
                                    (list (string-append (last bs) ch)))))
       (loop)))))

(define output (make-output #:blocks blocks))

(define specs
  (list
   (list (make-text #:text "┌────┤ Streaming Test ├────────────┐" #:style 'title) 1 1 34 1)
   (list (make-text #:text (λ () (format "│ chars: ~a/~a~a"
                                         (unbox pos) (string-length full-text)
                                         (make-string (max 0 (- 14
                                           (string-length (number->string (unbox pos)))
                                           (string-length (number->string (string-length full-text)))))
                                                      #\space))) #:style 'info) 1 2 34 1)
   (list (make-text #:text "└────────────────────────────────┘" #:style 'title) 1 3 34 1)
   (list output 1 4 34 12)))

(run-app specs #:noblock? #t)
