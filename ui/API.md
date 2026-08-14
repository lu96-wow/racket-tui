# ui API 文档

声明式 TUI 层。入口：`(require tui/ui)`。

数据流：

```
state ──view──▶ widget ──layout──▶ element ──render──▶ surface
  ▲                                                    │
  └── update ◀─ message ◀─ route-event ◀─ read-event ◀─┘
```

---

## 一、核心

### surface.rkt — 格点缓冲 + diff

```racket
(cell ch style)            ; ch: char, style: 样式名或 #f
(make-surface rows cols)   ; 新建缓冲
(surface-put! s r c ch style)
(surface-put-string! s r c str style)
(surface-ref s r c)
(surface->ascii s ...)     ; 见 ascii-dump
(surface-diff-bytes s prev) ; 生成 ANSI bytes（prev 可 #f）
```

### widget.rkt — widget 值 + 容器

```racket
;; widget 结构
(widget key kind props children)   ; 不可变值

;; 容器（vstack/hstack 的子节点用 child 加约束）
(vstack child-item ...)     ; 垂直
(hstack child-item ...)     ; 水平
(panel child #:title #:style) ; 带边框容器，子节点内缩 (1,1,-2,-2)
(rect child #:x #:y #:w #:h)  ; 绝对定位

;; 子节点约束
(child w #:weight 1 #:min 0 #:max +inf.0)
;; child-item 也可是裸 widget（权重 1）
```

### layout.rkt — 树布局/命中/焦点

```racket
(resolve w x y w h)     ; widget 树 → element 树
(element-hit elem x y)  ; 命中最上层 leaf（panel 边框不参与）
(element-focusables elem) ; DFS 焦点顺序
```

### render.rkt — 渲染

```racket
(render-element! e surf rctx)   ; element 树 → surface
(make-render-ctx #:focus-key #:local-table)
(widget-ctx w rctx)             ; 构造某 widget 的 ctx
```

### ascii-dump.rkt — 调试快照

```racket
(surface->ascii s
  #:mode 'grid | 'plain | 'compact
  #:legend-order 'sorted | 'first-use
  #:space-char #\space
  #:show-sgr? #f
  #:stats? #f)
(display-surface s ...)          ; 直接打印
```

### run.rkt — 事件循环

```racket
(run-app
  #:init   initial-state
  #:update update-fn
  #:view   view-fn
  #:keymap '((key . message) ...))

(run-app-noblock ...)  ; 非阻塞
```

- `view : state → widget`（纯函数）
- `update : state × message → state`（纯函数）
- `run-app` 返回最终 state
- keymap 键：`#\q`、`'tab`、`'backtab`、`'enter`、`'space`、`'backspace`、`'escape`、方向/功能键

保留消息：

| 消息 | 含义 |
|---|---|
| `'ui-quit` | 退出 |
| `'ui-focus-next` / `'ui-focus-prev` | 焦点前/后 |

### leaf — 自定义叶节点协议

```racket
(leaf #:key #f
      #:size '(0 . 0)          ; 期望尺寸
      #:render (λ (w rect ctx surf) ...)
      #:on-event (λ (w type data rect ctx) → message-or-#f)
      #:focusable? #f
      #:local (λ () 初始值))    ; keyed local state（需 #:key）
```

ctx 含：

| 字段 | 含义 |
|---|---|
| `'focus-key` | 当前聚焦 leaf 的 key（或 #f） |
| `'local` | 本 widget 的 keyed local state 值 |
| `'set-local!` | `(λ (v) ...)` 更新本 widget 局部状态 |

on-event 的 `type` 是归一化后的语义 key：`'enter` `'space` `'up` `'down` … `'mouse` `'paste` `'resize`，或可打印字符（如 `#\a`）。

---

## 二、组件

所有组件都是纯函数，返回 `leaf`。除特别说明外，`#:key` 都用于 keyed local state 或焦点。

### text

```racket
(text str #:style 'info #:h-align 'left #:key #f)
```

内容直接从 state 取值。`#:h-align`：`'left`/`'center`/`'right`。

### button

```racket
(button label
        #:on-activate #f      ; 消息值
        #:style 'button
        #:pressed-style 'button-pressed
        #:key #f)
```

激活：Enter/Space；鼠标在按钮内按下→释放。`#:key` 给了才有按下视觉反馈。

### bool-button

```racket
(bool-button label
             #:value #f
             #:on-toggle #f      ; 消息值
             #:on-style 'success
             #:off-style 'info
             #:key #f)
```

渲染 `[x] label` / `[ ] label`。激活返回 `#:on-toggle`，由 update 翻转 `#:value`。

### input（单行）

```racket
(input #:value ""
       #:on-change (λ (t) ...)  ; string → message
       #:on-submit (λ (t) ...)  ; string → message
       #:style 'input-focus
       #:nofocus-style 'input-normal
       #:placeholder ""
       #:key #f)
```

文本在 app state；光标是 keyed local state。支持插入/Backspace/Delete/←→/Home/End/鼠标定位/Enter 提交。

### text-area（多行）

```racket
(text-area #:value ""
           #:on-change (λ (t) ...)
           #:on-submit (λ (t) ...)
           #:style 'input-focus
           #:nofocus-style 'input-normal
           #:placeholder ""
           #:key #f)
```

Escape 插入换行；↑↓ 含 pref-col 列记忆；垂直+水平滚动。

### list-box

```racket
(list-box #:items '()          ; (listof string)
          #:selected #f        ; 选中索引（app state）
          #:on-select (λ (i) ...)  ; number → message
          #:style 'info
          #:selected-style 'selection
          #:scrollbar-width 1
          #:key #f)
```

↑↓/Home/End/PageUp/PageDown 移动选中；滚轮/滚动条拖动滚动；点击选中。

### output（可滚动日志 + 折叠）

```racket
(output #:lines '()
        #:folded '()           ; 折叠的 block-id 列表（app state）
        #:on-toggle-fold (λ (id) ...)  ; number → message
        #:style 'info
        #:auto-scroll? #t
        #:scrollbar-width 1
        #:key #f)
```

line 类型：

```racket
;; string
;; (cons string style)
;; (fold-block id header body)
(fold-block id header body)  ; header: string 或 (cons string style)
                             ; body: (listof line)，可嵌套
```

头行自动加 `▼`/`▶`；点击头产生 `#:on-toggle-fold` 消息；折叠状态在 app state。

### scrollbar（纯函数）

```racket
(scrollbar-render surf x y w h total scroll)
(scrollbar-scroll-from-y my y h total)  ; 鼠标 y → scroll
(scrollbar-metrics h total)             ; → (thumb-h track-range range)
```

不持有状态，由 list/output 配合 keyed local state 使用。

---

## 三、样式

样式名由 `base/io/output-styles.rkt` 预定义，也可 `(style-define! 'name ...)` 自定义。

常用：`info` `success` `warning` `error` `heading` `title` `dim` `button` `button-pressed` `selection` `input-focus` `input-normal` `cursor` `border` `scroll-track` `scroll-thumb`。

---

## 四、测试

```bash
racket ui-demo/run-tests.rkt   # 运行全部 8 个测试文件
```
