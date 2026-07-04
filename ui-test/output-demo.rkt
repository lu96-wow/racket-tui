#lang racket
;; ui-test/output-demo.rkt — 单线程示例：创建 output，写内容，run-app-noblock 启动
;;   不阻塞读取输入 → 按 q 退出
;;   动态更新需配合 thread（见 output-test.rkt）

(require "../ui/main.rkt"
         "../base/io/output-color.rkt")

;; ── 样式 ──
(style-define! 'panel (color256-bg 235) (color256-fg 250))
(style-define! 'error-style (color256-bg 88) (color256-fg 231) attr-bold)
(style-define! 'ok-style (color256-bg 28) (color256-fg 231) attr-bold)
(style-define! 'warn-style (color256-bg 94) (color256-fg 231) attr-bold)

;; ── 创建 output ──
(define-values (out append! append-styled! clear!
                    fold! begin-fold! end-fold! toggle-fold!
                    scroll-end!)
  (make-output #:max-lines 500 #:style 'panel))

;; ── 写满 max-lines 看性能 ──
(append! "╔══════════════════════════════╗\n")
(append! "║    Output Perf Test         ║\n")
(append! "╚══════════════════════════════╝\n")

;; styled 输出
(append-styled! "[ERROR] connection timeout\n" 'error-style)
(append-styled! "[OK]    retry scheduled     \n" 'ok-style)
(append-styled! "[WARN]  high memory usage   \n" 'warn-style)

;; 折叠块
(define err-bid (begin-fold! "Errors" 'error-style))
(for ([i (in-range 1 21)])
  (append-styled! (format "error ~a: stack overflow in module-~a.rkt\n" i i) 'panel))
(end-fold!)

(define warn-bid (begin-fold! "Warnings" 'warn-style))
(for ([i (in-range 1 15)])
  (append-styled! (format "warning ~a: deprecated API usage\n" i) 'panel))
(end-fold!)

;; 填充到 max-lines
(displayln "--- filling to max-lines ---")
(time
 (for ([i (in-range 1 451)])
   (append! (format "log ~a: all systems operational, no issues detected\n" i))))

;; ── 启动 ──
(run-app-noblock
  (out 1 1 50 20))
