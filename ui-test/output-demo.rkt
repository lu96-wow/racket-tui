#lang racket
;; ui-test/output-demo.rkt — 单线程示例：创建 output，写内容，run-app-noblock 启动
;;   不阻塞读取输入 → 按 q 退出
;;   动态更新需配合 thread（见 output-test.rkt）

(require "../ui/main.rkt"
         "../base/io/output-color.rkt")

;; ── 样式 ──
(style-define! 'panel       (color256-bg 235) (color256-fg 250))
(style-define! 'error-style (color256-bg  88) (color256-fg 231) attr-bold)
(style-define! 'ok-style    (color256-bg  28) (color256-fg 231) attr-bold)
(style-define! 'warn-style  (color256-bg  94) (color256-fg 231) attr-bold)

;; ── 创建 output ──
(define-values (out append! append-styled! clear!
                    fold! begin-fold! end-fold! toggle-fold!
                    scroll-end!)
  (make-output #:max-lines 200 #:style 'panel))

;; ── 写内容 ──
(append! "╔══════════════════════════════╗\n")
(append! "║    Output Demo              ║\n")
(append! "╚══════════════════════════════╝\n")
(append! "\n")

;; 普通文本
(for ([i (in-range 1 6)])
  (append! (format "log ~a: everything normal\n" i)))

;; styled 输出
(append! "\n")
(append-styled! "[ERROR] disk full\n"       'error-style)
(append-styled! "[OK]    retry scheduled\n" 'ok-style)
(append-styled! "[WARN]  latency spike\n"   'warn-style)
(append! "\n")

;; 折叠块 1 — 错误详情
(define err-bid (begin-fold! "Error Details" 'error-style))
(for ([i (in-range 1 8)])
  (append-styled! (format "  trace ~a: /src/module-~a.rkt:42\n" i i) 'panel))
(end-fold!)

(append! "\n")

;; 折叠块 2 — 警告列表
(define warn-bid (begin-fold! "Warning Summary" 'warn-style))
(for ([i (in-range 1 5)])
  (append-styled! (format "  warning ~a: threshold exceeded\n" i) 'panel))
(end-fold!)

(append! "\n")
(append! "─── ready, press q to quit ───\n")

;; ── 启动 ──
(run-app-noblock
  (out 1 1 50 20))
