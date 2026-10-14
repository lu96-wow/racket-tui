#lang racket

;; 当前字符屏（grid）的会话状态。
;; 所有输出都会作用到 (the-screen) 返回的这块 grid 上。

(require "grid.rkt"
         "render.rkt"
         "history.rkt")

(provide current-screen current-screen-size the-screen call-with-screen
         screen-alt-enable! screen-alt-disable! screen-alt-active?
         current-frame-hook current-frame-dedup? frame-end! frame-reset!)

;; 屏幕尺寸（行 . 列），无真实终端时的默认尺寸
(define current-screen-size (make-parameter (cons 24 80)))

;; 当前 grid；#f 表示尚未创建
(define current-screen (make-parameter #f))

(define (the-screen)
  (or (current-screen)
      (let ([g (make-grid (car (current-screen-size))
                          (cdr (current-screen-size)))])
        (current-screen g)
        g)))

(define (call-with-screen g thunk)
  (parameterize ([current-screen g]) (thunk)))

;; ── 备用缓冲（与 base 的 alt screen 语义对齐）──────────────
;; base 把 alt buffer 切给终端；char 用第二块 grid 模拟：
;; enable 时记住主屏并切到全新 alt 屏，disable 时切回主屏，
;; 因此主屏内容在 alt 期间不被破坏（== base 的 ESC[?1049h/l）。
(define screen-alt? (make-parameter #f))
(define saved-main-screen (box #f))

(define (screen-alt-active?) (screen-alt?))

(define (screen-alt-enable!)
  (unless (screen-alt?)
    (set-box! saved-main-screen (the-screen))
    (screen-alt? #t))
  ;; 每次 enable 都换一张全新的 alt 屏（对齐 ESC[?1049h 的清屏语义）
  (define size (current-screen-size))
  (define alt (make-grid (car size) (cdr size)))
  (set-grid-alt-active?! alt #t)
  (current-screen alt))

(define (screen-alt-disable!)
  (when (screen-alt?)
    (define main (unbox saved-main-screen))
    (set-grid-alt-active?! main #f)
    (current-screen main)
    (set-box! saved-main-screen #f)
    (screen-alt? #f)))

;; 帧钩子：每当一次绘制完成（flush!）时，用当前 grid 调用它。
;; 默认去重：与上一帧**视觉状态完全相同**（文本 + 颜色 + 属性）的帧不再触发，
;; 避免不阻塞循环里“没变也在一直输出”。注意只有颜色变化也算变化（文本去重
;; 会把它误判为没变，所以这里比的是整块 cells）。用 current-frame-dedup? 关闭。
(define current-frame-hook (make-parameter #f))
(define current-frame-dedup? (make-parameter #t))
(define last-frame-grid (box #f))

(define (frame-reset!)
  (set-box! last-frame-grid #f)
  (history-clear!))

(define (frame-end!)
  (define g (the-screen))
  (define dedup? (current-frame-dedup?))
  (define prev (unbox last-frame-grid))
  (unless (and dedup? prev (grid-equal? prev g))
    (when dedup? (set-box! last-frame-grid (grid-copy g)))
    ;; 历史与钩子独立：即使没设 current-frame-hook，也保留帧快照（信息不丢）
    (history-push! g)
    (when (current-frame-hook) ((current-frame-hook) g))))
