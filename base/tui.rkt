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
;; 异常自然向外传播（不再手动 catch + re-raise），因此 body 的
;; 错误总是会被调用方或默认错误处理器报告，不会静默吞掉。
(define (with-tui thunk)
  (dynamic-wind tui-init thunk (λ () (tui-exit))))

;; 不切换 alt 缓冲
(define (with-tui-nobuffer thunk)
  (dynamic-wind tui-init-no-buffer thunk (λ () (tui-exit-no-buffer))))

;; 不切换 alt 缓冲，保留终端回显
(define (with-tui-nobuffer-echo thunk)
  (dynamic-wind tui-init-no-buffer-echo thunk (λ () (tui-exit-no-buffer-echo))))

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
