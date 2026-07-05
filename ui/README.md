# TUI UI 层文档

基于 `base/` 终端抽象之上的组件化 UI 框架。

## 快速开始

```racket
#lang racket
(require tui/ui
         tui/base/io/output-color)

(style-define! 'bg-title  (color256-bg 237) (color256-fg 255))
(style-define! 'bg-body   (color256-bg 235) (color256-fg 250))
(style-define! 'bg-footer (color256-bg 240) (color256-fg 255))

(define t-title  (make-text #:text " Demo " #:style 'bg-title))
(define t-body   (make-text #:text " body " #:style 'bg-body))
(define t-footer (make-text #:text " q to quit " #:style 'bg-footer))

(run-app
 (screen
  (t-title 1)
  (t-body 6)
  (t-footer 1)))
```

按 `q` 退出。resize 终端窗口时布局自动重算。

## 架构

```
┌──────────────────────────────────────────────────────────┐
│  run-app (ui/run.rkt)                                    │
│  ├─ layout 解析 → spec-list                              │
│  ├─ resize 事件 → 重算 layout → 更新 spec-list            │
│  ├─ render-all  — 增量绘制 + 缓存回放                     │
│  ├─ global      — q=quit, 鼠标切焦点                     │
│  ├─ mouse-router— 鼠标事件空间分发                        │
│  └─ dispatch    — 键盘事件 → 焦点组件                     │
├──────────────────────────────────────────────────────────┤
│  layout (ui/layout.rkt)                                  │
│  ├─ layout-row / layout-col — 权重布局                   │
│  ├─ screen — 填满终端                                    │
│  ├─ border — 边框包装                                    │
│  └─ space — 空白占位                                     │
├──────────────────────────────────────────────────────────┤
│  component (ui/component.rkt + widgets/)                 │
│  ├─ make-text     — 静态/动态文本                         │
│  ├─ make-input    — 文本输入框                            │
│  ├─ make-button   — 按钮                                 │
│  ├─ make-bool-button — 布尔开关                          │
│  ├─ make-output   — 可滚动输出面板（折叠块）               │
│  └─ make-border   — 边框组件                              │
├──────────────────────────────────────────────────────────┤
│  底层 (base/)                                             │
│  ├─ gap-buffer   — 纯文本缓冲区                           │
│  ├─ output-buffer— 输出行缓冲（换行+折叠）                 │
│  ├─ build-input  — 输入事件分发器                         │
│  └─ output/*     — ANSI 输出 & 样式                       │
└──────────────────────────────────────────────────────────┘
```

## 入口

| 入口 | 说明 |
|---|---|
| `(run-app spec ...)` | 阻塞事件循环，等同 `ncurses getch()` |
| `(run-app-noblock spec ...)` | 非阻塞事件循环，等同 `ncurses timeout(0) getch()` |
| `(run-app-nobuffer spec ...)` | 阻塞模式，使用主 buffer（不启用 alt screen） |
| `(run-app-nobuffer-noblock spec ...)` | 非阻塞模式，使用主 buffer |

`spec` 可以是 `layout`（resize 自动重算）或裸 `(comp x y w h)`（固定坐标）。

多个裸 spec 会自动展开：

```racket
(run-app
 (comp-a 1 1 40 1)    ;; 等价于 (list comp-a 1 1 40 1)
 (comp-b 1 3 40 5))
```

---

## 布局系统

基于权重比例分配空间。详见 [ui-doc/layout.md](../ui-doc/layout.md)。

```racket
(layout-row (thing weight) ...)   ;; 垂直排列
(layout-col (thing weight) ...)   ;; 水平排列
(border inner #:title "..." ...)  ;; 套边框，内容内缩 1
(screen (thing weight) ...)       ;; 填满终端
space                              ;; 空白占位
```

`thing` 可以是 component、`space`、或嵌套的 layout。嵌套 layout 需套一层权重：

```racket
(run-app-noblock
 (screen
  (t-title 1)
  ((layout-col
    ((border (layout-row (panel-a 1)) #:title "Files") 1)
    (space 1)
    ((border (layout-row (panel-b 1)) #:title "Log") 1)) 6)
  ((layout-col (input-field 1) (toggle 1)) 1)
  (t-status 1)))
```

---

## 组件

所有组件遵循 [component 协议](../ui-doc/component.md)。

### make-text — 文本标签

静态或动态文本，无焦点，仅展示。详见 [ui-doc/text.md](../ui-doc/text.md)。

```racket
(make-text
 #:text    "Hello"              ; string / box / (-> string)
 #:style   'info                ; 样式名，默认 'info
 #:h-align 'left)               ; 'left / 'center / 'right，默认 'left
```

**三种模式：**

| 模式 | 语法 | 开销 |
|---|---|---|
| 静态 | `#:text "hello"` | 零 per-frame |
| box | `#:text some-box` | 每帧 unbox + 比对 |
| lambda | `#:text (λ () (format ...))` | 每帧调用 + 比对 |

```racket
;; 静态
(define label (make-text #:text "Static text" #:style 'info))

;; Box 动态
(define counter (box 0))
(define status (make-text #:text counter #:style 'success))

;; Lambda 动态
(define clock (make-text #:text (λ () (format "~a" (current-seconds)))
                         #:style 'heading))
```

### make-input — 文本输入框

多行编辑，Gap Buffer，pref-col 列记忆。详见 [ui-doc/input.md](../ui-doc/input.md)。

```racket
(make-input
 #:placeholder   "Enter text..."    ; 空状态占位
 #:initial-text  "hello"            ; 初始内容
 #:style         'input-focus       ; 聚焦样式
 #:nofocus-style 'input-normal      ; 非聚焦样式
 #:on-submit     (λ (text) ...)     ; Enter 提交回调
 #:on-change     (λ (text) ...))    ; 每次编辑回调
```

| 按键 | 行为 |
|---|---|
| 可打印字符 / UTF-8 | 插入 |
| Escape | 插入换行 |
| Backspace / Delete | 删除 |
| ← → ↑ ↓ | 移动光标（↑↓ 含 pref-col 列记忆） |
| Home / End | 行首/行尾 |
| Enter | 提交 |
| 鼠标左键/拖拽 | 定位光标 |
| Paste | 粘贴 |

### make-button — 按钮

点击或按键激活。详见 [ui-doc/button.md](../ui-doc/button.md)。

```racket
(make-button
 #:text        "Click Me"      ; 文字（前后自动加空格）
 #:on-activate (λ () ...)      ; 激活回调
 #:style       'button)        ; 样式
```

| 操作 | 行为 |
|---|---|
| 鼠标按下 | 切换 `button-pressed` 样式 |
| 鼠标释放（在按钮上） | 调用 `on-activate` |
| Enter / Space（聚焦时） | 调用 `on-activate` |

### make-bool-button — 布尔开关

Toggle 开关组件。详见 [ui-doc/bool-button.md](../ui-doc/bool-button.md)。

```racket
(make-bool-button
 #:label      "Option"      ; 显示文字
 #:initial?   #f            ; 初始状态
 #:on-change  (λ (v) ...)   ; 状态变化回调，参数为布尔值
 #:on-style   'success      ; 开 样式
 #:off-style  'info)        ; 关 样式
```

渲染：`[x] Option`（开）/ `[ ] Option`（关）。鼠标左键或 Enter/Space 切换。

### make-output — 可滚动输出面板

带滚动条和折叠块的输出缓冲区。返回两个值：组件 + 操作 API。详见 [ui-doc/output.md](../ui-doc/output.md)。

```racket
(define-values (comp api)
  (make-output
   #:max-lines    500      ;; 最大行数
   #:style        'info    ;; 默认样式
   #:auto-scroll?  #t      ;; 自动滚到底
   #:bar-width    1))      ;; 滚动条宽度
```

**API：**

```racket
(append api "text")                     ;; 追加文本
(append-styled api "text" 'error)       ;; 追加带样式文本
(clear api)                             ;; 清空
(scroll-end api)                        ;; 滚到底
(begin-fold api)  → block-id            ;; 开始折叠块
(end-fold api)                          ;; 结束折叠块
(toggle-fold api block-id)              ;; 折叠/展开
```

**折叠块示例：**

```racket
(append-styled api "▼ Errors" 'error)
(append api "\n")
(define bid (begin-fold api))
(for ([i 3])
  (append api (format "  error ~a\n" i)))
(end-fold api)
;; 点击 "▼ Errors" 行可折叠/展开
```

**交互：** ↑↓ 滚动、PageUp/PageDown 翻页、Home/End 到顶/底、鼠标滚轮滚动、拖拽滚动条、点击折叠块标题切换折叠。

### make-border — 边框组件

纯渲染组件，四边独立开关 + 独立样式。通常通过 `border` 布局宏使用。详见 [ui-doc/border.md](../ui-doc/border.md)。

```racket
(make-border
 #:up?         #t           ;; 各边开关
 #:down?       #t
 #:left?       #t
 #:right?      #t
 #:up-style    'info        ;; 各边样式
 #:down-style  'info
 #:left-style  'info
 #:right-style 'info
 #:title       #f)          ;; 上边中间文字
```

通常不直接使用，通过 `border` 包装：

```racket
(border (layout-row (content 1))
        #:title "Panel"
        #:up-style 'heading)
```

---

## Component 协议

```racket
(struct component
  (render handler focusable? show? w h dirty render?)
  #:transparent)
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `render` | `(focused? x y w h → void)` | 绘制回调 |
| `handler` | `(type data mods → void)` | 事件处理，`build-input` 构造 |
| `focusable?` | bool | 是否可获取键盘焦点 |
| `show?` | bool / box / thunk | 可见性 |
| `w` `h` | natural | 期望尺寸（0=由 spec 决定） |
| `dirty` | box[bool] | 标记需重绘，框架绘后置 `#f` |
| `render?` | `#f` / `(x y w h focused? → void)` | pre-render hook |

**可见性操作：**

```racket
(component-visible? comp)     ;; 查询（兼容 bool/box/thunk）
(component-show! comp)        ;; 显示（仅 box 可写）
(component-hide! comp)        ;; 隐藏
(component-toggle! comp)      ;; 切换
```

---

## 样式系统

预定义样式（`base/io/output-styles.rkt`）：

| 样式 | 说明 |
|---|---|
| `red` `green` `blue` `yellow` `cyan` `magenta` `white` | 基础颜色 |
| `error` `warning` `info` `success` | 语义化 |
| `title` `subtitle` `heading` `dim` | 标题 |
| `button` `button-pressed` | 按钮 |
| `input-normal` `input-focus` | 输入框 |
| `cursor` `selection` | 光标/选择 |
| `border` `border-bold` | 边框 |
| `scroll-track` `scroll-thumb` | 滚动条 |
| `status-bar` `status-good` `status-warning` `status-bad` | 状态栏 |

**自定义样式：**

```racket
(style-define! 'my-style (color256-bg 235) (color256-fg 255) attr-bold)
```

**样式回退：** 256 色自动回退 16 色：

```racket
(style-define! 'panel
  (color-fg* 255 7)    ;; 256 色 255，回退 16 色 7 (white)
  (color-bg* 238 0))   ;; 256 色 238，回退 16 色 0 (black)
```

---

## 完整示例

### 多面板 + 输入

```racket
#lang racket
(require tui/ui tui/base/io/output-color)

(style-define! 'bg (color256-bg 235) (color256-fg 255))
(style-define! 'input-style (color256-bg 236) (color256-fg 255))

(define-values (out api) (make-output #:style 'bg #:max-lines 100))
(define inp (make-input #:style 'input-style
                        #:on-submit (λ (txt) (append api (format "> ~a\n" txt)))))

(run-app-noblock
 (screen
  ((make-text #:text " Demo " #:style 'heading) 1)
  ((layout-col
    (out 1)
    (space 1)
    (inp 1)) 6)
  ((make-text #:text " q to quit " #:style 'dim) 1)))
```

### 按钮 + 状态切换

```racket
#lang racket
(require tui/ui)

(define last-action (box "none"))

(run-app
 ((make-text #:text (λ () (format "Last: ~a" (unbox last-action)))
             #:style 'title)
  1 1 40 1)
 ((make-button #:text "A"
               #:on-activate (λ () (set-box! last-action "a"))) 2 3 0 0)
 ((make-button #:text "B"
               #:on-activate (λ () (set-box! last-action "b"))) 3 5 0 0))
```

### 组件可见性控制

```racket
(define btn-a
  (make-button #:text "Vanish"
               #:on-activate (λ () (component-hide! btn-a))))

(define btn-b
  (make-button #:text "Toggle A"
               #:on-activate (λ () (component-toggle! btn-a))))

(run-app
 (btn-a 2 3 0 0)
 (btn-b 2 5 0 0))
```

---

## 事件循环

**全局处理器** `make-global`：`q` 退出 + 鼠标点击切换键盘焦点。

**鼠标路由** `make-mouse-router`：空间分发 + capture（拖拽时锁定目标）。

**事件分发** `make-dispatcher`：resize → recalc + 广播所有组件；keyboard → 焦点组件。

**渲染引擎** `make-renderer`：单个 `write-bytes`，零闪烁。bounds 不变时只重绘脏组件，bounds 变化时全量清屏 + 缓存回放。

---

## 与 base/ 的关系

UI 层 (`ui/`) 是对底层终端库 (`base/`) 的高层封装：

```
ui/
├── main.rkt           ;; 聚合入口
├── run.rkt            ;; 事件循环 (阻塞/非阻塞)
├── run/render.rkt     ;; 渲染引擎 (增量绘制)
├── run/focus.rkt      ;; 全局 (q=quit, 鼠标切焦点)
├── run/mouse.rkt      ;; 鼠标路由 (空间分发)
├── run/dispatch.rkt   ;; 事件分发 (resize/keyboard)
├── layout.rkt         ;; 权重布局系统
├── component.rkt      ;; 组件协议
├── gap-buffer.rkt     ;; 纯文本缓冲区
├── output-buffer.rkt  ;; 输出行缓冲 (换行+折叠)
├── widgets/
│   ├── text.rkt       ;; make-text
│   ├── input.rkt      ;; make-input
│   ├── button.rkt     ;; make-button
│   ├── bool-button.rkt;; make-bool-button
│   ├── output.rkt     ;; make-output
│   ├── border.rkt     ;; make-border
│   └── scrollbar.rkt  ;; 滚动条
└── ...

base/
├── tui.rkt            ;; 底层聚合
├── io/output.rkt      ;; ANSI 输出 (put-*)
├── io/output-styles.rkt ;; 样式系统
├── io/output-color.rkt  ;; 颜色定义
├── io/input.rkt       ;; 输入 (read-event)
├── io/build-input.rkt ;; 事件分发器
└── ...
```
