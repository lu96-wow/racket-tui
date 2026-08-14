# ui-rebuild — 声明式 UI 核心

这是对 `ui/` 的声明式重写（核心部分）。**只含核心，不含组件**（`text`/`button`/`input`/`list` 等延后到组件层）。

## 数据流

```
state ──view──▶ widget ──layout──▶ element ──render──▶ surface
  ▲                                                    │
  └── update ◀─ message ◀─ route-event ◀─ read-event ◀─┘
```

- `state`：用户定义的不可变状态
- `view`：纯函数 `(state → widget)`
- `widget`：不可变值，真正的树（容器持有子节点）
- `element`：`widget + rect`，由布局生成
- `surface`：格点缓冲，widget 只写格点，渲染器 diff 后写屏
- `message`：事件产生的消息，交给 `update` 归约

## 模块

| 文件 | 职责 |
|---|---|
| `surface.rkt` | cell buffer + diff → ANSI |
| `widget.rkt` | widget 值 + `leaf`/`vstack`/`hstack`/`panel`/`rect` |
| `layout.rkt` | 树状布局、命中测试、焦点顺序 |
| `render.rkt` | element 树 → surface（含 panel 边框） |
| `ascii-dump.rkt` | `surface->ascii` — 调试快照（ASCII 描述） |
| `widgets/text.rkt` | `text` 文本标签 |
| `widgets/button.rkt` | `button` 按钮 |
| `widgets/bool-button.rkt` | `bool-button` 布尔开关 |
| `widgets/input.rkt` | `input` 单行输入框 |
| `widgets/scrollbar.rkt` | 滚动条渲染/拖拽换算（纯函数） |
| `widgets/list.rkt` | `list-box` 可滚动列表 |
| `widgets/output.rkt` | `output` 可滚动日志面板 |
| `widgets/text-area.rkt` | `text-area` 多行输入框 |
| `run.rkt` | `run-app` 消息循环 |

## 用法

```racket
#lang racket
(require tui/ui-rebuild)

(struct model (count) #:transparent)

(define (update st msg)
  (match msg ['inc (struct-copy model st [count (add1 (model-count st))])]
              [_ st]))

(define (view st)
  (vstack
   (panel (leaf #:key 'counter #:focusable? #t
                #:render   (λ (w rect ctx surf)
                             (match-let ([(list x y w h) rect])
                               (define focused? (equal? (hash-ref ctx 'focus-key #f)
                                                        (widget-key w)))
                               (surface-put-string! surf y x
                                 (format "count: ~a" (model-count st))
                                 (if focused? 'selection 'info))))
                #:on-event (λ (w t d rect ctx) (if (eq? t 'up) 'inc #f)))
          #:title "Counter")))

(run-app
 #:init   (model 0)
 #:update update
 #:view   view
 #:keymap (list (cons #\q msg-quit)
                (cons 'tab msg-focus-next)))
```

## 组件

### text

```racket
(text "hello" #:style 'info #:h-align 'left #:key #f)
```

内容直接从 state 取值（view 每帧重建，无 lambda/box 模式）。`#:h-align`：`'left`/`'center`/`'right`。

> on-event 的 `type` 参数是归一化后的语义 key：`'enter` `'space` `'up` `'down` … `'mouse` `'paste` `'resize`，或可打印字符（如 `#\a`）。

### button

```racket
(button "Submit" #:on-activate 'submit #:style 'button #:key 'b)
```

- `#:on-activate` 是一个**消息值**（view 里可直接算出）
- 激活：Enter/Space（聚焦时）；鼠标在按钮内按下→释放（拖出则不激活）
- `#:key` 可选；给了才有点击按下的 `#:pressed-style` 视觉反馈（keyed local state）

### bool-button

```racket
(bool-button "Option" #:value #f #:on-toggle 'toggle
             #:on-style 'success #:off-style 'info #:key #f)
```

状态提升到 app state：`#:value` 是当前值，激活返回 `#:on-toggle` 消息，由 `update` 翻转。

### input（单行）

```racket
(input #:value "hello"
       #:on-change (λ (t) (list 'input t))
       #:on-submit (λ (t) (list 'submit t))
       #:placeholder "..." #:key #f)
```

- 文本在 app state；光标是 keyed local state（需 `#:key`）
- 支持插入/Backspace/Delete/←→/Home/End/鼠标定位/Enter 提交
- 单行、水平滚动保证光标可见

### list-box（可滚动列表）

```racket
(list-box #:items '("a" "b" "c")
          #:selected 0
          #:on-select (λ (i) (list 'select i))
          #:style 'info #:selected-style 'selection #:key #f)
```

- 选中索引在 app state；滚动偏移是 keyed local state（需 `#:key`）
- ↑↓/Home/End/PageUp/PageDown 移动选中；滚轮/滚动条拖动滚动（拖拽捕获）

### output（可滚动日志，含折叠块）

```racket
(output #:lines (list "log1"
                     (fold-block 'errors (cons "Errors" 'error) (list "e1" "e2")))
        #:folded '()
        #:on-toggle-fold (λ (id) (list 'toggle id))
        #:style 'info #:auto-scroll? #t #:key #f)
```

- 内容在 app state（`#:lines`）；追加日志由 `update` 在 state 里加行
- 支持 `(cons text style)` 单行样式；滚动偏移是 keyed local state
- `fold-block`：头行可点击折叠/展开（`#:folded` 是 app state 的 block-id 列表，点击产生 `#:on-toggle-fold` 消息）；支持嵌套
- ↑↓/Home/End/PageUp/PageDown/滚轮/滚动条拖动滚动；`#:auto-scroll?` 新行时自动滚到底

### text-area（多行输入）

```racket
(text-area #:value "line1\nline2"
           #:on-change (λ (t) (list 'input t))
           #:on-submit (λ (t) (list 'submit t))
           #:key #f)
```

- 文本在 app state；光标 + pref-col 是 keyed local state（需 `#:key`）
- 编辑用纯字符串操作；Escape 插入换行；↑↓ 含 pref-col 列记忆
- 垂直 + 水平滚动保证光标可见

## 布局约束（min/max）

`vstack`/`hstack` 的子节点可用 `child` 附加权重与最小/最大尺寸（主轴方向）：

```racket
(vstack
  (child title #:min 1 #:max 1)       ;; 固定 1 行
  (child body  #:weight 6 #:min 3)    ;; 权重 6，至少 3 行
  (child foot  #:weight 1 #:max 1))   ;; 最多 1 行
```

- `#:weight` 默认 1；`#:min` 默认 0；`#:max` 默认 `+inf.0`
- 算法：先按权重比例，再迭代 clamp 到 [min,max] 并重分配剩余空间
- `max` 是硬上限；`min` 是硬下限，若所有 min 之和超限则溢出（surface 裁剪）

## keyed local state（框架局部状态）

UI 局部状态（光标、滚动位置等）不必提升到 app state。leaf 用 `#:key` + `#:local` 声明，框架按 key 跨帧持久化，卸载时自动清理：

```racket
(leaf #:key 'panel #:local (λ () 0)
      #:focusable? #t
      #:render (λ (w rect ctx surf)
                 (surface-put-string! surf y x
                   (format "local: ~a" (hash-ref ctx 'local)) 'info))
      #:on-event (λ (w t d rect ctx)
                   ((hash-ref ctx 'set-local!) (add1 (hash-ref ctx 'local)))
                   #f))
```

ctx 含 `'focus-key` / `'local` / `'set-local!`。

## 鼠标拖拽捕获

press 命中后，后续 move/release/scroll 优先发给捕获目标（即使指针移出），release 时清除捕获。滚动条拖拽、文本选择都依赖它。

## 保留消息

| 消息 | 含义 |
|---|---|
| `msg-quit` (`'ui-quit`) | 退出循环，返回最终 state |
| `msg-focus-next` / `msg-focus-prev` | 焦点前/后移动 |

keymap 可绑定的特殊键：`'tab` `'backtab`(shift-tab) `'enter` `'space` `'backspace` `'escape` 及方向/功能键。

## 调试：ASCII 描述快照

把 surface 渲染成可读、可 diff、可断言的 ASCII 文本（无需真实终端）：

```racket
(display-surface surf #:space-char #\·)
;; Legend (2 styles + default):
;;   . default
;;   A info
;;   B selection
;; style: AAAAA.....
;; text : HELLO·····
;; ...
```

`#:mode 'grid`（默认，内容行 + 样式行）/ `'plain`（只内容）/ `'compact`（单行）。

## 关键性质

- widget 是**纯数据**，不持有 box、不产生副作用，每帧从 state 重建
- 容器是**真父子**：`panel` 边框不参与命中测试，不会吞内部节点的鼠标事件
- 渲染是**格点 diff**：无 `dirty` box、无 per-component 字节缓存
- `run-app` 返回最终 state，可测试、可组合
