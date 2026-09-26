#lang racket
(require ffi/unsafe ffi/unsafe/port
         "platform.rkt")

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
;;
;; 同一进程内可重入: resize-monitor-start/stop 带引用计数, 支持嵌套
;; with-tui; 只有计数 0→1 时才真正创建 signalfd, 1→0 时才真正关闭。
;; 注意: 多个「并发」事件循环仍会共享同一个 signalfd, 一个循环 drain
;; 后另一个循环会丢事件; 同一终端本就只能有一个前台 TUI, 该场景不
;; 受支持 (嵌套是安全的)。
;; ════════════════════════════════════════════════════════════════

(define libc (ffi-lib #f))
(define ioctl       (get-ffi-obj 'ioctl       libc (_fun _int _int _pointer -> _int)))
(define sigprocmask (get-ffi-obj 'sigprocmask libc (_fun _int _pointer _pointer -> _int)))
(define signalfd    (get-ffi-obj 'signalfd    libc (_fun _int _pointer _int -> _int)))
(define read-fd     (get-ffi-obj 'read        libc (_fun _int _pointer _intptr -> _intptr)))
(define close-fd    (get-ffi-obj 'close       libc (_fun _int -> _int)))

(define TIOCGWINSZ #x5413)
(define STDOUT_FILENO 1)

(define SIG_BLOCK 0)
(define SIG_SETMASK 2)
(define SIGWINCH 28)

;; Linux glibc 的 sigset_t 为 128 字节 (1024 位)。
;; 若目标平台不是 glibc, 请按实际 sigset_t 大小调整 (musl 同为 128)。
(define SIGNAL-MASK-SIZE 128)

;; SFD_NONBLOCK 避免 drain 时因 fd 就绪状态竞争而阻塞;
;; SFD_CLOEXEC 避免 fd 泄漏给 exec 出来的子进程。
(define SFD_NONBLOCK #x800)
(define SFD_CLOEXEC  #x80000)

;; 由信号编号动态计算 sigset_t 中的字节/位, 不再硬编码位偏移。
(define (make-sigwinch-mask)
  (define bit (sub1 SIGWINCH))
  (define mask (make-bytes SIGNAL-MASK-SIZE 0))
  (bytes-set! mask (quotient bit 8) (arithmetic-shift 1 (remainder bit 8)))
  mask)

(define resize-sfd #f)
(define old-sigmask #f)
;; start/stop 配对计数: 支持嵌套 with-tui, 0→1 才真正创建, 1→0 才真正关闭
(define resize-users 0)

;; sigprocmask 封装: 失败时立即报错, 避免错误恢复路径用零掩码误恢复。
(define (sigprocmask/check how set old)
  (define r (sigprocmask how set old))
  (when (negative? r)
    (error 'resize-monitor "sigprocmask failed (how=~a)" how))
  r)

;; 是否做「全线程 SIGWINCH 掩码」校验（需要读 /proc/<pid>/status）。
;;   - Android/Termux 的 SELinux 不给 app 域 proc:file read（AOSP 只有
;;     `allow domain proc:dir r_dir_perms`），/proc/self/task/<tid>/status
;;     必然 EACCES，校验会恒为 'unknown 并 fail-fast。此时退回到只做
;;     sigprocmask（新线程继承掩码），不再中断启动。
;;   - 可用 TUI_RESIZE_PROC_CHECK=0/1 显式覆盖。
(define (proc-check-enabled?)
  (define v (getenv "TUI_RESIZE_PROC_CHECK"))
  (cond
    [(member v '("0" "false" "no")) #f]
    [(member v '("1" "true" "yes")) #t]
    [(termux?) #f]
    [else #t]))

;; ── /proc 线程掩码校验 ──────────────────────────────────────
;; 返回 'ok（全部阻塞）、'unblocked（发现未阻塞线程）、'unknown（/proc 不可读）
(define (thread-sigwinch-state tid)
  (define status
    (with-handlers ([exn:fail? (λ (e) #f)])
      (file->string (format "/proc/self/task/~a/status" tid))))
  (cond
    [(not status) 'unknown]
    [else
     (define m (regexp-match #rx"SigBlk:[ \t]*([0-9a-fA-F]+)" status))
     (cond
       [(not m) 'unknown]
       [(bitwise-bit-set? (string->number (cadr m) 16) (sub1 SIGWINCH)) 'ok]
       [else 'unblocked])]))

(define (worst-thread-state a b)
  (define (rank s) (case s [(ok) 0] [(unknown) 1] [(unblocked) 2]))
  (if (> (rank b) (rank a)) b a))

(define (check-sigwinch-mask-all-threads)
  (define tids
    (with-handlers ([exn:fail? (λ (e) #f)])
      (for/list ([d (directory-list "/proc/self/task")])
        (string->number (path->string d)))))
  (cond
    [(not tids) 'unknown]
    [else
     (for/fold ([state 'ok]) ([tid (in-list tids)])
       (if (not tid)
           state
           (worst-thread-state state (thread-sigwinch-state tid))))]))

(define (get-window-size (fd STDOUT_FILENO))
  (define ws (make-bytes 8 0))
  (if (= (ioctl fd TIOCGWINSZ ws) -1)
      (values #f #f)
      (values (+ (bytes-ref ws 0) (arithmetic-shift (bytes-ref ws 1) 8))
              (+ (bytes-ref ws 2) (arithmetic-shift (bytes-ref ws 3) 8)))))

;; 真正创建 signalfd（幂等，内部用）
(define (resize-monitor-start!)
  (unless resize-sfd
    (define mask (make-sigwinch-mask))
    (define old (make-bytes SIGNAL-MASK-SIZE 0))
    (sigprocmask/check SIG_BLOCK mask old)
    (define state (if (proc-check-enabled?)
                      (check-sigwinch-mask-all-threads)
                      'skipped))
    (unless (memq state '(ok skipped))
      (sigprocmask/check SIG_SETMASK old #f)
      (error 'resize-monitor-start
             (case state
               [(unblocked)
                (string-append
                 "检测到存在未阻塞 SIGWINCH 的 OS 线程, signalfd 可能收不到 resize 事件。"
                 "请在 with-tui/tui-init 之前不要创建 futures/unsafe-call-in-os-thread 等 OS 线程。")]
               [else
                (string-append
                 "无法通过 /proc/self/task 校验所有 OS 线程的 SIGWINCH 掩码"
                 "（/proc 不可读?）。为避免静默丢失 resize 事件, 启动失败。")])))
    (define sfd (signalfd -1 mask (bitwise-ior SFD_NONBLOCK SFD_CLOEXEC)))
    (when (negative? sfd)
      (sigprocmask/check SIG_SETMASK old #f)
      (error 'resize-monitor-start "signalfd failed"))
    (set! old-sigmask old)
    (set! resize-sfd sfd)))

;; 真正关闭 signalfd（幂等，内部用）
(define (resize-monitor-stop!)
  (when resize-sfd
    ;; 先从 unsafe-fd->evt 的全局缓存移除, 再关闭 fd, 避免缓存残留
    (unsafe-fd->evt resize-sfd 'remove #f)
    (close-fd resize-sfd)
    (set! resize-sfd #f))
  (when old-sigmask
    (sigprocmask/check SIG_SETMASK old-sigmask #f)
    (set! old-sigmask #f)))

;; 带引用计数的启动: 支持嵌套 with-tui; 只有 0→1 才真正创建
(define (resize-monitor-start)
  (when (zero? resize-users)
    (resize-monitor-start!))
  (set! resize-users (add1 resize-users)))

;; 带引用计数的停止: 1→0 才真正关闭; 计数已为 0 时仍会尝试关闭
;; (resize-monitor-stop! 幂等), 以清理 make-resize-evt 懒启动的监控。
(define (resize-monitor-stop)
  (when (positive? resize-users)
    (set! resize-users (sub1 resize-users)))
  (when (zero? resize-users)
    (resize-monitor-stop!)))

;; 确保监控存在（懒启动，供 make-resize-evt 使用，不改变引用计数）
(define (resize-monitor-ensure!)
  (resize-monitor-start!))

(define (drain-resize-signal!)
  (when resize-sfd
    (define buf (make-bytes 128 0))
    (read-fd resize-sfd buf 128)))

;; 返回一个可被 sync 等待的事件; 触发后读取窗口大小并返回 (rows . cols)
(define (make-resize-evt)
  (resize-monitor-ensure!)
  (handle-evt
   (unsafe-fd->evt resize-sfd 'read #f)
   (λ (_)
     (drain-resize-signal!)
     (let-values ([(r c) (get-window-size)])
       ;; ioctl 失败时 get-window-size 返回 #f；此时不投递非法 resize 事件，
       ;; 由 read-event/raw 归一为 null-event
       (and r c (cons r c))))))

(provide get-window-size
         resize-monitor-start resize-monitor-stop
         make-resize-evt)
