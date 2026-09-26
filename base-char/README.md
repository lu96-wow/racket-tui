# Char Backend（字符图后端）

> 目标：把 tui 的输出渲染成**纯字符网格**，供 AI 调试 / 自动化测试 / 无终端（无 tty）环境使用。
> 与真实终端后端 `tui` 同名同 API，**只改 require 路径即可切换**。
>
> char 后端**不加载 termios / FFI**，因此可在任何平台和沙箱（非 Linux、CI、AI 运行环境）运行；
> base 支持 Linux 与 Android/Termux（Termux 的 Racket BC 报 `os* = 'android`）。

```racket
(require tui)        ; 真实终端：输出 ANSI 到 stdout
(require tui/char)   ; 字符图：输出到内存网格，可读回纯文本
```

---

## 快速开始

```racket
#lang racket
(require tui/char)

(parameterize ([current-screen-size (cons 6 30)])   ; 与 base 一致：尺寸走 parameter
 (with-tui
  (λ ()
    (put-bytes
     (bytes-append                    ; ← 被 base-char 覆盖，行为=拼 op
      format-screen-clear
      (format-cursor-move 1 1)
      (format-rgb-fg 255 255 0 "=== TUI Demo ===")
      (format-cursor-move 3 1)
      (format-256-fg 46 "count = 42")))
    (displayln (char-frame)))))        ; 读回纯字符图
```

输出：

```
=== TUI Demo ===

count = 42
```

也可以直接构建（不经 `bytes-append`）：

```racket
(parameterize ([current-screen-size (cons 12 40)])
 (with-tui
  (λ ()
    (screen-clear)
    (put-at 5 10 "Hello")
    (put-rgb-fg 0 255 0 "green")
    (displayln (char-frame)))))
```

---

## 原理：镜像 + 叶子替换，**无需解析**

```
base       用户代码 ──► put-*/format-* ──► ANSI 字节 ──► stdout
base-char  用户代码 ──► put-*/format-* ──► op        ──► grid ──► 纯字符图
```

- 上层 API 与 `base` **完全同名同签名**，调用点不用改。
- 唯一被替换的「叶子」是：
  - `base-char/ansi/ansi-format.rkt`：`format-*` 返回 **op / op-seq**（不再是 ANSI 字节）
  - `base-char/io/output.rkt`：`put-*` 把 op 作用到网格
- 因此从 `format-*` 到网格**全程零解析**，信息无损、也不存在解析分歧。

`base-char/screen/ansi-parse.rkt` 里的 ANSI 解析器**不参与主路径**，只作为测试用的
「预言机」：同一段 UI 分别走 op 路径和 ANSI 字节→解析路径，结果必须一致。

---

## `bytes-append` 被覆盖

`base-char/main.rkt` 会 `provide` 一个自己的 `bytes-append`（等价 `ops-append`）。
Racket 允许显式 `require` 覆盖 `#lang` 的初始导入，所以：

```racket
(require tui/char)
(bytes-append format-screen-clear (format-cursor-move 1 1) "hi")  ; → op-seq
```

- **作用域仅限当前模块**：其他模块的 `bytes-append` 仍是 `racket` 原版。
- 即使再 `(require racket/bytes)` 也不冲突。
- **代价**：同一模块内它不再做真正的字节拼接。若该模块需要真正的字节拼接，
  用 `(require (rename-in racket/base [bytes-append raw-bytes-append]))` 取原版。

`put-bytes` / `put` / `put-format-bytes` 同时接受 op-seq、`bytes`、`string`，
裸字节按 UTF-8 文本写入网格。

---

## 尺寸与生命周期

```racket
(parameterize ([current-screen-size (cons 24 80)])
  (with-tui thunk))                    ; 尺寸来自 current-screen-size（默认 24×80）

(current-screen-size (cons 30 100))    ; 全局默认尺寸
(current-screen)                       ; 当前网格（参数）
(the-screen)                           ; 当前网格；没有就按尺寸新建
(call-with-screen g thunk)             ; 临时切换到指定网格
(tui-init)                             ; 手动初始化（同样读 current-screen-size）
(tui-exit)                             ; 清理（仅复位 newline-var）
```

`with-tui` / `with-tui-nobuffer` / `with-tui-nobuffer-echo` 都存在且语义一致
（char 后端没有 raw 模式，三者只是别名）。mouse / bracketed-paste 相关函数是 no-op。

---

## 纯字符图输出

| 函数 | 说明 |
|---|---|
| `(char-frame #:trim-right? #t)` | 当前整屏字符图（最常用） |
| `(screen->text g #:trim-right? #t)` | 指定网格 → 多行字符串 |
| `(screen->lines g #:trim-right? #t)` | → `listof string` |
| `(grid->text g ...)` / `(grid->lines g ...)` | 同上（别名） |

约定：

- 宽字符左格放字符、右半格 `#f` 渲染为空串，保证列对齐。
- `#:trim-right?` 默认 `#t`，去掉行尾空白；需要精确比对时传 `#f`。

---

## 光标与属性查询

### 光标位置

| 函数 | 返回 | 坐标系 |
|---|---|---|
| `(get-cursor)` | `(values row col)` | **1-based**（与 base 一致） |
| `(update-cursor!)` | `(values row col)` | 1-based（直接读网格，不发 DSR） |
| `(screen-cursor g)` | `(values row col)` | **0-based** |
| `(screen-cursor-cell g)` | 光标处 `cell` | — |
| `(screen-size g)` | `(values rows cols)` | — |
| `current-cursor-row` / `current-cursor-col` | 数值 | 1-based |

### 局部属性

| 函数 | 返回 |
|---|---|
| `(screen-ref g row col)` | `cell` 结构体 |
| `(cell-text c)` / `(cell-fg c)` / `(cell-bg c)` / `(cell-attrs c)` | 单格内容与属性 |
| `(style->string c)` | 可读样式串，如 `"fg#1 bold"` |
| `(screen-style-at g row col)` | 指定格样式串 |
| `(screen-current-style g)` | 当前待写入属性（下一个字符会带的 SGR 状态） |
| `(screen-styled-cells g)` | 整屏非默认格清单 `(row col text style)` |
| `(screen-attr-ranges g)` | 整屏按行的属性区间（压缩，最省 token） |

颜色表示：`#f`（默认）｜`(list 'idx n)`（索引色 0-255）｜`(list 'rgb r g b)`。
属性为 symbol 列表：`bold dim italic underline blink reverse`。

```racket
(parameterize ([current-screen-size (cons 6 16)])
  (with-tui (λ ()
              (put-at 3 5 "hello")
              (put-styled-at 2 1 'error "E")
              (displayln (call-with-values get-cursor list))          ; (1 1)
              (displayln (screen-style-at (the-screen) 1 0))          ; "fg#1 bold"
              (displayln (screen-styled-cells (the-screen))))))
```

---

## 脚本输入与事件循环

char 后端的输入有两个语义：

- **`read-event` 默认阻塞**（与真实终端一致）：队列为空且未关闭时等待，
  有事件才返回，因此 `loop-input` 不会空转、不会刷屏。
- **`read-event-noblock` 非阻塞**：无事件立即返回 `null-event`。

脚本跑完后用 `char-input-close!` 标记结束，此时 `read-event` 返回 `null-event`，
配合 `char-input-exhausted?` 作为停止条件即可有界退出。

```racket
(char-input-push! spec ...)   ; 追加事件（队列由空变非空时唤醒等待者）
(char-input-close!)           ; 标记脚本结束
(char-input-exhausted?)       ; 已关闭且队列空
(char-input-open?)            ; 尚未关闭
(char-input-empty?)           ; 队列是否为空
(char-input-clear!)           ; 清空并重新打开
(char-input-remaining)        ; 剩余个数
(read-event)                  ; 阻塞取一个
(read-event-noblock)          ; 非阻塞取一个
```

`spec` 可以是：

| 形态 | 含义 |
|---|---|
| `event?` 结构体 | 原样入队，例如 `(key-event #\a no-mods)` |
| `#\a` | 普通字符键 |
| `'enter` / `'up` / `'tab` … | 命名键 |
| `(key mods)` | 带修饰键，例如 `(list #\a (mods #t #f #f))` |
| `(type data mods)` | 低层 raw 形式，走 `normalize-event` |

完整循环（无终端）：

```racket
#lang racket
(require tui/char)

(define count 0)
(define quit? #f)

(define (draw)
  (bytes-append
   format-screen-clear
   (format-cursor-move 1 1) (format-rgb-fg 0 255 0 "Counter demo")
   (format-cursor-move 3 1) (format-256-fg 46 (format "count = ~a" count))
   (format-cursor-move 5 1) format-bold "keys: + - q" format-reset))

(parameterize ([current-screen-size (cons 7 24)])
 (with-tui
  (λ ()
    (char-input-push! #\+ #\+ #\- #\q)
    (define handler
      (build-input
       #:key (λ (k mods)
               (case k
                 [(#\+) (set! count (add1 count))]
                 [(#\-) (set! count (sub1 count))]
                 [(#\q) (set! quit? #t)]))))
    (loop-input/stop (or quit? (char-input-empty?))
      (λ (ev) (handler ev) (put-bytes (draw)) (flush!) (displayln (char-frame)))))))
```

`build-input`、`loop-input`、`loop-input-noblock`、`loop-input/stop`、
`loop-input-noblock/stop` 与 base 同名同签名。
（`loop-input*` 是宏，char 后端重新定义以保证其中 `read-event` 绑定到脚本输入。）

## 有界运行与「防无限输出」

逐帧调试最怕两件事：非阻塞循环空转、以及没变化也在一直输出。char 后端用
三层机制处理：

1. **输入默认阻塞**：`loop-input` / `read-event` 不会空转（见上）。
2. **帧默认去重**：`flush!` 只在字符图**发生变化**时才触发帧钩子
   （`current-frame-dedup?`，默认 `#t`）。同样的帧不会重复输出。
3. **有界脚本运行器 `char-run`**（推荐入口）：给定一串事件，每个事件处理并
   渲染一次，脚本跑完即结束，帧数 ≤ 事件数 + 1。

```racket
(define frames
  (char-run (list #\+ #\+ #\- #\q)
            #:handle   (λ (ev) ...)      ; 处理事件（通常更新外部 state）
            #:render   (λ () ...)        ; 绘制到当前网格
            #:snapshot char-frame        ; 抓帧（默认 char-frame）
            #:stop     (λ () quit?)      ; 额外提前停止条件
            #:dedup?   #t                ; 跳过与上一帧相同的帧
            #:rows 24 #:cols 80))
;; => (listof string)  帧序列
```

不建议在 `loop-input-noblock` 里无条件打印：`read-event-noblock` 每轮都返回，
循环会无限跑。若要连续动画，请把渲染挂在 `flush!` + 帧钩子上（有去重），
或固定帧率驱动；确定性调试则直接用 `char-run`。

---

## 帧钩子与逐帧落盘

`flush!` 会触发 `current-frame-hook`（用当前网格调用），用于「每帧」快照：

```racket
(current-frame-hook (λ (g) ...))     ; 设置帧回调（参数）
(current-frame-dedup? #t)             ; 默认开：字符图未变的帧不触发
(frame-end!)                          ; 手动触发一次（同样受去重控制）
(flush!)                              ; 等价于 frame-end!
(frame-reset!)                        ; 清除「上一帧」记录（新会话用）
```

开箱即用的落盘：

```racket
(screen-frame-log-enable! "frames.txt" #:trim-right? #t #:dedup? #t)
(screen-frame-count)      ; 已记录帧数
(screen-frame-log-disable!)
```

`#:dedup?` 为真时跳过与上一帧完全相同的帧（immediate 模式刷屏时很有用）。
文件内容：

```
── frame 1 ──
...字符图...
── frame 2 ──
...
```

---

## 网格模型与解析器（高级）

**网格**（`base-char/screen/grid.rkt`）：

```racket
(struct cell (text fg bg attrs))   ; text: string | " " | #f(宽字符右半格)
(struct grid (cells rows cols cursor-row cursor-col
              fg bg attrs wrap-pending? saved cursor-visible? alt-active?
              scroll-top scroll-bottom))
```

常用：`make-grid`、`grid-ref`、`grid->text`、`blank-cell`、`cell-default?`。

**ANSI 解析器**（`base-char/screen/ansi-parse.rkt`，仅作测试预言机）：

```racket
(make-ansi-parser rows cols)
(ansi-parser-feed-bytes! p bs)
(ansi-parser-feed-string! p s)
(ansi-parser-grid p)          ; → grid
(ansi-parser-diag p)          ; 未识别序列
```

特性：增量（escape / UTF-8 可跨 chunk 分片）、宽字符、`DECSC/DECRC`、
`?1049` 备用缓冲、SGR（16/256/RGB/属性）。

---

## 与 base 的差异与限制

| 项 | 说明 |
|---|---|
| `bytes-append` | 被覆盖为 op 拼接，**仅当前模块**；代价见上文 |
| `format-*` 返回类型 | char 下是 op-seq，不是 bytes；当字节用会在编译期报错（不会静默出错） |
| 硬编码 ANSI 字面量 | 如 `#"\e[2J"` 会被当成普通文本写入网格；只用 `format-*`/`put-*` 则无此问题 |
| `screen-clear` | char 下会额外归位光标（erase + home） |
| 尺寸入口 | 与 base 同签名：`with-tui`/`tui-init` **不接受** `#:rows/#:cols`，尺寸走 `(parameterize ([current-screen-size (cons rows cols)]) ...)` |
| alt buffer | 真正维护主/副双网格（`screen-alt-enable!/disable!`），语义对齐 base 的 `ESC[?1049h/l`：alt 期间主屏内容保留 |
| 输入 | 事件模型/归一化逻辑自带（复制自 base，有对拍测试），**零 FFI**；`read-event/raw` / `read-event-noblock/raw` 为 base 专有（字节级读 stdin），char 不提供 |
| 坐标系 | `get-cursor` 1-based，`screen-cursor` 0-based |

---

## API 速查

| 类别 | 函数 |
|---|---|
| 入口 | `with-tui` `with-tui-nobuffer` `with-tui-nobuffer-echo` `tui-init` `tui-exit` |
| 输出（与 base 同名） | `put-*` `format-*` `cursor-*` `screen-*` `line-*` `buffer-alt-*` `style-*` `put-styled*` |
| 会话 | `current-screen` `current-screen-size` `the-screen` `call-with-screen` `screen-alt-enable!` `screen-alt-disable!` `screen-alt-active?` |
| 字符图 | `char-frame` `screen->text` `screen->lines` `grid->text` `grid->lines` |
| 光标 | `get-cursor` `update-cursor!` `screen-cursor` `screen-cursor-cell` `screen-size` |
| 属性 | `screen-ref` `cell-text/fg/bg/attrs` `style->string` `screen-style-at` `screen-current-style` `screen-styled-cells` `screen-attr-ranges` |
| 输入 | `char-input-push!` `char-input-close!` `char-input-exhausted?` `char-input-open?` `char-input-empty?` `char-input-clear!` `char-input-remaining` `read-event` `read-event-noblock` `build-input` `loop-input*` |
| 运行 | `char-run` `current-frame-hook` `current-frame-dedup?` `frame-end!` `frame-reset!` `flush!` `screen-frame-log-enable!` `screen-frame-log-disable!` `screen-frame-count` |
| 底层 | `make-grid` `grid-ref` `cell?` `blank-cell` `cell-default?` `make-ansi-parser` `ansi-parser-*` |

---

## 测试

```bash
raco test tests/
```

- `tests/screen-test.rkt`：解析器（含分片 fuzz、宽字符、擦除、备用缓冲）
- `tests/char-backend-test.rkt`：op 路径 vs ANSI 解析路径**跨实现对拍**（含 alt buffer）
- `tests/char-app-test.rkt`：脚本输入 / 事件循环 / 帧钩子 / 属性查询
