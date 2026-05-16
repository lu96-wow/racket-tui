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

## 输入系统

### build-input（推荐）

用声明式关键字替代手动事件判断，内置正确的优先级顺序：

```racket
(require tui)  ; build-input 已包含在 tui 中

(define handler
  (build-input
    #:char      (lambda (ch) (printf "按键: ~a\n" (integer->char ch)))
    #:up        (lambda ()  (cursor-up 1))
    #:ctrl      (lambda (ch) (printf "Ctrl+~a\n" ch))
    #:resize    (lambda (rows cols) (printf "~a×~a\n" rows cols))
    #:paste     (lambda (data) (printf "粘贴: ~a 字节\n" (bytes-length data)))
    #:any       (lambda (type data mods) (printf "[~a]\n" type))))

(let loop ()
  (let-values ([(type data mods) (read-event)])
    (handler type data mods)
    (loop)))
```

全部关键字参数：

| 关键字 | handler 签名 | 说明 |
|--------|-------------|------|
| `#:char` | `(lambda (ch) ...)` | ASCII 字节值 |
| `#:utf-char` | `(lambda (str) ...)` | UTF-8 字符串 |
| `#:ctrl` | `(lambda (ch) ...)` | Ctrl+字母，ch 是 char |
| `#:alt` | `(lambda (ch) ...)` | Alt+字母 |
| `#:mod` | `(lambda (ch ctrl? alt?) ...)` | Ctrl+Alt+字母 |
| `#:tab` `#:space` `#:enter` `#:backspace` `#:escape` | `(lambda () ...)` | 特殊键 |
| `#:up` `#:down` `#:left` `#:right` | `(lambda () ...)` | 方向键 |
| `#:delete` `#:insert` `#:home` `#:end` `#:pageup` `#:pagedown` | `(lambda () ...)` | 编辑键 |
| `#:mouse-press` | `(lambda (button x y mods) ...)` | 鼠标按下 |
| `#:mouse-release` | `(lambda (button x y mods) ...)` | 鼠标释放 |
| `#:mouse-move` | `(lambda (x y mods) ...)` | 鼠标移动 |
| `#:mouse-scroll` | `(lambda (dir x y mods) ...)` | 滚轮，dir='up/'down |
| `#:paste` | `(lambda (data) ...)` | 粘贴内容(bytes) |
| `#:resize` | `(lambda (rows cols) ...)` | 窗口大小变化 |
| `#:null` | `(lambda () ...)` | 无输入事件 |
| `#:any` | `(lambda (type data mods) ...)` | 兜底，未匹配的事件 |

### 底层 API

如需直接使用 `read-event`，返回 `(type data mods)` 三值。判断函数见 `input.rkt`：

```racket
(let-values ([(type data mods) (read-event)])
  (cond [(event-up? type)    ...]
        [(event-ctrl? type)  (ctrl->char data) ...]
        [(event-utf8? type)  (event->string data) ...]
        [(event-mouse? type) (get-mouse-pos data) ...]
        [(event-paste? type) (bytes-length data) ...]
        ...))
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

(with-tui
    (cursor-hide)
  (define running? #t)
  (define handler
    (build-input
      #:char (lambda (ch)
               (when (= ch (char->integer #\q))
                 (set! running? #f)))
      #:any (lambda (t d m) (void))))

  (let loop ()
    (when running?
      (with-screen-buffer
        (λ ()
          (put-at 0 0 (format-rgb-fg 255 255 0 "=== TUI Demo ==="))
          (put-at 2 0 (format-rgb-fg 0 255 0 "Press 'q' to quit"))
          (put-at 4 0 (format-rgb-fg 255 0 0 "Hello, TUI!"))
          (put-at 6 0 (format-256-fg 46 "UTF-8: 你好世界"))))

      (change-noblock)
      (let-values ([(type data mods) (read-event)])
        (handler type data mods))
      (sleep 0.01)
      (loop))))
```

更多示例在 `test/` 目录下：
- `test/input.rkt` — 输入事件测试
- `test/matrix.rkt` — 字符雨（全量输出）
- `test/matrix-buffer.rkt` — 字符雨（双缓冲 diff 版本）
- `test/output.rkt` — 样式系统示例
- `test/color.rkt` / `test/color-256.rkt` / `test/color-rgb.rkt` — 颜色测试

## 双缓冲渲染 (Screen Buffer)

逐帧只输出变化格子，大幅减少终端 I/O。

### 快速开始

```racket
(with-screen-buffer
  (λ ()
    (put-at 0 0 "Hello")
    (put-fg 1 "Red")))
```

### 跨帧复用（真正 diff）

```racket
(define buf (make-screen-buffer))

(let loop ()
  (parameterize ([current-screen buf])
    (sb-ensure! buf rows cols)
    (sb-clear! buf)
    (put-at 0 0 "frame content")
    (sb-flush! buf))
  (loop))
```

设置 `(current-screen buf)` 后所有 `put-*`/`put-fg`/`put-styled` 自动写入 buffer。

### API

| 函数 | 说明 |
|------|------|
| `(make-screen-buffer)` | 创建空 buffer |
| `(sb-ensure! buf rows cols)` | 扩容（只增不减，应对 resize） |
| `(sb-put! buf row col bytes)` | 指定位置写内容 |
| `(sb-clear! buf)` | 全填空格 |
| `(sb-flush! buf)` | diff + 一次性输出 |
| `(current-screen)` | parameter，设 buffer 即开启 screen-mode |
| `(with-screen-buffer thunk)` | 创建 buffer → 执行 → flush |

## 前缀/后缀约定

| 前缀 | 含义 |
|------|------|
| `format-` | 返回 bytes，不输出，配合 `put-bytes` 批量输出 |
| `put-` | 立即输出（screen-mode 下写入 buffer） |

| 后缀 | 含义 | 示例 |
|------|------|------|
| `!` | 有副作用（改变光标位置） | `put-at!`, `style-define!` |
| `?` | 谓词，返回布尔值 | `terminal?` |
| `-at` | 带位置参数 | `put-at`, `cursor-move` |
| `-at!` | 带位置参数 + 有副作用 | `put-at!` |

测试环境：xterm / qterminal
