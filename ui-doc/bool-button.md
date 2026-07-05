# Bool-Button — 布尔开关

Toggle 开关组件，点击或按 Enter/Space 切换状态。

## 创建

```racket
(make-bool-button
  #:label      "Option"      ; 显示文字
  #:initial?   #f            ; 初始状态，默认 #f
  #:on-change  (λ (v) ...)   ; 状态变化回调，参数为新的布尔值
  #:on-style   'success      ; 开 样式，默认 'success
  #:off-style  'info)        ; 关 样式，默认 'info
```

## 交互

| 操作 | 行为 |
|---|---|
| 鼠标左键 | 切换状态 |
| Enter / Space（聚焦时） | 切换状态 |

## 渲染

```
[x] Option A   ← 开 (on-style)
[ ] Option B   ← 关 (off-style)
```

## 回调

- **on-change** `(boolean → void)` — 每次切换后调用，参数为新的布尔值

## 样式

| 状态 | 参数 | 默认 |
|---|---|---|
| 开 | `#:on-style` | `success` |
| 关 | `#:off-style` | `info` |

## 示例

```racket
(define b1 (make-bool-button #:label "Auto-save"
                             #:initial? #t
                             #:on-change (λ (v)
                                           (printf "auto-save: ~a\n" v))))

(define b2 (make-bool-button #:label "Debug"
                             #:on-style 'error
                             #:off-style 'warning
                             #:on-change (λ (v)
                                           (printf "debug: ~a\n" v))))

(run-app
 (screen
  (t-title 1)
  (b1 1)
  (b2 1)
  (t-footer 1)))
```
