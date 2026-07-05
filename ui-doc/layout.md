# layout — 权重布局系统

纯函数布局，按权重比例分配空间。返回 `layout`，可直接传给 `run-app`。

## API

```racket
(layout-row (thing weight) ...)   ;; 垂直排列
(layout-col (thing weight) ...)   ;; 水平排列
(border inner #:title "..." ...)  ;; 套边框，内容内缩 1
(screen (thing weight) ...)       ;; 填满终端
space                              ;; 空白占位
```

## thing 类型

| thing | 说明 |
|---|---|
| component | `make-text` `make-input` `make-output` `make-button` `make-border` |
| `space` | 占权重，不产生组件 |
| `layout` | `layout-row`/`layout-col`/`border`/`screen` 的返回值 |

## 权重算法

```
size = max(1, floor(span × weight / sum))

weight > 0 至少得 1 行/列，末端剩余像素留空
```

## 嵌套

`layout-row`/`layout-col`/`border` 返回 `layout`，在父级中需套一层权重：

```racket
(layout-row
  (title 1)                             ;; component
  (space 1)                             ;; 占位
  ((layout-col (left 1) (right 2)) 3)   ;; ← 嵌套 layout，必须套 ((...) weight)
  ((border inner #:title "P") 2))       ;; ← border 也套
```

## 顶层入口

```racket
(run-app (screen (title 1) (body 6) (footer 1)))
```

`screen` 返回 `layout`，`run-app` 内部取终端尺寸解析。resize 时自动重算。

## 裸坐标兼容

```racket
(run-app (list (list comp x y w h) ...))
```

传 `spec-list` 时行为不变，不参与 resize。

## 示例

```racket
(run-app-noblock
  (screen
   (t-title 1)
   ((layout-col
     ((border (layout-row (out-left 1)) #:title "Files") 1)
     (space 1)
     ((border (layout-row (out-right 1)) #:title "Log") 1)) 6)
   ((layout-col (input-field 1) (space 3)) 1)
   (t-status 1)))
```
