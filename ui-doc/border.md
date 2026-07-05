# make-border — 边框组件

纯渲染组件，四边独立开关 + 独立样式，无交互。

## 创建

```racket
(make-border
  #:up?         #t           ;; 各边独立开关
  #:down?       #t
  #:left?       #t
  #:right?      #t
  #:up-style    'info        ;; 各边独立样式
  #:down-style  'info
  #:left-style  'info
  #:right-style 'info
  #:title       #f)          ;; 上边中间文字
```

## 绘制

```
┌── title ──┐
│           │
│  内部区域  │
│           │
└───────────┘
```

四角字符由相邻两边自动决定：

| 条件 | 左上 | 右上 | 左下 | 右下 |
|---|---|---|---|---|
| 两边都有 | `┌` | `┐` | `└` | `┘` |
| 只有横边 | `─` | `─` | `─` | `─` |
| 只有竖边 | `│` | `│` | `│` | `│` |

## 与 layout 配合

通常不直接使用，通过 `border` 包装：

```racket
(border (layout-row (content 1))
        #:title "Panel"
        #:up-style 'heading)
```

`border` 自动处理内缩 (1,1,-2,-2) 和绘制顺序（边框覆盖内容边缘）。
