#lang racket

;; ════════════════════════════════════════════════════════════════
;; base/terminal/features.rkt —— 能力 → 功能特性的唯一决策点
;;
;; 输入是 terminal-support 的 `caps`（纯数据），输出一个 features 结构体。
;; 本模块是**纯函数、总函数、无 I/O**：给定同样的 caps 永远得到同样的结论。
;;
;; 保守规则（"可靠"就来自这里）：
;;   · 未探测 / 未回复 / unknown 一律当作「不支持」
;;   · color 的 'unknown 归一到 '16（最安全档）
;;   · 绝不读 $TERM 猜测
;;
;; 注意：caps 里只有「被查询过」的模式才有结论。features-of 假定调用方
;; 用覆盖这些模式的探测表（terminal-support 的 'standard profile 已包含
;; mouse / paste / screen / sync / keyboard）。没查到的模式一律按不支持处理。
;; ════════════════════════════════════════════════════════════════

(require "../../terminal-support/main.rkt")

(provide (struct-out features)
         features-of
         default-features)

;; color        : '16 | '256 | 'truecolor
;; mouse?       : SGR 鼠标可用（1006 + 至少一种跟踪模式）
;; paste?       : 括号粘贴 2004 可用
;; alt-screen?  : 备用屏 1049 可用
;; kitty-keys?  : kitty 键盘协议可用（CSI ? u 有回复）
;; sync?        : 同步输出 2026 可用
(struct features (color mouse? paste? alt-screen? kitty-keys? sync?)
  #:transparent)

;; 最保守的一组：无颜色（16）、其余全关。
(define default-features
  (features '16 #f #f #f #f #f))

(define (mode-available? caps mode)
  (and caps (caps-mode-available? caps mode)))

(define (features-of caps)
  (cond
    [(not (caps? caps)) default-features]
    [else
     (features
      ;; 色深：terminal-support 已把 OSC/XTGETTCAP/COLORTERM/TERM/DA1 揉成一个符号；
      ;; 这里只做归一：'unknown → '16。
      (let ([lvl (caps-color-level caps)])
        (case lvl
          [(truecolor) 'truecolor]
          [(256) '256]
          [else '16]))
      ;; SGR 鼠标：必须有 1006（否则 base 的 SGR 解析对不上），且至少一种跟踪模式。
      (and (mode-available? caps 1006)
           (or (mode-available? caps 1000)
               (mode-available? caps 1002)
               (mode-available? caps 1003)))
      (mode-available? caps 2004)
      (mode-available? caps 1049)
      ;; kitty flags 回复 0 也表示「支持」（只是未置任何 flag），故判 #f。
      (not (eq? (caps-kitty-flags caps) #f))
      (mode-available? caps 2026))]))
