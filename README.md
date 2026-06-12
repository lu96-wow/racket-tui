# Racket TUI Library

终端用户界面库，支持鼠标、触摸板、真彩色、括号粘贴和窗口大小变化事件。

## 远程安装

```bash
raco pkg install https://github.com/lu96-wow/racket-tui.git
```

![Demo](a.gif)

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

`build-input` 是本库推荐的高层输入事件分发 API，通过回调函数方式简化事件处理。
它封装了底层 `read-event` 的事件判断逻辑，用户只需声明"当 X 事件发生时调用什么函数"即可。

### 推荐方式：build-input

`require tui` 后即可直接使用 `build-input`，无需额外加载：

```racket
(require tui)

(define handler
  (build-input
    #:char      (lambda (ch) (printf "按键: ~a\n" (integer->char ch)))
    #:up        (lambda ()  (cursor-up 1))
    #:down      (lambda ()  (cursor-down 1))
    #:left      (lambda ()  (cursor-left 1))
    #:right     (lambda ()  (cursor-right 1))
    #:resize    (lambda (rows cols) (printf "窗口: ~ax~a\n" rows cols))
    #:mouse-press (lambda (btn x y mods) (printf "鼠标按下 ~a (~a,~a)\n" btn x y))
    #:any       (lambda (type data mods) (printf "未处理: ~a\n" type))))

;; 在事件循环中使用
(let loop ()
  (let-values ([(type data mods) (read-event)])
    (handler type data mods)
    (loop)))
```

所有关键字参数均为可选，支持以下事件：

| 参数 | 回调签名 | 说明 |
|------|----------|------|
| `#:char` | `(lambda (ch) ...)` | 普通按键，ch 为 ASCII 值 |
| `#:utf-char` | `(lambda (str) ...)` | UTF-8 字符 |
| `#:ctrl` | `(lambda (ch) ...)` | Ctrl+字母，ch 为 `#\A`-`#\Z` |
| `#:alt` | `(lambda (ch) ...)` | Alt+字母 |
| `#:mod` | `(lambda (ch ctrl? alt?) ...)` | Ctrl+Alt+组合 |
| `#:tab` / `#:space` / `#:enter` / `#:backspace` / `#:escape` | `(lambda () ...)` | 特殊键 |
| `#:up` / `#:down` / `#:left` / `#:right` | `(lambda () ...)` | 方向键 |
| `#:delete` / `#:insert` / `#:home` / `#:end` / `#:pageup` / `#:pagedown` | `(lambda () ...)` | 功能键 |
| `#:mouse-press` | `(lambda (button x y modifiers) ...)` | 鼠标按下，button 为 `'left`/`'middle`/`'right` |
| `#:mouse-release` | `(lambda (button x y modifiers) ...)` | 鼠标释放 |
| `#:mouse-move` | `(lambda (x y modifiers) ...)` | 鼠标移动 |
| `#:mouse-scroll` | `(lambda (dir x y modifiers) ...)` | 滚轮，dir 为 `'up`/`'down` |
| `#:paste` | `(lambda (data) ...)` | 括号粘贴，data 为 bytes |
| `#:resize` | `(lambda (rows cols) ...)` | 窗口大小变化 |
| `#:null` | `(lambda () ...)` | 无输入事件 |
| `#:any` | `(lambda (type data mods) ...)` | 兜底回调 |

优先级顺序（内置保证，用户无需关心）：`null > resize > paste > mouse > tab/space/enter/backspace/escape > 方向键 > 功能键 > ctrl > alt > mod > utf8 > char > any`

### 底层 API（input.rkt）

如果需要对事件类型做更精细的控制，也可直接使用底层 `read-event` 和事件判断函数：

```racket
(require tui)

(let-values ([(type data mods) (read-event)])
  (cond
    [(event-touch? type)
     (let-values ([(x y) (get-mouse-pos data)])
       (printf "鼠标 ~a,~a" x y))]
    [(event-up? type) (cursor-up 1)]
    [(event-ctrl? type) (printf "Ctrl+~a" (ctrl->char data))]
    [(event-utf8? type) (printf "UTF-8: ~a" (event->string data))]
    [(event-resize? type)
     (printf "~a×~a" (get-resize-rows data) (get-resize-cols data))]
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
#lang racket
(require tui)

(with-tui-nobuffer
    (define buffer-content
      (list
       format-screen-clear
       (format-cursor-move 0 0)
       (format-rgb-fg 255 255 0 "=== Demo ===")
       (format-cursor-move 2 0)
       (format-rgb-fg 0 255 0 "Line 1")
       (format-cursor-move 3 0)
       (format-rgb-fg 0 255 0 "Line 2")
       (format-cursor-move 4 0)
       (format-rgb-fg 0 255 0 "Line 3")))

  ;; 拼接所有字节串
  (define screen (apply bytes-append buffer-content))

  ;; 一次性输出
  (put-bytes screen))
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
     (format-rgb-fg 255 255 0 "=== TUI Demo ===")
     (format-cursor-move 2 0)
     (format-rgb-fg 0 255 0 "Press 'q' to quit")
     (format-cursor-move 4 0)
     (format-rgb-fg 255 0 0 "Hello, TUI!")
     (format-cursor-move 6 0)
     (format-256-fg 46 "UTF-8 support: 你好世界")))
  (put-bytes buffer))

(with-tui
    (cursor-hide)
  (define handler
    (build-input
      #:char (lambda (ch)
               (when (= ch (char->integer #\q))
                 (exit)))))  ;; 按 q 退出
  (let loop ()
    (draw-ui)
    (let-values ([(type data mods) (read-event)])
      (handler type data mods)
      (loop))))
```

其他示例在 test 目录下。

## 刷新模式

```racket
(set-immediate-mode!)    ;; put- 函数立即刷新（默认）
(set-buffered-mode!)     ;; put- 函数缓冲输出
(flush)                  ;; 手动触发刷新
```

## 前缀/后缀约定

| 前缀 | 含义 | 示例 |
|------|------|------|
| `put-` | 立即输出到终端 | `put`, `put-string` |
| `format-` | 返回字节串，配合 `put-bytes` 批量输出 | `format-cursor-move` |
| `clr-` | 颜色设置（16色） | `clr-red` |
| `attr-` | 属性设置 | `attr-bold` |

| 后缀 | 含义 | 示例 |
|------|------|------|
| `!` | 有副作用（改变光标位置） | `put-at!`, `style-define!` |
| `?` | 谓词，返回布尔值 | `event-key?`, `terminal?` |
| `-at` | 带位置参数 | `put-at`, `cursor-move` |
| `-at!` | 带位置参数 + 有副作用 | `put-at!` |

> waring: only test in xterm/qterminal