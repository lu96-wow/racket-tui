# Button — 按钮

## 创建

```racket
(make-button
  #:text        "Click Me"      ; 按钮文字（前后自动加空格）
  #:on-activate (λ () ...)      ; 激活回调，默认 void
  #:style       'button)        ; 样式，默认 'button
```

## 交互

| 操作 | 行为 |
|---|---|
| 鼠标按下 | 切换为 `button-pressed` 样式 |
| 鼠标释放（在按钮上） | 调用 `on-activate` |
| Enter / Space（聚焦时） | 调用 `on-activate` |

## 样式

| 状态 | 样式 |
|---|---|
| 默认 | `#:style`（默认 `button`） |
| 按下 | `button-pressed` |
