#lang racket

;; ════════════════════════════════════════════════════════════════
;; base/terminal/session.rkt —— 会话级能力状态
;;
;; features 是"当前这次会话已确认的能力"。tui-init 探测后写入，
;; tui-exit 恢复成进入前的值（支持嵌套 with-tui，LIFO）。
;;
;; 用 parameter 而不是全局变量：可被 parameterize 覆盖，测试友好。
;; 注意：base 是单线程 TUI；多线程并发会话不受支持（同 base 的其余状态）。
;; ════════════════════════════════════════════════════════════════

(require "features.rkt")

(provide current-features
         current-screen-size)

(define current-features (make-parameter default-features))

;; [char-compat] 会话尺寸 (rows . cols)。此参数是为兼容 tui/char 端而存在的：
;; char 用它给内存 grid 定尺寸，用户可 parameterize 成固定尺寸（测试 / 调试）；
;; base 侧未覆盖（仍是默认 24×80）时 tui-init 会填入真实终端尺寸（见 base/tui.rkt）。
;; base 的实际输出仍由终端决定，此参数的作用是让同一份代码在 tui / tui/char
;; 间切换时同名、同语义、能编译。
(define current-screen-size (make-parameter (cons 24 80)))
