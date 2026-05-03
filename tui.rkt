#lang racket

(require "base.rkt"
         "autoresources.rkt"
         "output.rkt"
         "output-color.rkt")

(define (tui-init)
  (unless (terminal?) (error "tui-init: not a terminal"))
  (enter-raw-mode!)
  (start-thread! 'input)
  (start-thread! 'resize)
  (buffer-alt-enable)
  ;; 初始化鼠标和括号粘贴支持
  (enable-mouse!)
  (enable-bracketed-paste!))

(define (tui-init-no-buffer)
  (unless (terminal?) (error "tui-init: not a terminal"))
  (enter-raw-mode!)
  (start-thread! 'input)
  (start-thread! 'resize)
  ;; 初始化鼠标和括号粘贴支持
  (enable-mouse!)
  (enable-bracketed-paste!))

(define (tui-exit)
  ;; 先禁用鼠标和括号粘贴
  (disable-bracketed-paste!)
  (disable-mouse!)
  (cursor-show)
  (style-reset)
  (buffer-alt-disable)
  (stop-all!)
  (exit-raw-mode!))

(define (tui-exit-no-buffer)
  ;; 先禁用鼠标和括号粘贴
  (disable-bracketed-paste!)
  (disable-mouse!)
  (cursor-show)
  (style-reset)
  (stop-all!)
  (exit-raw-mode!))

;; 鼠标支持
(define (enable-mouse!)
  (display "\x1b[?1000h")  ; 基础鼠标跟踪
  (display "\x1b[?1002h")  ; 按钮事件跟踪（拖拽时）
  (display "\x1b[?1006h")  ; SGR 扩展坐标模式
  (flush-output))

(define (disable-mouse!)
  (display "\x1b[?1006l")
  (display "\x1b[?1002l")
  (display "\x1b[?1000l")
  (flush-output))

;; 括号粘贴支持
(define (enable-bracketed-paste!)
  (display "\x1b[?2004h")
  (flush-output))

(define (disable-bracketed-paste!)
  (display "\x1b[?2004l")
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

(provide tui-init tui-exit
         tui-init-no-buffer tui-exit-no-buffer
         with-tui with-tui-nobuffer
         enable-mouse! disable-mouse!
         enable-bracketed-paste! disable-bracketed-paste!)