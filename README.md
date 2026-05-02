远程安装

```bash
raco pkg install https://github.com/lu96-wow/racket-tui.git
```

![Demo](a.gif)

输入设计
所有按键抽象为统一事件 (read-event)，返回 (type data modifiers)：
```racket

(let-values ([(type data mods) (read-event)])
  (cond [(event-touch? type)  (let-values ([(x y) (get-mouse-pos data)])
                                (printf "鼠标 ~a,~a" x y))]
        [(event-up? type)     (cursor-up 1)]
        [(event-ctrl? type)   (printf "Ctrl+~a" (ctrl->char data))]
        [(event-utf8? type)   (printf "UTF-8: ~a" (event->string data))]
        [(event-resize? type) (printf "~a×~a" (get-resize-rows data) (get-resize-cols data))]
        [(event-paste? type)  (printf "粘贴: ~a 字节" (bytes-length data))]))

```
支持事件：

事件类型	说明	   判断函数
key	   普通按键	           event-key?
ctrl	Ctrl+字符	          event-ctrl?
alt	  Alt+字符	          event-alt?
utf8	UTF-8多字节字符	     event-utf8?
up/down/left/right方向键	event-up? 等
home/end	Home/End 键	  event-home? 等
del/insert	Delete/Insert	event-del? 等
pageup/pagedown	PageUp/PageDown	event-pageup? 等
mouse	鼠标事件（统一触摸接口）	event-touch? / event-mouse?
paste	粘贴事件（括号粘贴模式）	event-paste?
resize	窗口大小变化	event-resize?
seq	未识别的转义序列	event-seq?
mod-seq	带修饰键的序列	event-mod-seq?
null	无事件	event-null?

```racket
(style-define! 'fancy clr-yellow bclr-blue attr-bold attr-underline)
(put-styled 'fancy "组合样式")
;; 真彩色快捷输出（不影响光标位置）
(put-rgb-fg-at 5 10 255 128 0 "橙色文字")
```
支持 ANSI 16 色 / 256 色 / 真彩色。put-at 自动保存恢复光标，对交互透明。
窗口 Resize
后台线程每 100ms 通过 ioctl(TIOCGWINSZ) 查询窗口大小，变化时注入 read-event 为 'resize 事件：
```racket

(with-tui
  (let loop ()
    (let-values ([(type data mods) (read-event)])
      (when (event-resize? type)
        (let-values ([(rows cols) (get-resize-size data)])
          (screen-clear)
          (redraw-ui rows cols)))
      (loop))))
```
无信号依赖，channel-try-get 零阻塞，窗口主动查询驱动。
光标追踪
所有光标操作自动追踪当前位置，put-at 输出后恢复原位，对交互式输入透明。
```racket
鼠标事件
(let-values ([(type data mods) (read-event)])
  (when (event-touch? type)
    (let-values ([(x y) (get-mouse-pos data)])
      (cond [(mouse-press? data)
             (printf "按下~a键 位置:(~a,~a)"
                     (cond [(mouse-left? data) "左"]
                           [(mouse-middle? data) "中"]
                           [(mouse-right? data) "右"])
                     x y)]
            [(mouse-release? data)
             (printf "释放 位置:(~a,~a)" x y)]
            [(mouse-move? data)
             (printf "移动 位置:(~a,~a)" x y)]
            [(mouse-scroll? data)
             (printf "滚轮~a 位置:(~a,~a)"
                     (if (scroll-up? data) "上" "下")
                     x y)]))))
```
鼠标事件数据结构：
    普通事件：(action button x y modifiers)
    滚轮事件：(action scroll direction x y modifiers)

粘贴事件
```racket
(let-values ([(type data mods) (read-event)])
  (when (event-paste? type)
    (printf "粘贴了 ~a 字节内容" (bytes-length data))
    (printf "内容: ~a" (event->string data))))
```
快速开始
```racket

#lang racket

(require tui)
(with-tui
  (screen-clear) (cursor-hide)
  (put-at 5 10 "Hello TUI!")
  (sleep 2))
```

racket-tui/tui	with-tui 生命周期
racket-tui/input	事件输入
racket-tui/output	光标/屏幕控制
racket-tui/output-color	颜色/样式
racket-tui/resize	窗口大小

ffi绑定只存在于base.rkt和resize.rkt,最小依赖