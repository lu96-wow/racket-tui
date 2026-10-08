#lang racket

;; ════════════════════════════════════════════════════════════════
;; base/tui.rkt —— TUI 生命周期（按探测到的能力门控）
;;
;; init：先进入 raw 模式（探测前提），再用 terminal-support 查询终端能力，
;; 经 features-of 做纯决策，只启用"已确认支持"的功能；alt buffer 同样是
;; 门控项。能力的启用/禁用由 feature-plan.rkt 的动作表驱动
;; （声明顺序启用、逆序退出、引用计数、skip）。
;;
;; 顺序：
;;   0 terminal? → 1 raw → 2 newline → 3 probe → 4 features
;;   → 5 保存/设置 current-features 与 current-key-protocol → 6 颜色 registry
;;   → 7 resize → 8 plan(alt → mouse → paste，均按能力)
;; 退出：plan 逆序禁用 → cursor-show/style-reset → exit-raw
;;   → resize-stop → reset-newline → 恢复 features / current-key-protocol
;;
;; current-key-protocol（输入解码协议）由本会话保存/恢复。
;; ════════════════════════════════════════════════════════════════

(require "terminal/base.rkt"
         "terminal/resize.rkt"
         "terminal/probe.rkt"
         "terminal/features.rkt"
         "terminal/feature-plan.rkt"
         "terminal/session.rkt"
         "io/input.rkt"
         "io/output.rkt"
         "io/output-color.rkt"
         "io/color-policy.rkt"
         "ansi/ansi-var.rkt")

;; 进入 raw 模式后 OPOST/ONLCR 被关闭，换行需手动 \r\n
(define (init-newline-var)
  (set-box! newline-var "\r\n"))

;; 退出 raw 模式后恢复普通换行（终端 ONLCR 会自动补 \r）
(define (reset-newline-var)
  (set-box! newline-var "\n"))

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

;; ── 能力 → 启用/禁用的统一控制表 ──
;; 声明顺序 = 启用顺序，退出逆序；applicable? 来自 features。
(define feature-plan
  (list (faction 'alt-screen features-alt-screen? buffer-alt-enable buffer-alt-disable 0)
        (faction 'mouse      features-mouse?      enable-mouse!  disable-mouse!  0)
        (faction 'paste      features-paste?      enable-bracketed-paste!
                                                   disable-bracketed-paste! 0)))

;; ── 非能力门控的会话状态 ──
(define session-resize? #f)
(define session-newline? #f)
(define saved-features default-features)
(define saved-key-protocol 'ansi)

;; ── 初始化/清理 ─────────────────────────────────────────────
;; 单步清理的防御性包装：
;;   - 某一步失败不中断后续清理（终端尽量恢复完整）
;;   - 不抛出异常，避免掩盖 body 抛出的原始错误
;;   - 失败以 warning 形式输出，保证可见
(define (cleanup-step name thunk)
  (with-handlers ([exn? (λ (e)
                          (eprintf "tui-exit: ~a failed: ~a\n"
                                   name (exn-message e)))])
    (thunk)))

;; 若初始化中途失败，先尽力回滚已修改的终端状态，再重新抛出原始错误，
;; 避免终端卡在 raw 模式。tui-exit 幂等，未开始的步骤调用它是安全的。
(define (init-lifecycle! enter! #:alt? [alt? #t])
  (unless (terminal?) (error "tui-init: not a terminal"))
  ;; 先保存外层状态，保证即使 enter! 抛错也能正确恢复
  (set! saved-features (current-features))
  (set! saved-key-protocol (current-key-protocol))
  (with-handlers ([exn? (λ (e) (tui-exit) (raise e))])
    (enter!)
    (init-newline-var) (set! session-newline? #t)

    (define caps (probe-caps))                 ; 探测（异常已降级为 #f）
    (define f (features-of caps))              ; 纯决策
    (current-features f)
    (use-color-from-features! f)               ; 只选 registry，无 I/O

    (resize-monitor-start) (set! session-resize? #t)
    ;; alt / mouse / paste：只启用已确认支持者；no-buffer 变体 skip alt
    (plan-enable! feature-plan f #:skip (if alt? '() '(alt-screen)))))

(define (tui-init)              (init-lifecycle! enter-raw-mode! #:alt? #t))
(define (tui-init-no-buffer)    (init-lifecycle! enter-raw-mode! #:alt? #f))
(define (tui-init-no-buffer-echo)
  (init-lifecycle! enter-raw-mode-keep-echo! #:alt? #f))

;; 退出严格逆序；幂等；部分失败不中断
(define (tui-exit)
  (plan-disable! feature-plan
                 #:on-error (λ (a e)
                              (eprintf "tui-exit: disable ~a failed: ~a\n"
                                       (faction-label a) (exn-message e))))
  (cleanup-step "cursor-show" cursor-show)
  (cleanup-step "style-reset" style-reset)
  (cleanup-step "exit-raw-mode!" exit-raw-mode!)
  (when session-resize?
    (cleanup-step "resize-monitor-stop" resize-monitor-stop)
    (set! session-resize? #f))
  (when session-newline?
    (cleanup-step "reset-newline-var" reset-newline-var)
    (set! session-newline? #f))
  ;; 恢复进入前的会话状态
  (current-key-protocol saved-key-protocol)
  (current-features saved-features))

;; no-buffer 变体共用同一 exit（alt 从未开启，plan 计数为 0 自然跳过）
(define tui-exit-no-buffer tui-exit)
(define tui-exit-no-buffer-echo tui-exit)

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

(provide tui-init tui-exit
         tui-init-no-buffer tui-exit-no-buffer
         tui-init-no-buffer-echo tui-exit-no-buffer-echo
         init-newline-var reset-newline-var
         with-tui with-tui-nobuffer with-tui-nobuffer-echo
         enable-mouse! disable-mouse!
         enable-bracketed-paste! disable-bracketed-paste!)
