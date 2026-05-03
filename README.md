# Racket TUI Library

终端用户界面库，支持鼠标、触摸板、真彩色、括号粘贴和窗口大小变化事件。

## 远程安装

```bash
raco pkg install https://github.com/lu96-wow/racket-tui.git
```

https://a.gif

## 快速开始

```racket
#lang racket

(require tui)

;; 方式1：直接输出（立即显示）
(with-tui
  (screen-clear)
  (cursor-hide)
  (put-rgb-fg 255 100 0 "Hello TUI!")
  (put-at 5 10 "Direct output")
  (sleep 2))

;; 方式2：批量输出（收集后一次性显示）
(with-tui
  (screen-clear)
  (define buffer
    (bytes-append
     (format-cursor-move 5 10)
     (format-rgb-fg 0 255 0 "Green text")
     (format-cursor-move 6 10)
     (format-256-fg 46 "Bright green")))
  (put-bytes buffer)  ;; 一次性输出
  (sleep 2))
```

## 输出系统

### 立即输出函数（put- 前缀）

直接输出到终端，立即显示：

```racket
;; 基础输出
(put "Hello")
(put-string "text")
(put-bytes #"bytes")
(put-char #\A)
(put-byte 65)
(put-newline)

;; 光标控制
(cursor-up 1)
(cursor-down 1)
(cursor-left 1)
(cursor-right 1)
(cursor-move 5 10)
(cursor-col 20)
(cursor-home)
(cursor-hide)
(cursor-show)

;; 屏幕控制
(screen-clear)
(screen-clear-below)
(screen-clear-above)
(line-clear)
(line-clear-right)
(line-clear-left)
(buffer-alt-enable)
(buffer-alt-disable)

;; 位置输出
(put-at 5 10 "Text")
(put-at! 5 10 "Text")
```

### 颜色输出（立即）

```racket
;; 16色
(fg-red) (bg-blue)
(put-styled 'error "错误信息")

;; 真彩色（RGB）
(put-rgb-fg 255 100 0 "橙色文字")
(put-rgb-bg 0 0 255 "蓝色背景")
(put-rgb-fg-bg 255 255 0 0 0 255 "黄字蓝底")

;; 256色
(put-256-fg 46 "亮绿色")
(put-256-bg 124 "暗红色背景")

;; 位置颜色输出
(put-rgb-fg-at 5 10 255 128 0 "橙色文字")
(put-rgb-fg-at! 5 10 255 128 0 "橙色文字")
```

## 格式化函数（format- 前缀）

返回字节串而不输出，用于批量收集：

```racket
(define my-buffer (bytes))

(set! my-buffer (bytes-append my-buffer (format-cursor-move 5 10)))
(set! my-buffer (bytes-append my-buffer (format-cursor-up 2)))
(set! my-buffer (bytes-append my-buffer (format-cursor-home)))

(set! my-buffer (bytes-append my-buffer (format-rgb-fg 255 0 0 "Red")))
(set! my-buffer (bytes-append my-buffer (format-rgb-bg 0 0 255 "Blue")))
(set! my-buffer (bytes-append my-buffer (format-256-fg 46 "Green")))
(set! my-buffer (bytes-append my-buffer (format-rgb-fg-bg 255 255 0 0 0 255 "Yellow/Blue")))

(set! my-buffer (bytes-append my-buffer format-screen-clear))
(set! my-buffer (bytes-append my-buffer format-cursor-hide))

(define style-bytes (call-with-output-bytes
                     (λ (out)
                       (parameterize ([current-output-port out])
                         (clr-red) (attr-bold)))))
(set! my-buffer (bytes-append my-buffer (format-styled style-bytes "Bold Red")))

(put-bytes my-buffer)
```

## 可用格式化函数列表

| 函数 | 说明 | 对应输出函数 |
|------|------|--------------|
| (format-cursor-move row col) | 移动光标 | cursor-move |
| (format-cursor-up n) | 光标上移 | cursor-up |
| (format-cursor-down n) | 光标下移 | cursor-down |
| (format-cursor-left n) | 光标左移 | cursor-left |
| (format-cursor-right n) | 光标右移 | cursor-right |
| (format-cursor-col n) | 移动到列 | cursor-col |
| format-cursor-home | 原点 | cursor-home |
| format-cursor-hide | 隐藏光标 | cursor-hide |
| format-cursor-show | 显示光标 | cursor-show |
| format-screen-clear | 清屏 | screen-clear |
| format-screen-clear-below | 清下方 | screen-clear-below |
| format-screen-clear-above | 清上方 | screen-clear-above |
| format-line-clear | 清行 | line-clear |
| format-line-clear-right | 清右 | line-clear-right |
| format-line-clear-left | 清左 | line-clear-left |
| format-buffer-alt-enable | 备用屏开 | buffer-alt-enable |
| format-buffer-alt-disable | 备用屏关 | buffer-alt-disable |
| format-reset | 重置 | style-reset |
| (format-rgb-fg r g b v) | RGB前景 | put-rgb-fg |
| (format-rgb-bg r g b v) | RGB背景 | put-rgb-bg |
| (format-rgb-fg-bg fr fg fb br bg bb v) | RGB前后景 | put-rgb-fg-bg |
| (format-256-fg n v) | 256前景 | put-256-fg |
| (format-256-bg n v) | 256背景 | put-256-bg |
| (format-styled style-bytes v) | 样式 | put-styled |

## 样式系统

```racket
(style-define! 'fancy clr-yellow bclr-blue attr-bold attr-underline)

(put-styled 'fancy "组合样式")

(define fancy-bytes
  (call-with-output-bytes
   (λ (out)
     (parameterize ([current-output-port out])
       (style-apply! 'fancy)))))

(define styled-text (format-styled fancy-bytes "Styled text"))
```

## 输入设计

```racket
(let-values ([(type data mods) (read-event)])
  (cond
    [(event-touch? type)
     (let-values ([(x y) (get-mouse-pos data)])
       (printf "鼠标 ~a,~a" x y))]
    [(event-up? type) (cursor-up 1)]
    [(event-ctrl? type) (printf "Ctrl+~a" (ctrl->char data))]
    [(event-utf8? type) (printf "UTF-8: ~a" (event->string data))]
    [(event-resize? type)
     (printf "~a×~a"
             (get-resize-rows data)
             (get-resize-cols data))]
    [(event-paste? type)
     (printf "粘贴: ~a 字节" (bytes-length data))]))
```

## 生命周期管理

```racket
(with-tui
  (screen-clear)
  (put "Hello")
  (read-event))

(tui-init)
(tui-exit)

(with-tui-nobuffer
  (put "Output in main buffer"))
```

## Buffer

```racket
;; 批量输出
(define buf (bytes))
(for ([i 100])
  (set! buf (bytes-append buf (string->bytes/utf-8 "X"))))
(put-bytes buf)
```

## 完整示例

```racket
#lang racket
(require tui)

(define (draw-ui)
  (define buffer
    (bytes-append
     format-screen-clear
     (format-cursor-move 0 0)
     (format-rgb-fg 255 255 0 "=== TUI Demo ===")))
  (put-bytes buffer))

(with-tui
  (cursor-hide)
  (let loop ()
    (draw-ui)
    (read-event)
    (loop)))
```
