#lang racket

;; ════════════════════════════════════════════════════════════════
;; base/io/color-policy.rkt —— features → 颜色 registry 策略
;;
;; 根据 features 选择样式 registry（唯一的档位选择入口）：
;;   truecolor → 256 档（命名样式到 256 为止；真彩走直接的 put-rgb-* 通道）
;;   256       → 256 档
;;   16 / 其他 → 16 档
;;
;; 只调用 output-color.rkt 的 setter，不改 registry 本身。
;; ════════════════════════════════════════════════════════════════

(require "output-color.rkt"
         "../terminal/features.rkt"
         "../terminal/session.rkt")

(provide use-color-from-features!
         use-color-auto!)

;; 应用 features 里的色深档位；返回实际选用的档位（便于测试/日志）。
(define (use-color-from-features! f)
  (define tier (features-color f))
  (case tier
    [(truecolor 256) (use-256color!)]
    [else (use-16color!)])
  tier)

;; [char-compat] 与 tui/char 端同名同语义：按当前会话 features 自动选档位。
;; 提供它只为让使用 use-color-auto! 的调用点在两端都能编译/运行；
;; 会话外（current-features = default-features）等价于 16 色。
(define (use-color-auto!)
  (use-color-from-features! (current-features)))
