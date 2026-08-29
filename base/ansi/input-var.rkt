#lang racket

;; ════════════════════════════════════════════════════════════════
;; 输入事件符号常量
;; EVENT- / KEY- / BUTTON- / SCROLL- 前缀避免与 ansi-var.rkt
;; 中的数值常量冲突 (如 ansi-var 的 MOUSE-RELEASE=109)
;; ════════════════════════════════════════════════════════════════

(define EVENT-NULL   'null)
(define EVENT-KEY    'key)
(define EVENT-UTF8   'utf8)
(define EVENT-SEQ    'seq)
(define EVENT-CTRL   'ctrl)
(define EVENT-ALT    'alt)
(define EVENT-MOD    'mod-seq)
(define EVENT-RESIZE 'resize)
(define EVENT-MOUSE  'mouse)
(define EVENT-PASTE  'paste)

(define KEY-UP       'up)
(define KEY-DOWN     'down)
(define KEY-LEFT     'left)
(define KEY-RIGHT    'right)
(define KEY-DELETE   'del)
(define KEY-INSERT   'insert)
(define KEY-HOME     'home)
(define KEY-END      'end)
(define KEY-PAGEUP   'pageup)
(define KEY-PAGEDOWN 'pagedown)
(define KEY-BACKTAB  'backtab)   ; Shift+Tab (xterm: ESC [ Z)

(define EVENT-MOUSE-PRESS   'press)
(define EVENT-MOUSE-RELEASE 'release)
(define EVENT-MOUSE-MOVE    'move)
(define EVENT-MOUSE-SCROLL  'scroll)

(define BUTTON-LEFT    'left)
(define BUTTON-MIDDLE  'middle)
(define BUTTON-RIGHT   'right)
(define BUTTON-UNKNOWN 'unknown)

(define SCROLL-UP   'up)
(define SCROLL-DOWN 'down)

(provide (all-defined-out))
