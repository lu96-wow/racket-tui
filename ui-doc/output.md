# make-output — 可滚动输出面板

带滚动条、折叠块的输出缓冲区。返回两个值：组件 + 操作 API。

## 创建

```racket
(define-values (comp api) (make-output
                            #:max-lines    500     ;; 最大行数，默认 #f
                            #:style        'info   ;; 默认样式
                            #:auto-scroll?  #t     ;; 自动滚到底
                            #:bar-width    1))     ;; 滚动条宽度
```

## API

```racket
(append api "text")                     ;; 追加文本
(append-styled api "text" 'error)       ;; 追加带样式的文本
(clear api)                             ;; 清空
(scroll-end api)                        ;; 滚到底

;; 折叠块
(begin-fold api)                        ;; 开始折叠块 → 返回 block-id
(end-fold api)                          ;; 结束折叠块
(toggle-fold api block-id)              ;; 折叠/展开
```

## 交互

| 操作 | 行为 |
|---|---|
| ↑ ↓ | 滚动 |
| PageUp / PageDown | 翻页 |
| Home / End | 顶部/底部 |
| 鼠标滚轮 | 滚动 |
| 鼠标拖拽滚动条 | 滚动 |
| 点击折叠块标题 | 折叠/展开 |

## 折叠块

```racket
(append-styled api "▼ Errors" 'error)
(append api "\n")
(define bid (begin-fold api))
(for ([i 3])
  (append api (format "  line ~a\n" i)))
(end-fold api)
;; 点击 "▼ Errors" 可折叠/展开
```

嵌套折叠：

```racket
(define bid1 (begin-fold api))
(append api "  level 1\n")
  (define bid2 (begin-fold api))
  (append api "    level 2\n")
  (end-fold api)
(end-fold api)
```
