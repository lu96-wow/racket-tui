#lang racket

;; char 后端的生命周期 —— 与 base/tui.rkt 同名 API，但不碰 termios，
;; 只负责准备/清理当前 grid。

(require "screen/session.rkt"
         "screen/grid.rkt"
         "terminal/resize.rkt"
         "io/output.rkt"
         "io/output-color.rkt"
         "ansi/ansi-var.rkt")

(define (init-newline-var) (set-box! newline-var "\r\n"))
(define (reset-newline-var) (set-box! newline-var "\n"))

;; 尺寸来源是 current-screen-size（session.rkt 的 parameter），与 base 一致
;; 不带尺寸关键字。测试/调试需要固定尺寸时：
;;   (parameterize ([current-screen-size (cons rows cols)]) (with-tui thunk))
(define (char-init!)
  (screen-alt-disable!)                 ; 清掉上次会话可能残留的 alt 屏
  (define size (current-screen-size))
  (current-screen (make-grid (car size) (cdr size)))
  (frame-reset!)
  (init-newline-var)
  (use-color-auto!))

;; 与 base 的 tui-exit 一致：退出时恢复主屏（即便 body 出错时停在 alt）
(define (char-exit!)
  (screen-alt-disable!)
  (reset-newline-var))

;; ── 与 base 同名 ─────────────────────────────────────────

(define (tui-init) (char-init!))
(define (tui-exit) (char-exit!))
(define tui-init-no-buffer tui-init)
(define tui-exit-no-buffer tui-exit)
(define tui-init-no-buffer-echo tui-init)
(define tui-exit-no-buffer-echo tui-exit)

(define (with-tui thunk)
  (dynamic-wind char-init! thunk char-exit!))

(define (with-tui-nobuffer thunk) (with-tui thunk))
(define (with-tui-nobuffer-echo thunk) (with-tui thunk))

(define (enable-mouse!) (void))
(define (disable-mouse!) (void))
(define (enable-bracketed-paste!) (void))
(define (disable-bracketed-paste!) (void))

(provide tui-init tui-exit
         tui-init-no-buffer tui-exit-no-buffer
         tui-init-no-buffer-echo tui-exit-no-buffer-echo
         init-newline-var reset-newline-var
         with-tui with-tui-nobuffer with-tui-nobuffer-echo
         enable-mouse! disable-mouse!
         enable-bracketed-paste! disable-bracketed-paste!)
