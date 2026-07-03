# TUI 终端 UI 框架

一个纯 Racket 实现的终端 UI 框架，零外部依赖，基于 ANSI 转义序列和 raw 终端模式。

## 快速开始

```racket
#lang racket
(require "ui/main.rkt")

(define specs
  (list
    (list (make-text #:text "Hello, TUI!" #:style 'title) 1 1 20 1)
    (list (make-input #:placeholder "type...")              2 3 20 1)))

(run-app specs)
```

按 `q` 退出。

## 架构

```
┌─────────────────────────────────────────────────┐
│  run-app (ui/run.rkt)                           │
│  ├─ render-all  — 渲染引擎，增量绘制 + 缓存回放  │
│  ├─ global      — 全局快捷键 (q=quit, 鼠标切焦点) │
│  ├─ mouse-router— 鼠标事件空间分发              │
│  └─ dispatch    — 键盘事件 → 焦点组件            │
├─────────────────────────────────────────────────┤
│  component 协议 (ui/component.rkt)              │
│  ├─ make-text   — 静态/动态文本                  │
│  ├─ make-input  — 文本输入框 (单行/多行)         │
│  └─ make-button — 按钮                          │
├─────────────────────────────────────────────────┤
│  底层 (base/)                                    │
│  ├─ gap-buffer  — 纯文本缓冲区 (gap buffer)       │
│  ├─ build-input — 输入事件分发器                  │
│  └─ output/*    — ANSI 输出 & 样式              │
└─────────────────────────────────────────────────┘
```

## 组件协议

所有组件都是 `component` 结构体，字段：

| 字段 | 类型 | 说明 |
|---|---|---|
| `render` | `(focused? x y w h → void)` | 绘制函数，框架传入视口坐标 |
| `handler` | `(type data mods → void)` | 事件处理，由 `build-input` 构造 |
| `focusable?` | bool | 是否可获取键盘焦点 |
| `show?` | bool | 是否可见 |
| `w` `h` | natural | 期望尺寸（0=自动） |
| `dirty` | box | 标记需要重绘 |
| `render?` | `#f` 或 hook | 每帧检查是否需要标记 dirty |

## 布局

`run-app` 接受 `(list (list component x y w h) ...)`，坐标原点是终端左上角 `(1, 1)`。

组件按列表顺序绘制——后面的覆盖前面的。鼠标事件按**逆序**分发（上层优先）。

## 样式

预定义语义化样式，见 `base/io/output-styles.rkt`：

| 类别 | 样式名 |
|---|---|
| 基础色 | `red green blue yellow cyan magenta white` |
| 语义 | `error warning info success` |
| 输入 | `input-normal input-focus input-error` |
| 光标 | `cursor selection` |
| 文本 | `title subtitle heading` |
| 按钮 | `button button-hover button-pressed button-disabled` |
| 状态栏 | `status-bar status-good status-warning status-bad` |

自定义样式：`(style-define! 'my-style (color-fg 3) attr-bold)`

## 事件循环

- **阻塞模式** (`run-app specs`): 等同 `ncurses getch()`
- **非阻塞模式** (`run-app specs #:noblock? #t`): 等同 `ncurses timeout(0) getch()`
