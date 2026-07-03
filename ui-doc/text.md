# Text — 文本标签

静态或动态文本，无焦点，仅展示。

## 创建

```racket
(make-text
  #:text    "Hello"              ; string 或 (-> string)  静态/动态
  #:style   'info                ; 样式名，默认 'info
  #:h-align 'left)               ; 'left / 'center / 'right，默认 'left
```

## 动态文本

传入一个返回 string 的 thunk，每帧自动检查变化并重绘：

```racket
(make-text
  #:text (λ () (format "Count: ~a" (unbox counter)))
  #:style 'status-good)
```

## 样式

预定义：`title subtitle heading info error warning success` 等，见 `base/io/output-styles.rkt`。

## 对齐

| `h-align` | 行为 |
|---|---|
| `'left` | 左对齐（默认） |
| `'center` | 居中 |
| `'right` | 右对齐 |

文本超过视口宽度 `w` 时截断。

## 示例

```racket
(define title
  (make-text #:text "┌────┤ My App ├──────────┐" #:style 'title))

(define status
  (make-text #:text (λ () (format "Mode: ~a" mode)) #:style 'info))

(list title  1 1 30 1)
(list status 1 2 30 1)
```
