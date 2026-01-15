#lang racket

;; attribute_data.rkt
;; 根据 ncurses 头文件硬编码 A_XXX 属性常量
;; 基于 NCURSES_ATTR_SHIFT = 8

(define NCURSES_ATTR_SHIFT 8)

;; 辅助函数：A_XXX = 1 << (N + 8)
(define-syntax-rule (define-A name shift)
  (define name (arithmetic-shift 1 (+ shift NCURSES_ATTR_SHIFT))))

;; 基础属性
(define A_NORMAL       0)                          ; (1U - 1U)
(define A_CHARTEXT     #xFF)                       ; (NCURSES_BITS(1U,0) - 1U) → (1<<8)-1 = 255
(define A_COLOR        #xFF00)                     ; NCURSES_BITS(((1U)<<8)-1U, 0) → 255<<8 = 65280
(define A_ATTRIBUTES   #xFFFF0000)                 ; NCURSES_BITS(～0U, 0) → 高16位掩码（32位模型）

;; 标准视频属性（按 shift 值定义）
(define-A A_STANDOUT     8)    ; 1 << (8+8)  = 65536
(define-A A_UNDERLINE    9)    ; 1 << 17     = 131072
(define-A A_REVERSE     10)    ; 1 << 18     = 262144
(define-A A_BLINK       11)    ; 1 << 19     = 524288
(define-A A_DIM         12)    ; 1 << 20     = 1048576
(define-A A_BOLD        13)    ; 1 << 21     = 2097152
(define-A A_ALTCHARSET  14)    ; 1 << 22     = 4194304
(define-A A_INVIS       15)    ; 1 << 23     = 8388608
(define-A A_PROTECT     16)    ; 1 << 24     = 16777216
(define-A A_HORIZONTAL  17)    ; 1 << 25     = 33554432
(define-A A_LEFT        18)    ; 1 << 26     = 67108864
(define-A A_LOW         19)    ; 1 << 27     = 134217728
(define-A A_RIGHT       20)    ; 1 << 28     = 268435456
(define-A A_TOP         21)    ; 1 << 29     = 536870912
(define-A A_VERTICAL    22)    ; 1 << 30     = 1073741824

;; ncurses 扩展
(define-A A_ITALIC      23)    ; 1 << 31     = 2147483648

;; 提供所有定义
(provide (all-defined-out))