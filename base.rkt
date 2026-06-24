#lang racket

(require ffi/unsafe racket/bytes)

;; ════════════════════════════════════════════════════════════════
;; FFI 绑定 — ncurses 风格: select() + self-pipe 替代线程
;; ════════════════════════════════════════════════════════════════

(define libc (ffi-lib #f))
(define tcgetattr (get-ffi-obj 'tcgetattr libc (_fun _int _pointer -> _int)))
(define tcsetattr (get-ffi-obj 'tcsetattr libc (_fun _int _int _pointer -> _int)))
(define isatty    (get-ffi-obj 'isatty    libc (_fun _int -> _int)))
(define select-c  (get-ffi-obj 'select    libc (_fun _int _pointer _pointer _pointer _pointer -> _int)))
(define read-c    (get-ffi-obj 'read      libc (_fun _int _pointer _int -> _int)))
(define write-c   (get-ffi-obj 'write     libc (_fun _int _pointer _int -> _int)))
(define pipe-c    (get-ffi-obj 'pipe      libc (_fun _pointer -> _int)))
(define fcntl-c   (get-ffi-obj 'fcntl     libc (_fun _int _int _int -> _int)))

;; select / fcntl 常量
(define FD_SETSIZE 1024)
(define FD_BYTES (/ FD_SETSIZE 8))  ; 128 bytes on Linux x86_64
(define F_SETFL 4)
(define O_NONBLOCK 2048)

;; termios 常量
(define STDIN_FILENO 0)
(define TCSAFLUSH 2)
(define TERMIOS-SIZE 60)
(define ICANON #x0002) (define ECHO   #x0008)
(define ISIG   #x0001) (define IEXTEN #x8000)
(define IXON   #x400)  (define OPOST  #x001)
(define ICRNL  #x100)  (define INLCR  #x040)
(define IGNCR  #x080)  (define OCRNL  #x008)
(define ONLCR  #x004)
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

;; ════════════════════════════════════════════════════════════════
;; fd_set 操作 (纯 Racket, 避免依赖 glibc 内部 __FD_* 符号)
;; ════════════════════════════════════════════════════════════════

(define (make-fd-set) (make-bytes FD_BYTES 0))

(define (fd-set! fds fd)
  (when (< fd FD_SETSIZE)
    (define byte-idx (quotient fd 8))
    (define bit-idx  (remainder fd 8))
    (bytes-set! fds byte-idx
                (bitwise-ior (bytes-ref fds byte-idx)
                             (arithmetic-shift 1 bit-idx)))))

(define (fd-isset? fds fd)
  (and (< fd FD_SETSIZE)
       (let* ([byte-idx (quotient fd 8)]
              [bit-idx  (remainder fd 8)]
              [mask     (arithmetic-shift 1 bit-idx)])
         (not (zero? (bitwise-and (bytes-ref fds byte-idx) mask))))))

;; ════════════════════════════════════════════════════════════════
;; self-pipe — resize 线程写 1 byte → select 唤醒主线程
;; ════════════════════════════════════════════════════════════════

(define resize-read-fd  #f)
(define resize-write-fd #f)

(define (resize-pipe-init!)
  (define pipe-buf (make-bytes 8 0))
  (when (= (pipe-c pipe-buf) -1)
    (error "resize-pipe-init!: pipe() failed"))
  (define (le32 idx)
    (+ (bytes-ref pipe-buf idx)
       (arithmetic-shift (bytes-ref pipe-buf (+ idx 1)) 8)
       (arithmetic-shift (bytes-ref pipe-buf (+ idx 2)) 16)
       (arithmetic-shift (bytes-ref pipe-buf (+ idx 3)) 24)))
  (set! resize-read-fd  (le32 0))
  (set! resize-write-fd (le32 4))
  ;; write 端非阻塞, 避免 resize 线程被满管道阻塞
  (fcntl-c resize-write-fd F_SETFL O_NONBLOCK))

(define (resize-pipe-cleanup!)
  (set! resize-read-fd #f)
  (set! resize-write-fd #f))

;; resize 线程调用: 写 1 字节到 pipe 唤醒 select
(define (resize-notify!)
  (when resize-write-fd
    (write-c resize-write-fd (bytes 1) 1)))

(define (drain-resize-pipe!)
  (when resize-read-fd
    (define buf (make-bytes 64 0))
    (let loop ()
      (when (> (read-c resize-read-fd buf 64) 0)
        (loop)))))

;; ════════════════════════════════════════════════════════════════
;; 核心读取 — ncurses 风格: select() 统一等 stdin + resize pipe
;; ════════════════════════════════════════════════════════════════

;; 返回 (values 'byte <integer>) | (values 'resize #f) | (values 'eof #f)
;; 阻塞直到有事件, 零 CPU 占用
(define (select-read)
  (unless resize-read-fd
    (error "select-read: resize pipe not initialized"))
  (define maxfd (+ 1 (max STDIN_FILENO resize-read-fd)))
  (let loop ()
    (define readfds (make-fd-set))
    (fd-set! readfds STDIN_FILENO)
    (fd-set! readfds resize-read-fd)
    (let ([ret (select-c maxfd readfds #f #f #f)])
      (cond [(= ret -1) (loop)]                    ; EINTR, retry
            [(fd-isset? readfds resize-read-fd)
             (drain-resize-pipe!)
             (values 'resize #f)]
            [(fd-isset? readfds STDIN_FILENO)
             (define buf (make-bytes 1 0))
             (define n (read-c STDIN_FILENO buf 1))
             (cond [(= n 1) (values 'byte (bytes-ref buf 0))]
                   [(= n 0) (values 'eof #f)]
                   [else    (loop)])]              ; EINTR
            [else (loop)]))))

;; 内部使用: stdin-only 上阻塞读取 (多字节解析时不检查 resize)
(define (read-byte-stdin)
  (let loop ()
    (define readfds (make-fd-set))
    (fd-set! readfds STDIN_FILENO)
    (let ([ret (select-c (+ STDIN_FILENO 1) readfds #f #f #f)])
      (cond [(= ret -1) (loop)]
            [(fd-isset? readfds STDIN_FILENO)
             (define buf (make-bytes 1 0))
             (define n (read-c STDIN_FILENO buf 1))
             (cond [(= n 1) (bytes-ref buf 0)]
                   [else (loop)])]
            [else (loop)]))))

;; 非阻塞模式: select() timeout={0,0}, 立即返回
;; 返回 'timeout 表示无事件, 用于动画帧循环
(define (select-read-nonblock)
  (unless resize-read-fd
    (error "select-read-nonblock: resize pipe not initialized"))
  (define maxfd (+ 1 (max STDIN_FILENO resize-read-fd)))
  (define readfds (make-fd-set))
  (fd-set! readfds STDIN_FILENO)
  (fd-set! readfds resize-read-fd)
  ;; struct timeval { long tv_sec; long tv_usec } = {0, 0}
  (define tv (make-bytes 16 0))
  (let ([ret (select-c maxfd readfds #f #f tv)])
    (cond [(= ret -1) (values 'timeout #f)]
          [(= ret 0)  (values 'timeout #f)]
          [(fd-isset? readfds resize-read-fd)
           (drain-resize-pipe!)
           (values 'resize #f)]
          [(fd-isset? readfds STDIN_FILENO)
           (define buf (make-bytes 1 0))
           (define n (read-c STDIN_FILENO buf 1))
           (cond [(= n 1) (values 'byte (bytes-ref buf 0))]
                 [else    (values 'timeout #f)])]
          [else (values 'timeout #f)])))

;; ════════════════════════════════════════════════════════════════
;; 终端模式管理
;; ════════════════════════════════════════════════════════════════

(define saved-terminal #f)

(define (terminal?) (not (zero? (isatty STDIN_FILENO))))

(define (enter-raw-mode!)
  (define t (make-termios))
  (tcgetattr STDIN_FILENO t)
  (set! saved-terminal (copy-termios t))
  (lflag-set! t (bitwise-and (lflag-ref t) (bitwise-not (bitwise-ior ICANON ECHO ISIG IEXTEN))))
  (iflag-set! t (bitwise-and (iflag-ref t) (bitwise-not (bitwise-ior IXON ICRNL INLCR IGNCR))))
  (oflag-set! t (bitwise-and (oflag-ref t) (bitwise-not (bitwise-ior OPOST OCRNL ONLCR))))
  (set-vmin-vtime! t 0 0)
  (tcsetattr STDIN_FILENO TCSAFLUSH t))

(define (exit-raw-mode!)
  (when saved-terminal
    (tcsetattr STDIN_FILENO TCSAFLUSH saved-terminal)
    (set! saved-terminal #f)))

;; ════════════════════════════════════════════════════════════════
;; 导出
;; ════════════════════════════════════════════════════════════════

(provide terminal? enter-raw-mode! exit-raw-mode!
         ;; 新 API → ncurses 风格
         resize-pipe-init! resize-pipe-cleanup! resize-notify!
         select-read select-read-nonblock read-byte-stdin
         STDIN_FILENO)