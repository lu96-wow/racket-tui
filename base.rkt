;; base.rkt
#lang racket

(require ffi/unsafe racket/bytes "autoresources.rkt")

;; FFI
(define libc (ffi-lib #f))
(define tcgetattr (get-ffi-obj 'tcgetattr libc (_fun _int _pointer -> _int)))
(define tcsetattr (get-ffi-obj 'tcsetattr libc (_fun _int _int _pointer -> _int)))
(define isatty    (get-ffi-obj 'isatty    libc (_fun _int -> _int)))

;; 常量
(define STDIN_FILENO 0)
(define TCSAFLUSH 2)
(define TERMIOS-SIZE 60)
(define ICANON #x0002) (define ECHO   #x0008)
(define ISIG   #x0001) (define IEXTEN #x8000)
(define IXON   #x400)  (define OPOST  #x001)
(define VMIN 6)        (define VTIME 5)
(define LFLAG-OFFSET 12) (define IFLAG-OFFSET 0) (define OFLAG-OFFSET 4)

;; termios 字节操作
(define (make-termios) (make-bytes TERMIOS-SIZE 0))
(define (copy-termios src) (define dst (make-termios)) (bytes-copy! dst 0 src 0 TERMIOS-SIZE) dst)

(define (flag-ref t off)
  (for/fold ([v 0]) ([i (in-range 3 -1 -1)]) (+ (arithmetic-shift v 8) (bytes-ref t (+ off i)))))

(define (flag-set! t off v)
  (for ([i 4]) (bytes-set! t (+ off i) (bitwise-and v #xff)) (set! v (arithmetic-shift v -8))) t)

(define (lflag-ref t) (flag-ref t LFLAG-OFFSET))
(define (lflag-set! t v) (flag-set! t LFLAG-OFFSET v))
(define (iflag-ref t) (flag-ref t IFLAG-OFFSET))
(define (iflag-set! t v) (flag-set! t IFLAG-OFFSET v))
(define (oflag-ref t) (flag-ref t OFLAG-OFFSET))
(define (oflag-set! t v) (flag-set! t OFLAG-OFFSET v))

(define (set-vmin-vtime! t vmin vtime)
  (bytes-set! t (+ 17 VMIN) vmin) (bytes-set! t (+ 17 VTIME) vtime) t)

;; 输入线程
(define input-channel (make-channel))

(define (input-thread-start)
  (thread (λ () (let loop () (channel-put input-channel (read-byte)) (loop)))))

(define (input-thread-stop t) (kill-thread t))
(register-thread! 'input input-thread-start input-thread-stop)

;; 读取函数
(define (blocking-getc)    (channel-get input-channel))
(define (nonblocking-getc) (let ([v (channel-try-get input-channel)]) (if v v 'null)))

;; 终端模式
(define saved-terminal #f)
(define getc blocking-getc)

(define (terminal?) (not (zero? (isatty STDIN_FILENO))))

(define (enter-raw-mode!)
  (define t (make-termios))
  (tcgetattr STDIN_FILENO t)
  (set! saved-terminal (copy-termios t))
  (lflag-set! t (bitwise-and (lflag-ref t) (bitwise-not (bitwise-ior ICANON ECHO ISIG IEXTEN))))
  (iflag-set! t (bitwise-and (iflag-ref t) (bitwise-not IXON)))
  (oflag-set! t (bitwise-and (oflag-ref t) (bitwise-not OPOST)))
  (set-vmin-vtime! t 0 0)
  (tcsetattr STDIN_FILENO TCSAFLUSH t)
  (change-block))

(define (exit-raw-mode!)
  (when saved-terminal
    (tcsetattr STDIN_FILENO TCSAFLUSH saved-terminal)
    (set! saved-terminal #f)))

(define (change-block)   (set! getc blocking-getc))
(define (change-noblock) (set! getc nonblocking-getc))

(provide terminal? enter-raw-mode! exit-raw-mode!
         change-block change-noblock getc)