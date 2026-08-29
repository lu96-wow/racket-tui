#lang racket

(require ffi/unsafe racket/bytes)

(unless (eq? 'linux
             (system-type 'os)) (error "only linux could use"))
;; ════════════════════════════════════════════════════════════════
;; FFI 绑定 — termios / isatty（Linux libc）
;;
;; 函数与常量在 Linux 上是固定的，直接硬编码，不再需要从 C 生成。
;; 旧的 env-build-base（编译 dump-termios.c）流程已移除。
;; ════════════════════════════════════════════════════════════════

(define libc (ffi-lib #f))
(define tcgetattr (get-ffi-obj 'tcgetattr libc (_fun _int _pointer -> _int)))
(define tcsetattr (get-ffi-obj 'tcsetattr libc (_fun _int _int _pointer -> _int)))
(define isatty (get-ffi-obj 'isatty libc (_fun _int -> _int)))

;; ── 常量（来源: 内核 asm-generic/termbits.h + glibc termios 布局）──
;; 以下标志位值在 Linux 所有主流架构（x86 / arm / aarch64 / riscv /
;; ppc / mips / sparc）上一致，由 asm-generic 头文件统一定义。
(define STDIN_FILENO 0)
(define TCSAFLUSH 2)
(define ICANON 2) (define ECHO 8)
(define ISIG 1) (define IEXTEN 32768)
(define IXON 1024) (define OPOST 1)
(define ICRNL 256) (define INLCR 64)
(define IGNCR 128) (define OCRNL 8)
(define ONLCR 4)
(define VMIN 6) (define VTIME 5)

;; ── struct termios 布局 ──
;; 布局: tcflag_t c_iflag, c_oflag, c_cflag, c_lflag  (各 4 字节)
;;       cc_t c_line (1 字节) + cc_t c_cc[NCCS]
;; 偏移: iflag=0, oflag=4, lflag=12, c_cc 起始=17 —— glibc 与 musl 一致
;; 大小: glibc = 60 (NCCS=32)；musl = 36 (NCCS=19)。
;;       固定用 60 对两者都安全：缓冲区不小于 libc 实际读写的字节数。
;; 例外: alpha 架构的 termios 布局不同（本项目不面向它）。
(define TERMIOS-SIZE 60)
(define IFLAG-OFFSET 0)
(define OFLAG-OFFSET 4)
(define LFLAG-OFFSET 12)
(define CC-OFFSET 17)

;; tcgetattr/tcsetattr 是 Linux 设置终端模式的唯一 API，必须传
;; 完整的 struct termios* 缓冲区；内核会读写整个结构体（与项目
;; 实际用到几个字段无关），因此缓冲区大小仍需 ≥ sizeof(struct termios)。

(define (make-termios) (make-bytes TERMIOS-SIZE 0))

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
  (bytes-set! t (+ CC-OFFSET VMIN) vmin) (bytes-set! t (+ CC-OFFSET VTIME) vtime) t)

;; ════════════════════════════════════════════════════════════════
;; sync 多路复用 — Racket 等价于 select(STDIN, resize_fd)
;; stdin 事件在此定义; resize 事件见 terminal/resize.rkt (signalfd)
;; 与调度器协作, green thread 可正常运行
;; ════════════════════════════════════════════════════════════════

(define (make-stdin-evt)
  (read-bytes-evt 1 (current-input-port)))

;; ════════════════════════════════════════════════════════════════
;; 终端模式管理
;;
;; 本项目只会修改 termios 的 4 个字段:
;;   lflag 的 ICANON/ECHO/ISIG/IEXTEN
;;   iflag 的 IXON/ICRNL/INLCR/IGNCR
;;   oflag 的 OPOST/OCRNL/ONLCR
;;   c_cc[VMIN] / c_cc[VTIME]
;; 因此只保存/还原这些字段，不需要保存整个 struct termios 快照。
;; ════════════════════════════════════════════════════════════════

(define saved-state #f) ; 最近一次 enter-raw-mode! 保存的字段, 或 #f

;; 读取当前 termios，返回 (缓冲区, 将被修改字段的原始值)
(define (read-raw-state)
  (define t (make-termios))
  (tcgetattr STDIN_FILENO t)
  (values t (list (lflag-ref t) (iflag-ref t) (oflag-ref t)
                  (bytes-ref t (+ CC-OFFSET VMIN))
                  (bytes-ref t (+ CC-OFFSET VTIME)))))

;; 把保存的字段写回缓冲区并应用
(define (apply-saved! t saved)
  (define-values (l i o vmin vtime) (apply values saved))
  (lflag-set! t l)
  (iflag-set! t i)
  (oflag-set! t o)
  (bytes-set! t (+ CC-OFFSET VMIN) vmin)
  (bytes-set! t (+ CC-OFFSET VTIME) vtime)
  (tcsetattr STDIN_FILENO TCSAFLUSH t))

(define (terminal?) (not (zero? (isatty STDIN_FILENO))))

(define (enter-raw-mode!)
  (define-values (t saved) (read-raw-state))
  (set! saved-state saved)
  (lflag-set! t (bitwise-and (lflag-ref t) (bitwise-not (bitwise-ior ICANON ECHO ISIG IEXTEN))))
  (iflag-set! t (bitwise-and (iflag-ref t) (bitwise-not (bitwise-ior IXON ICRNL INLCR IGNCR))))
  (oflag-set! t (bitwise-and (oflag-ref t) (bitwise-not (bitwise-ior OPOST OCRNL ONLCR))))
  (set-vmin-vtime! t 0 0)
  (tcsetattr STDIN_FILENO TCSAFLUSH t))

(define (exit-raw-mode!)
  (when saved-state
    ;; 重新读取当前状态，只把动过的字段改回原值，其余保持现状
    (define-values (t _) (read-raw-state))
    (apply-saved! t saved-state)
    (set! saved-state #f)))

;; 进入 raw 模式但保留回显 (ECHO)
;; 适用于需要实时读取按键但希望终端同时显示输入的场景
(define (enter-raw-mode-keep-echo!)
  (define-values (t saved) (read-raw-state))
  (set! saved-state saved)
  (lflag-set! t (bitwise-and (lflag-ref t) (bitwise-not (bitwise-ior ICANON ISIG IEXTEN))))
  (iflag-set! t (bitwise-and (iflag-ref t) (bitwise-not (bitwise-ior IXON ICRNL INLCR IGNCR))))
  (oflag-set! t (bitwise-and (oflag-ref t) (bitwise-not (bitwise-ior OPOST OCRNL ONLCR))))
  (set-vmin-vtime! t 0 0)
  (tcsetattr STDIN_FILENO TCSAFLUSH t))

;; 通用终端请求/回复 — 发请求后阻塞等待响应
;; 同时处理 raw 模式(VMIN=0 不等待)和非 raw 模式(行缓冲)的问题
(define (call-with-terminal-reply thunk #:vtime [vtime 1])
  (define-values (t saved) (read-raw-state))
  ;; 关行缓冲 + 回显，设 VMIN=1 阻塞等至少 1 字节
  (lflag-set! t (bitwise-and (lflag-ref t) (bitwise-not (bitwise-ior ICANON ECHO))))
  (set-vmin-vtime! t 1 vtime)
  (tcsetattr STDIN_FILENO TCSAFLUSH t)
  (define result (call-with-values thunk list))
  ;; 用同一缓冲区把保存的字段改回原值
  (apply-saved! t saved)
  (apply values result))

(provide terminal? enter-raw-mode! exit-raw-mode!
         enter-raw-mode-keep-echo!
         call-with-terminal-reply
         make-stdin-evt
         STDIN_FILENO)
