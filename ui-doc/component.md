# Component — 组件协议

```racket
(struct component
  (render handler focusable? show? w h dirty render?)
  #:transparent)
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `render` | `(focused? x y w h → void)` | 绘制，框架传入视口坐标。只写不读 |
| `handler` | `(type data mods → void)` | 事件处理，由 `build-input` 构造 |
| `focusable?` | bool | 是否可获取键盘焦点 |
| `show?` | bool | 是否可见 |
| `w` `h` | natural | 期望尺寸（0=由 spec 决定） |
| `dirty` | box[bool] | 标记需重绘，框架绘后置 `#f` |
| `render?` | `#f` 或 `(x y w h focused? → void)` | pre-render hook——每帧调用，组件可在此判断是否需要重绘并置 dirty |

## 实现自定义组件

```racket
(require "ui/component.rkt"
         "base/io/build-input.rkt"
         "base/io/output.rkt"
         "base/io/output-styles.rkt")

(define (make-my-widget #:kw val ...)
  (define dirty (box #t))

  (define (render focused? x y w h)
    ;; 只在 dirty 时被调用（或首次）
    ;; 使用 put-* 绘制到终端的 [x,y,w,h] 区域
    (put-styled-at! y x 'info "my widget"))

  (define handler
    (build-input
      #:char (λ (ch) ...)   ;; 处理按键
      #:enter (λ () ...)
      ;; ... 更多事件
      ))

  (component render handler #t #t w h dirty #f))
```

## render 规范

- `focused?`: 当前组件是否拥有键盘焦点
- `x y`: 终端列/行坐标（0-based）
- `w h`: 视口宽高
- 绘制过程被渲染器 `parameterize` 捕获到 byte buffer，框架批量写 stdout——**不要在 render 里 flush**
- 组件如果需要在视口外留空，自己控制；渲染器不做额外清屏
- `cursor-move` 操作是随 ANSI 序列发出的绝对定位，和 cursor 状态追踪无关

## handler 规范

handler 由 `build-input` 构造，支持的事件类型：

| 关键字 | 回调签名 |
|---|---|
| `#:char` | `(integer → void)` — ASCII 字节值 |
| `#:utf-char` | `(string → void)` |
| `#:ctrl` | `(char → void)` — Ctrl+字母 |
| `#:alt` | `(char → void)` |
| `#:enter` / `#:backspace` / `#:delete` / `#:tab` / `#:space` / `#:escape` | `(→ void)` |
| `#:up` / `#:down` / `#:left` / `#:right` | `(→ void)` |
| `#:home` / `#:end` / `#:pageup` / `#:pagedown` / `#:insert` | `(→ void)` |
| `#:mouse-press` | `(button x y modifiers → void)` — button: `'left/'middle/'right` |
| `#:mouse-release` | `(button x y modifiers → void)` |
| `#:mouse-move` | `(x y modifiers → void)` |
| `#:mouse-scroll` | `(dir x y modifiers → void)` — dir: `'up/'down` |
| `#:paste` | `(bytes → void)` |
| `#:resize` | `(rows cols → void)` |
| `#:any` | `(type data mods → void)` — 兜底 |
| `#:null` | `(→ void)` — 无输入 |

所有关键字可选。未匹配的事件落入 `#:any` 兜底（如无则静默丢弃）。

## dirty 机制

- 组件创建时 dirty 初始应为 `(box #t)`——确保首次渲染
- 内容变化时 `(set-box! dirty #t)`
- 框架渲染后自动 `(set-box! dirty #f)`
- `render?` hook 可用于每帧自动检测变化（适合动态文本场景）
