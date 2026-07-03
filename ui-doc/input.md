# Input — 文本输入框

多行编辑，Gap Buffer，惰性滚动，pref-col 列记忆。format- 一次性写 bytes。

## 创建

```racket
(make-input
  #:placeholder   "Enter text..."    ; 空状态占位，默认 ""
  #:initial-text  "hello"            ; 初始内容，默认 ""
  #:style         'input-focus       ; 聚焦时样式，默认 'input-focus
  #:nofocus-style 'input-normal      ; 非聚焦 + 背景底色，默认 'input-normal
  #:on-submit     (λ (text) ...)     ; 提交回调，默认 void
  #:on-change     (λ (text) ...))    ; 编辑回调，默认 void
```

## 交互

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

## Pref-col 列记忆

上下移动时保持之前的 display-width 列，短行夹紧、回长行恢复。

## 回调

- **on-submit** `(string → void)` — Enter 时调用，参数为完整 buffer 文本
- **on-change** `(string → void)` — 每次编辑后调用

## 样式

| 状态 | 参数 | 默认 |
|---|---|---|
| 聚焦文字 | `#:style` | `input-focus` |
| 非聚焦 + 背景 | `#:nofocus-style` | `input-normal` |
| 光标 | — | `cursor` |
