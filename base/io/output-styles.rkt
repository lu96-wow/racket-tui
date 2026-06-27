#lang racket

(require "output-color.rkt")

;; 预定义颜色（用于样式系统）
(define clr-black    (color-fg 0))
(define clr-red      (color-fg 1))
(define clr-green    (color-fg 2))
(define clr-yellow   (color-fg 3))
(define clr-blue     (color-fg 4))
(define clr-magenta  (color-fg 5))
(define clr-cyan     (color-fg 6))
(define clr-white    (color-fg 7))
(define clr-default  (color-fg 9))

(define bclr-black   (color-bg 0))
(define bclr-red     (color-bg 1))
(define bclr-green   (color-bg 2))
(define bclr-yellow  (color-bg 3))
(define bclr-blue    (color-bg 4))
(define bclr-magenta (color-bg 5))
(define bclr-cyan    (color-bg 6))
(define bclr-white   (color-bg 7))
(define bclr-default (color-bg 9))

;; 基础颜色样式
(style-define! 'red     clr-red)
(style-define! 'green   clr-green)
(style-define! 'blue    clr-blue)
(style-define! 'yellow  clr-yellow)
(style-define! 'cyan    clr-cyan)
(style-define! 'magenta clr-magenta)
(style-define! 'white   clr-white)

;; 语义化样式
(style-define! 'error   clr-red attr-bold)
(style-define! 'warning clr-yellow attr-bold)
(style-define! 'info    clr-cyan)
(style-define! 'success clr-green)

;; UI 组件样式
(style-define! 'cursor    bclr-white clr-black)
(style-define! 'selection bclr-blue clr-white)

;; 标题样式
(style-define! 'title      clr-cyan attr-bold)
(style-define! 'subtitle   clr-blue)
(style-define! 'heading    clr-white attr-bold)

;; 边框样式
(style-define! 'border     clr-blue)
(style-define! 'border-bold clr-blue attr-bold)

;; 按钮样式
(style-define! 'button           clr-white bclr-blue attr-bold)
(style-define! 'button-hover     clr-black bclr-cyan attr-bold)
(style-define! 'button-disabled  clr-white bclr-black)

;; 菜单样式
(style-define! 'menu-item        clr-white)
(style-define! 'menu-selected    clr-black bclr-blue attr-bold)
(style-define! 'menu-key         clr-yellow attr-bold)
(style-define! 'menu-shortcut    clr-cyan)

;; 列表样式
(style-define! 'list-item        clr-white)
(style-define! 'list-selected    clr-black bclr-blue)
(style-define! 'list-alternate   bclr-black)  ; 斑马纹

;; 对话框样式
(style-define! 'dialog-title     clr-cyan attr-bold)
(style-define! 'dialog-body      clr-white)
(style-define! 'dialog-button    clr-white bclr-blue)
(style-define! 'dialog-highlight clr-yellow attr-bold)

;; 状态栏样式
(style-define! 'status-bar       clr-white bclr-blue)
(style-define! 'status-good      clr-green attr-bold)
(style-define! 'status-warning   clr-yellow attr-bold)
(style-define! 'status-bad       clr-red attr-bold)

;; 输入框样式
(style-define! 'input-normal     clr-white)
(style-define! 'input-focus      clr-white bclr-blue)
(style-define! 'input-error      clr-red bclr-white attr-bold)

(provide (all-defined-out))