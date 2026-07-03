# Button — 按钮

鼠标点击或键盘触发。

## 创建

```racket
(make-button
  #:text        "Click Me"          ; 按钮文字（前后自动加空格）
  #:on-activate (λ () ...))         ; 激活回调，默认 void
```

## 交互

| 操作 | 行为 |
|---|---|
| 鼠标按下 | 切换为 `button-pressed` 样式 |
| 鼠标释放（在按钮上） | 调用 `on-activate` |
| Enter / Space（聚焦时） | 调用 `on-activate` |

## 样式

| 状态 | 样式名 |
|---|---|
| 默认 | `button` |
| 按下 | `button-pressed` |

可通过 `style-define!` 覆盖。

## 示例

```racket
(define btn
  (make-button #:text "Submit"
               #:on-activate (λ () (displayln "clicked!"))))

;; 放入 specs:
(list btn 10 5 0 0)  ; x=10, y=5, w/h=0 使用自动尺寸
```
