# Input — 文本输入框

支持单行/多行模式，Gap Buffer 存储，惰性水平滚动，pref-col 列记忆。

## 创建

```racket
(make-input
  #:placeholder  "Enter text..."    ; 空状态占位文本，默认 ""
  #:multiline?   #t                 ; 多行模式，默认 #f
  #:initial-text "hello"            ; 初始内容，默认 ""
  #:on-submit    (λ (text) ...)     ; 提交回调，默认 void
  #:on-change    (λ (text) ...))    ; 编辑回调，默认 void
```

## 返回值

一个 `component`，focusable，可放入 `run-app` 的 specs 列表。

## 交互

### 单行模式 (`multiline? = #f`)

| 按键 | 行为 |
|---|---|
| 可打印字符 (32-126) | 插入 |
| UTF-8 字符 | 插入 |
| Backspace / Delete | 删除 |
| ← → | 移动光标 |
| Home / End | 行首/行尾 |
| Enter | 提交（调用 `on-submit`） |
| 鼠标左键 | 定位光标 |
| 鼠标拖拽 | 定位光标 |

`\n` 会被过滤，无法输入换行。

### 多行模式 (`multiline? = #t`)

| 按键 | 行为 |
|---|---|
| 可打印字符 / UTF-8 | 插入 |
| Backspace / Delete | 删除 |
| ← → ↑ ↓ | 移动光标（↑↓ 含 pref-col 列记忆） |
| Home / End | 行首/行尾 |
| Enter | **提交** |
| Escape | **插入换行** |
| 鼠标左键/拖拽 | 定位光标 |

### Pref-col 列记忆

上下移动时保持之前的 display-width 列：

```
长行: hello world      ← 光标在 'w' (col 6)
短行: hi               ← ↓ 后夹紧到行尾 (col 2)
长行: another line     ← ↓ 恢复到 col 6 (pref-col 不变)
```

## 回调

### on-submit : `(string → void)`

Enter 时调用，参数为完整 buffer 文本（含所有换行）。单行模式即单行内容。

### on-change : `(string → void)`

每次编辑（insert/backspace/delete）后调用，参数为完整 buffer 文本。可用于字数统计、自动保存、联动其他组件。

## 样式

| 状态 | 样式 |
|---|---|
| 无焦点 | `input-normal` |
| 聚焦 | `input-focus` |
| 光标 | `cursor` |

## 滚动

- **垂直**：保证光标行始终在视口内
- **水平**：惰性——仅光标贴边时滚动，其余保持不动
- CJK/emoji 宽字符正确裁剪，不显示半字符

## 实现

两层架构：

- **Layer 1** (`base/gap-buffer.rkt`): 纯 Gap Buffer，无终端依赖。负责字符存储、光标移动（含 pref-col 记忆）、行索引缓存
- **Layer 2** (`ui/widgets/input.rkt`): 渲染 + 滚动计算 + 事件绑定。只读 buffer，只写屏幕
