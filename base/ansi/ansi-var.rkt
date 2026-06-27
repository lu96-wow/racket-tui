#lang racket

;; ════════════════════════════════════════════════════════════════
;; ANSI / 终端相关常量和可变运行时变量
;; ════════════════════════════════════════════════════════════════

;; ─── 运行时变量（box 化，可在运行时切换）───

;; 换行序列
;; 默认 "\n"：普通（非 raw）模式下终端 ONLCR 会自动把 \n 转成 \r\n
;; 进入 raw 模式后由 tui.rkt 的 init-newline-var 设为 "\r\n"
;; （raw 模式关闭了 OPOST/ONLCR，需手动回车）
(define newline-var (box "\n"))

(define ansi-source-row 1)
(define ansi-source-col 1)

;; ─── ASCII 控制字符 ───

(define TAB 9)           ; Tab
(define LF 10)           ; Line Feed
(define CR 13)           ; Carriage Return
(define ESC 27)          ; Escape
(define SPACE 32)        ; Space
(define BACKSPACE 8)     ; Backspace (^H)
(define DELETE 127)      ; Delete

;; ASCII 字符范围
(define ASCII-DIGIT-START 48)    ; '0'
(define ASCII-DIGIT-END 57)      ; '9'
(define ASCII-PRINTABLE-START 32)
(define ASCII-PRINTABLE-END 126)

;; CSI 序列字符
(define CSI-OPEN 91)     ; '['
(define CSI-SS3 79)      ; 'O'
(define CSI-FINAL-START 64)   ; '@'
(define CSI-FINAL-END 126)    ; '~'

;; CSI final byte → 方向键/功能键
(define CSI-FINAL-UP      65) ; A
(define CSI-FINAL-DOWN    66) ; B
(define CSI-FINAL-RIGHT   67) ; C
(define CSI-FINAL-LEFT    68) ; D
(define CSI-FINAL-END-KEY 70) ; F
(define CSI-FINAL-HOME    72) ; H

;; CSI ~ 参数 → 功能键
(define CSI-PARAM-DELETE   3)
(define CSI-PARAM-INSERT   2)
(define CSI-PARAM-PAGEUP   5)
(define CSI-PARAM-PAGEDOWN 6)

;; 括号粘贴序列长度
(define CSI-PASTE-SEQ-LEN 6)

;; 括号粘贴标记
(define BRACKETED-PASTE-START-1 50)   ; '2'
(define BRACKETED-PASTE-START-2 48)   ; '0'
(define BRACKETED-PASTE-START-3 48)   ; '0'
(define BRACKETED-PASTE-END-1 50)     ; '2'
(define BRACKETED-PASTE-END-2 48)     ; '0'
(define BRACKETED-PASTE-END-3 49)     ; '1'
(define TILDE 126)                    ; '~'

;; 鼠标事件标记
(define MOUSE-EVENT 77)      ; 'M' - 鼠标按下/移动
(define MOUSE-RELEASE 109)   ; 'm' - 鼠标释放

;; CSI 参数分隔符
(define CSI-PARAM-SEP 59)    ; ';'

;; UTF-8 编码范围
(define UTF8-2BYTE-START 194)
(define UTF8-2BYTE-END 223)
(define UTF8-3BYTE-START 224)
(define UTF8-3BYTE-END 239)
(define UTF8-4BYTE-START 240)
(define UTF8-4BYTE-END 244)

;; 修饰键参数值
(define MOD-ALT 3)       ; Alt 修饰符
(define MOD-CTRL 5)      ; Ctrl 修饰符
(define MOD-ALT-CTRL 7)  ; Alt+Ctrl

;; 鼠标事件类型位掩码
(define MOUSE-BUTTON-MASK #b11)      ; 按钮掩码 (bits 0-1)
(define MOUSE-MOVE-FLAG #b100000)    ; 移动标志 (bit 5)
(define MOUSE-SCROLL-START 64)       ; 滚轮向上
(define MOUSE-SCROLL-END 65)         ; 滚轮向下

(provide (all-defined-out))
