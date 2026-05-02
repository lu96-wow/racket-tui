;; color-256.rkt - 256色颜色表
#lang racket
(require "../main.rkt")

(with-tui-nobuffer
    (screen-clear)
  (cursor-hide)

  ;; 标题
  (put-string "╔══════════════════════════════════════════════╗") (put-newline)
  (put-string "║          256 色颜色表 (256 Colors)          ║") (put-newline)
  (put-string "╚══════════════════════════════════════════════╝") (put-newline)
  (put-newline)

  ;; 系统色 0-15 (标准 ANSI 色 + 高亮色)
  (put-string "─── 系统色 (0-15) ───") (put-newline)
  (for ([row (in-range 0 2)])
    (for ([col (in-range 0 8)])
      (define n (+ (* row 8) col))
      (put-256-bg n (format " ~a " n))
      (when (= col 7) (put-newline))))
  (put-newline)

  ;; 216 色调色板 (16-231) - 6×6×6 RGB 立方体
  (put-string "─── 调色板 (16-231) 6×6×6 RGB 立方体 ───") (put-newline)
  (for ([g (in-range 0 6)])
    (put-string (format "G~a:" g))
    (for ([r (in-range 0 6)])
      (for ([b (in-range 0 6)])
        (define n (+ 16 (* 36 r) (* 6 g) b))
        (put-256-bg n "  ")))
    (put-newline))
  (put-newline)

  ;; 灰度色 232-255
  (put-string "─── 灰度色 (232-255) ───") (put-newline)
  (for ([n (in-range 232 256)])
    (put-256-bg n (format "~a" n)))
  (put-newline)
  (put-newline)

  ;; 前景色示例
  (put-string "─── 前景色示例 ───") (put-newline)
  (for ([n (in-range 0 256)])
    (put-256-fg n (format "~a" n))
    (put-string " ")
    (when (= (modulo (+ n 1) 32) 0) (put-newline)))
  (put-newline)

  (sleep 5))