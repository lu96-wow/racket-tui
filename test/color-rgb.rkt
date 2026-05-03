;; color-truecolor.rkt - 真彩色颜色表
#lang racket
(require "../main.rkt")

(with-tui-nobuffer
    (cursor-hide)

  ;; 标题
  (put-string "╔══════════════════════════════════════════════╗") (put-newline)
  (put-string "║        真彩色颜色表 (True Color)           ║") (put-newline)
  (put-string "╚══════════════════════════════════════════════╝") (put-newline)
  (put-newline)

  ;; 检查真彩色是否工作
  (put-string "真彩色测试: ")
  (put-rgb-bg 255 0 0 "  ")
  (put-rgb-bg 0 255 0 "  ")
  (put-rgb-bg 0 0 255 "  ")
  (put-string " <- 应看到红绿蓝三个色块")
  (put-newline)
  (put-newline)

  ;; 色相环 - 360度色相渐变
  (put-string "─── 色相环 (Hue 0°-360°) ───") (put-newline)
  (for ([h (in-range 0 360 5)])
    (define sector (floor (/ h 60)))
    (define frac (- (/ h 60) sector))
    (define t (inexact->exact (round (* 255 frac))))
    (define-values (r g b)
      (case (modulo sector 6)
        [(0) (values 255 t 0)]
        [(1) (values (- 255 t) 255 0)]
        [(2) (values 0 255 t)]
        [(3) (values 0 (- 255 t) 255)]
        [(4) (values t 0 255)]
        [(5) (values 255 0 (- 255 t))]
        [else (values 255 255 255)]))
    (put-rgb-fg r g b "█")
    (when (= (modulo (+ h 5) 360) 0) (put-newline)))
  (put-newline)

  ;; 红色渐变
  (put-string "─── 红色渐变 (R 0→255, G=0, B=0) ───") (put-newline)
  (for ([r (in-range 0 256 4)])
    (put-rgb-bg r 0 0 " "))
  (put-string " 255") (put-newline)
  (put-newline)

  ;; 绿色渐变
  (put-string "─── 绿色渐变 (R=0, G 0→255, B=0) ───") (put-newline)
  (for ([g (in-range 0 256 4)])
    (put-rgb-bg 0 g 0 " "))
  (put-string " 255") (put-newline)
  (put-newline)

  ;; 蓝色渐变
  (put-string "─── 蓝色渐变 (R=0, G=0, B 0→255) ───") (put-newline)
  (for ([b (in-range 0 256 4)])
    (put-rgb-bg 0 0 b " "))
  (put-string " 255") (put-newline)
  (put-newline)

  ;; RGB 立方体切面
  (put-string "─── RGB 平面 (G=128 固定) ───") (put-newline)
  (put-string "     ")
  (for ([b (in-range 0 256 32)])
    (put-string (format "~a   " (if (< b 100) (format " ~a" b) b))))
  (put-newline)
  (put-string "     ")
  (for ([b (in-range 0 256 32)]) (put-string "────"))
  (put-newline)
  (for ([r (in-range 0 256 16)])
    (put-string (format "~a " (if (< r 100) (if (< r 10) (format "  ~a" r) (format " ~a" r)) r)))
    (for ([b (in-range 0 256 16)])
      (put-rgb-bg r 128 b "  "))
    (put-newline))
  (put-newline)

  ;; 灰度渐变
  (put-string "─── 灰度渐变 (0→255) ───") (put-newline)
  (for ([g (in-range 0 256 3)])
    (put-rgb-bg g g g (if (< g 128) " " " ")))
  (put-string " 255") (put-newline)
  (put-newline)

  ;; 暖色系渐变
  (put-string "─── 暖色系渐变 ───") (put-newline)
  (for ([i (in-range 0 256 4)])
    (put-rgb-bg (min 255 (+ 128 i)) (min 255 (+ 64 i)) (min 255 i) " "))
  (put-newline)
  (put-newline)

  ;; 冷色系渐变
  (put-string "─── 冷色系渐变 ───") (put-newline)
  (for ([i (in-range 0 256 4)])
    (put-rgb-bg (min 255 i) (min 255 (+ 64 i)) (min 255 (+ 128 i)) " "))
  (put-newline)
  (put-newline)

  (sleep 5))