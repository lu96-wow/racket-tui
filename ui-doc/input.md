# Input — 文本输入框

支持多行编辑，Gap Buffer 存储，惰性水平滚动，pref-col 列记忆。

## 创建

```racket
(make-input
  #:placeholder  "Enter text..."    ; 空状态占位文本，默认 ""
  #:initial-text "hello"            ; 初始内容，默认 ""
  #:on-submit    (λ (text) ...)     ; 提交回调，默认 void
  #:on-change    (λ (text) ...))    ; 编辑回调，默认 void
```

## 交互

| 按键 | 行为 |
|---|---|
| 可打印字符 / UTF-8 | 插入 |
| Escape | 插入换行 |
| Backspace / Delete | 删除 |
| ← → ↑ ↓ | 移动光标（↑↓ 含 pref-col 列记忆） |
| Home / End | 行首/行尾 |
| Enter | 提交（调用 `on-submit`） |
| 鼠标左键/拖拽 | 定位光标 |
| Paste | 粘贴 |

无需 `#:multiline?` 参数——不想多行就不按 Escape，上下键在单行时天然 no-op。

## Pref-col 列记忆

上下移动时保持之前的 display-width 列：

```
长行: hello world      ← 光标在 'w' (col 6)
短行: hi               ← ↓ 后夹紧到行尾 (col 2)
长行: another line     ← ↓ 恢复到 col 6 (pref-col 不变)
```

## 回调

### on-submit : `(string → void)`

Enter 时调用，参数为完整 buffer 文本（含所有换行）。

### on-change : `(string → void)`

每次编辑后调用。

## 样式

| 状态 | 样式 |
|---|---|
| 无焦点 | `input-normal` |
| 聚焦 | `input-focus` |
| 光标 | `cursor` |

## 实现

两层架构：`base/gap-buffer.rkt`（纯数据） + `ui/widgets/input.rkt`（渲染），零渲染依赖。
