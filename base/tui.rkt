#lang racket

(require "terminal/base.rkt"
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

(define (tui-init)
  (unless (terminal?) (error "tui-init: not a terminal"))
  (enter-raw-mode!)
  (init-newline-var)
  (resize-monitor-start)
  (use-color-auto!)
  (buffer-alt-enable)
  (enable-mouse!)
  (enable-bracketed-paste!))

(define (tui-init-no-buffer)
  (unless (terminal?) (error "tui-init: not a terminal"))
  (enter-raw-mode!)
  (init-newline-var)
  (resize-monitor-start)
  (use-color-auto!)
  (enable-mouse!)
  (enable-bracketed-paste!))

;; 无 buffer + 保留回显：适用需要实时读取按键同时终端显示输入的场景
(define (tui-init-no-buffer-echo)
  (unless (terminal?) (error "tui-init: not a terminal"))
  (enter-raw-mode-keep-echo!)
  (init-newline-var)
  (resize-monitor-start)
  (use-color-auto!)
  (enable-mouse!)
  (enable-bracketed-paste!))

;; dynamic-wind 保证 tui-exit 必定执行, resize 线程随进程退出自然回收
(define (tui-exit)
  (disable-bracketed-paste!)
  (disable-mouse!)
  (cursor-show)
  (style-reset)
  (buffer-alt-disable)
  (exit-raw-mode!)
  (reset-newline-var))

(define (tui-exit-no-buffer)
  (disable-bracketed-paste!)
  (disable-mouse!)
  (cursor-show)
  (style-reset)
  (exit-raw-mode!)
  (reset-newline-var))

;; 退出逻辑与 tui-exit-no-buffer 相同，exit-raw-mode! 恢复保存的 termios 即可
(define tui-exit-no-buffer-echo tui-exit-no-buffer)

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

(define-syntax-rule (with-tui body ...)
  (let ([exn #f])
    (dynamic-wind
     tui-init
     (λ ()
       (with-handlers ([exn:fail? (λ (e) (set! exn e))])
         body ...))
     (λ ()
       (tui-exit)
       (when exn
         (eprintf "Error: ~a\n" (exn-message exn))
         (raise exn))))))

(define-syntax-rule (with-tui-nobuffer body ...)
  (let ([exn #f])
    (dynamic-wind
     tui-init-no-buffer
     (λ ()
       (with-handlers ([exn:fail? (λ (e) (set! exn e))])
         body ...))
     (λ ()
       (tui-exit-no-buffer)
       (when exn
         (eprintf "Error: ~a\n" (exn-message exn))
         (raise exn))))))

(define-syntax-rule (with-tui-nobuffer-echo body ...)
  (let ([exn #f])
    (dynamic-wind
     tui-init-no-buffer-echo
     (λ ()
       (with-handlers ([exn:fail? (λ (e) (set! exn e))])
         body ...))
     (λ ()
       (tui-exit-no-buffer-echo)
       (when exn
         (eprintf "Error: ~a\n" (exn-message exn))
         (raise exn))))))

(provide tui-init tui-exit
         tui-init-no-buffer tui-exit-no-buffer
         tui-init-no-buffer-echo tui-exit-no-buffer-echo
         init-newline-var reset-newline-var
         with-tui with-tui-nobuffer with-tui-nobuffer-echo
         enable-mouse! disable-mouse!
         enable-bracketed-paste! disable-bracketed-paste!)