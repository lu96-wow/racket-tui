# TUI 终端 UI 框架

一个纯 Racket 实现的终端 UI 框架，零外部依赖，基于 ANSI 转义序列和 raw 终端模式。

## 快速开始

```racket
#lang racket
(require "ui/main.rkt")

(define t-title  (make-text #:text " Demo " #:style 'heading))
(define t-body   (make-text #:text " body " #:style 'info))
(define t-footer (make-text #:text " q to quit " #:style 'dim))

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

## 布局系统

基于权重比例分配空间，返回 `layout`，可嵌套。

```racket
(layout-row (thing weight) ...)   ;; 垂直排列
(layout-col (thing weight) ...)   ;; 水平排列
(border inner #:title "..." ...)  ;; 套边框
(screen (thing weight) ...)       ;; 填满终端
space                              ;; 空白占位
```

`thing` 可以是 component、`space`、或嵌套的 `layout`。嵌套 layout 需要套一层权重：`((layout-row ...) weight)`。

详见 [layout.md](layout.md)。

## 组件

| 组件 | 文档 |
|---|---|
| `make-text` | [text.md](text.md) |
| `make-input` | [input.md](input.md) |
| `make-button` | [button.md](button.md) |
| `make-output` | [output.md](output.md) |
| `make-border` | [border.md](border.md) |

所有组件遵循 [component 协议](component.md)。

## 事件循环

- **阻塞模式** (`run-app spec`): 等同 `ncurses getch()`
- **非阻塞模式** (`run-app-noblock spec`): 等同 `ncurses timeout(0) getch()`

`run-app` 接受 `layout`（resize 自动重算）或裸 `spec-list`（固定坐标）。
