#lang racket

(require ffi/unsafe racket/bytes)

;; ════════════════════════════════════════════════════════════════
;; FFI 绑定 — 仅 termios (快速 syscall, 非阻塞等待)
;; 事件多路复用用 Racket 原生 sync + read-bytes-evt (与调度器协作)
;; ════════════════════════════════════════════════════════════════

(define libc (ffi-lib #f))
(define tcgetattr (get-ffi-obj 'tcgetattr libc (_fun _int _pointer -> _int)))
(define tcsetattr (get-ffi-obj 'tcsetattr libc (_fun _int _int _pointer -> _int)))
(define isatty (get-ffi-obj 'isatty libc (_fun _int -> _int)))

(define STDIN_FILENO 0)
(define TCSAFLUSH 2)
(define TERMIOS-SIZE 60)
(define ICANON 2) (define ECHO 8)
(define ISIG 1) (define IEXTEN 32768)
(define IXON 1024) (define OPOST 1)
(define ICRNL 256) (define INLCR 64)
(define IGNCR 128) (define OCRNL 8)
(define ONLCR 4)
(define VMIN 6) (define VTIME 5)
(define LFLAG-OFFSET 12) (define IFLAG-OFFSET 0) (define OFLAG-OFFSET 4)

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
;; sync 多路复用 — Racket 等价于 select(STDIN, resize_fd)
;; 与调度器协作, green thread 可正常运行
;; ════════════════════════════════════════════════════════════════

(define (make-stdin-evt)
  (read-bytes-evt 1 (current-input-port)))

(define resize-channel (make-channel))

(define (resize-notify! data)
  (channel-put resize-channel data))

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

;; 通用终端请求/回复 — 发请求后阻塞等待响应clear
;; 同时处理 raw 模式(VMIN=0 不等待)和非 raw 模式(行缓冲)的问题
(define (call-with-terminal-reply thunk #:vtime [vtime 1])
  (define t (make-termios))
  (tcgetattr STDIN_FILENO t)
  (define saved (copy-termios t))
  ;; 关行缓冲 + 回显，设 VMIN=1 阻塞等至少 1 字节
  (lflag-set! t (bitwise-and (lflag-ref t) (bitwise-not (bitwise-ior ICANON ECHO))))
  (set-vmin-vtime! t 1 vtime)
  (tcsetattr STDIN_FILENO TCSAFLUSH t)
  (define result (call-with-values thunk list))
  (tcsetattr STDIN_FILENO TCSAFLUSH saved)
  (apply values result))

(provide terminal? enter-raw-mode! exit-raw-mode!
         call-with-terminal-reply
         make-stdin-evt resize-channel resize-notify!
         STDIN_FILENO)