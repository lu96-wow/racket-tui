#lang racket
(require ffi/unsafe ffi/unsafe/port)

;; ════════════════════════════════════════════════════════════════
;; 窗口大小获取 + SIGWINCH 事件
;;
;; 不再用子线程轮询 ioctl(TIOCGWINSZ)。改用 Linux signalfd:
;;   1. sigprocmask 阻塞 SIGWINCH
;;   2. signalfd 把信号变成文件描述符
;;   3. unsafe-fd->evt + handle-evt 得到一个 Racket sync 事件
;;
;; 这样 read-event 的 sync 可以统一等 stdin 和 resize 事件,
;; 与调度器协作, 零轮询、零 CPU。
;;
;; 约束: sigprocmask 只作用于当前 OS 线程, 因此启动时校验
;; /proc/self/task 下所有线程都已阻塞 SIGWINCH。若不满足则 fail-fast,
;; 而不是静默丢事件。之后新建的线程会继承创建线程的掩码, 自然满足。
;; ════════════════════════════════════════════════════════════════

(define libc (ffi-lib #f))
(define ioctl       (get-ffi-obj 'ioctl       libc (_fun _int _int _pointer -> _int)))
(define sigprocmask (get-ffi-obj 'sigprocmask libc (_fun _int _pointer _pointer -> _int)))
(define signalfd    (get-ffi-obj 'signalfd    libc (_fun _int _pointer _int -> _int)))
(define read-fd     (get-ffi-obj 'read        libc (_fun _int _pointer _int64 -> _int64)))
(define close-fd    (get-ffi-obj 'close       libc (_fun _int -> _int)))

(define TIOCGWINSZ #x5413)
(define STDOUT_FILENO 1)

(define SIG_BLOCK 0)
(define SIG_SETMASK 2)
(define SIGWINCH 28)

;; Linux x86_64/glibc 的 sigset_t 为 128 字节 (1024 位)。
;; SIGWINCH=28 → 位索引 27 → 第 3 字节的第 3 位。
(define SIGNAL-MASK-SIZE 128)

(define (make-sigwinch-mask)
  (define mask (make-bytes SIGNAL-MASK-SIZE 0))
  (bytes-set! mask 3 8)
  mask)

(define resize-sfd #f)
(define old-sigmask #f)

;; 校验当前进程内所有 OS 线程都阻塞了 SIGWINCH。
;; 纯 Racket 实现（读 /proc，无 C）。读取失败返回 #f。
(define (all-threads-block-sigwinch?)
  (with-handlers ([exn:fail? (λ (e) #f)])
    (for/and ([tid (map (λ (d) (string->number (path->string d)))
                        (directory-list "/proc/self/task"))])
      (and tid
           (let* ([status (file->string (format "/proc/self/task/~a/status" tid))]
                  [m (regexp-match #rx"SigBlk:[ \t]*([0-9a-fA-F]+)" status)])
             (and m (bitwise-bit-set? (string->number (cadr m) 16) 27)))))))

(define (get-window-size (fd STDOUT_FILENO))
  (define ws (make-bytes 8 0))
  (if (= (ioctl fd TIOCGWINSZ ws) -1)
      (values #f #f)
      (values (+ (bytes-ref ws 0) (arithmetic-shift (bytes-ref ws 1) 8))
              (+ (bytes-ref ws 2) (arithmetic-shift (bytes-ref ws 3) 8)))))

(define (resize-monitor-start)
  (unless resize-sfd
    (define mask (make-sigwinch-mask))
    (define old (make-bytes SIGNAL-MASK-SIZE 0))
    (sigprocmask SIG_BLOCK mask old)
    (unless (all-threads-block-sigwinch?)
      (sigprocmask SIG_SETMASK old #f)
      (error 'resize-monitor-start
             (string-append
              "无法确认所有 OS 线程都阻塞 SIGWINCH，signalfd 可能收不到 resize 事件。"
              "请在 with-tui/tui-init 之前不要创建 futures/unsafe-call-in-os-thread 等 OS 线程，"
              "并确保 /proc 可读。")))
    (define sfd (signalfd -1 mask 0))
    (when (negative? sfd)
      (sigprocmask SIG_SETMASK old #f)
      (error 'resize-monitor-start "signalfd failed"))
    (set! old-sigmask old)
    (set! resize-sfd sfd)))

(define (resize-monitor-stop)
  (when resize-sfd
    (close-fd resize-sfd)
    (set! resize-sfd #f))
  (when old-sigmask
    (sigprocmask SIG_SETMASK old-sigmask #f)
    (set! old-sigmask #f)))

(define (drain-resize-signal!)
  (when resize-sfd
    (define buf (make-bytes 128 0))
    (read-fd resize-sfd buf 128)))

;; 返回一个可被 sync 等待的事件; 触发后读取窗口大小并返回 (rows . cols)
(define (make-resize-evt)
  (resize-monitor-start)
  (handle-evt
   (unsafe-fd->evt resize-sfd 'read #f)
   (λ (_)
     (drain-resize-signal!)
     (let-values ([(r c) (get-window-size)])
       (cons r c)))))

(provide get-window-size
         resize-monitor-start resize-monitor-stop
         make-resize-evt)
