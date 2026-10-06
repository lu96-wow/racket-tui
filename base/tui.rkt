#lang racket

(require "terminal/base.rkt"
         "terminal/resize.rkt"
         "io/input.rkt"
         "io/output.rkt"
         "io/output-color.rkt"
         "ansi/ansi-var.rkt")

;; 进入 raw 模式后 OPOST/ONLCR 被关闭，换行需手动 \r\n
(define (init-newline-var)
  (set-box! newline-var "\r\n"))

;; 退出 raw 模式后恢复普通换行（终端 ONLCR 会自动补 \r）
(define (reset-newline-var)
  (set-box! newline-var "\n"))

;; ── 初始化 ─────────────────────────────────────────────────
;; 若初始化中途失败（如 resize-monitor-start 报错），先尽力回滚
;; 已修改的终端状态，再重新抛出原始错误，避免终端卡在 raw 模式。
;; tui-exit* 全部幂等，未开始的步骤调用它是安全的。
(define (tui-init)
  (unless (terminal?) (error "tui-init: not a terminal"))
  (with-handlers ([exn? (λ (e) (tui-exit) (raise e))])
    (enter-raw-mode!)
    (init-newline-var)
    (resize-monitor-start)
    (use-color-auto!)
    (buffer-alt-enable)
    (enable-mouse!)
    (enable-bracketed-paste!)))

(define (tui-init-no-buffer)
  (unless (terminal?) (error "tui-init: not a terminal"))
  (with-handlers ([exn? (λ (e) (tui-exit-no-buffer) (raise e))])
    (enter-raw-mode!)
    (init-newline-var)
    (resize-monitor-start)
    (use-color-auto!)
    (enable-mouse!)
    (enable-bracketed-paste!)))

;; 无 buffer + 保留回显：适用需要实时读取按键同时终端显示输入的场景
(define (tui-init-no-buffer-echo)
  (unless (terminal?) (error "tui-init: not a terminal"))
  (with-handlers ([exn? (λ (e) (tui-exit-no-buffer-echo) (raise e))])
    (enter-raw-mode-keep-echo!)
    (init-newline-var)
    (resize-monitor-start)
    (use-color-auto!)
    (enable-mouse!)
    (enable-bracketed-paste!)))

;; ── 清理 ─────────────────────────────────────────────────
;; 单个清理步骤的防御性包装：
;;   - 某一步失败不中断后续清理（终端尽量恢复完整）
;;   - 不抛出异常，避免掩盖 body 抛出的原始错误
;;   - 失败以 warning 形式输出，保证可见
(define (cleanup-step name thunk)
  (with-handlers ([exn? (λ (e)
                          (eprintf "tui-exit: ~a failed: ~a\n"
                                   name (exn-message e)))])
    (thunk)))

(define (tui-exit)
  (cleanup-step "disable-bracketed-paste!" disable-bracketed-paste!)
  (cleanup-step "disable-mouse!" disable-mouse!)
  (cleanup-step "cursor-show" cursor-show)
  (cleanup-step "style-reset" style-reset)
  (cleanup-step "buffer-alt-disable" buffer-alt-disable)
  (cleanup-step "exit-raw-mode!" exit-raw-mode!)
  (cleanup-step "resize-monitor-stop" resize-monitor-stop)
  (cleanup-step "reset-newline-var" reset-newline-var))

(define (tui-exit-no-buffer)
  (cleanup-step "disable-bracketed-paste!" disable-bracketed-paste!)
  (cleanup-step "disable-mouse!" disable-mouse!)
  (cleanup-step "cursor-show" cursor-show)
  (cleanup-step "style-reset" style-reset)
  (cleanup-step "exit-raw-mode!" exit-raw-mode!)
  (cleanup-step "resize-monitor-stop" resize-monitor-stop)
  (cleanup-step "reset-newline-var" reset-newline-var))

;; 退出逻辑与 tui-exit-no-buffer 相同，exit-raw-mode! 恢复保存的 termios 即可
(define tui-exit-no-buffer-echo tui-exit-no-buffer)

;; ── with-tui 系列（函数版）──────────────────────────────────
;; 用 dynamic-wind 保证 body 无论正常返回还是抛出异常都执行清理。
;;
;; 关键：Racket 的默认错误处理器在 dynamic-wind 的 after-thunk 之前运行。
;; 若让 body 的异常直接向外冒，错误会先被打印到【仍在 alt 缓冲 + raw 模式】
;; 的终端上，随后 tui-exit 的 buffer-alt-disable 切回主屏，刚打印的错误
;; 连同 alt 屏一起被丢弃 —— 用户什么都看不到。
;;
;; 因此下面在 body 外层接住任何 raise，先让 dynamic-wind 走完清理
;; （切回主屏、退出 raw 模式），再在会话外原样重新抛出。这样无论
;; 调用方还是默认错误处理器接手，报错都出现在已恢复的主屏上。
;; 多返回值按与 body 相同的 values 协议透传。
;;
;; call-with-source-registry：为本次会话建立事件源注册表，
;; 会话内 (on-source evt proc) 注册的源会被 read-event 的 sync 自动带上。
(define (call-with-tui-lifecycle init cleanup thunk)
  (define tagged
    (dynamic-wind
     init
     (λ ()
       (with-handlers ([(λ (_) #t) (λ (e) (list #f e))])
         (call-with-values thunk (λ vals (cons #t vals)))))
     cleanup))
  (if (car tagged)
      (apply values (cdr tagged))
      (raise (cadr tagged))))

(define (with-tui thunk)
  (call-with-source-registry
   (λ () (call-with-tui-lifecycle tui-init tui-exit thunk))))

;; 不切换 alt 缓冲
(define (with-tui-nobuffer thunk)
  (call-with-source-registry
   (λ () (call-with-tui-lifecycle tui-init-no-buffer tui-exit-no-buffer thunk))))

;; 不切换 alt 缓冲，保留终端回显
(define (with-tui-nobuffer-echo thunk)
  (call-with-source-registry
   (λ () (call-with-tui-lifecycle tui-init-no-buffer-echo tui-exit-no-buffer-echo thunk))))

;; 鼠标支持
(define (enable-mouse!)
  (display MOUSE-ENABLE-BASIC)   ; 基础鼠标跟踪
  (display MOUSE-ENABLE-BUTTON)  ; 按钮事件跟踪（拖拽时）
  (display MOUSE-ENABLE-SGR)     ; SGR 扩展坐标模式
  (flush-output))

(define (disable-mouse!)
  (display MOUSE-DISABLE-SGR)
  (display MOUSE-DISABLE-BUTTON)
  (display MOUSE-DISABLE-BASIC)
  (flush-output))

;; 括号粘贴支持
(define (enable-bracketed-paste!)
  (display PASTE-ENABLE)
  (flush-output))

(define (disable-bracketed-paste!)
  (display PASTE-DISABLE)
  (flush-output))

(provide tui-init tui-exit
         tui-init-no-buffer tui-exit-no-buffer
         tui-init-no-buffer-echo tui-exit-no-buffer-echo
         init-newline-var reset-newline-var
         with-tui with-tui-nobuffer with-tui-nobuffer-echo
         enable-mouse! disable-mouse!
         enable-bracketed-paste! disable-bracketed-paste!)
