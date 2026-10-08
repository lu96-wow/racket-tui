# terminal-support

终端能力**探测**（运行时查询）。**纯 Racket，无 FFI，不依赖 `base`。**

本模块只做两件事：**发查询** + **建能力表（纯数据）**。
**不做任何"启用/关闭功能"**——那属于调用方的策略。

## 模块

| 文件 | 职责 |
|------|------|
| `query.rkt` | 查询序列构造 + 回复解析（纯函数，无 I/O） |
| `io.rkt` | 收发：一次写出所有查询，一次读回（DA1 哨兵） |
| `modes.rkt` | 模式编号 ↔ 名称的纯数据表 |
| `caps.rkt` | `terminal-caps` 结构 + `probe-terminal` |
| `main.rkt` | 汇总对外接口 |

## 用法

```racket
(require "terminal-support/main.rkt")

;; 前提：终端已进入 raw 模式（关闭 ECHO/ICANON）
(define caps (probe-terminal))                 ; → terminal-caps（纯数据）

(terminal-caps-id caps)                        ;=> "VTE(8001)" / "xterm.js(...)"
(terminal-caps-kitty-flags caps)               ;=> 0 / #f / ...
(caps-mode-supported? caps 1006)               ;=> SGR 鼠标是否可用
(caps-mode-state caps 2026)                    ;=> 'supported | 'unavailable | 'unrecognized | #f
(caps-mode-name 2026)                          ;=> "同步输出"
(caps-truecolor? caps)                         ;=> 由 OSC 10/11/4 实测
(terminal-caps-text-size caps)                 ;=> (rows . cols) 或 #f
```

可调参数：`#:private-modes #:ansi-modes #:xtgettcap-names #:palette-indices
#:kitty-graphics? #:timeout #:idle`。

## 查询范围

| 类别 | 内容 |
|------|------|
| 设备属性 | DA1 `CSI c`（哨兵）、DA2 `CSI > c`、DA3 `CSI = c`（VTE 识别） |
| 身份 | XTVERSION `CSI > 0 q`、XTGETTCAP `DCS + q`（TN/RGB/Co 等） |
| 模式 | DECRQM 逐项：**78 个 DEC 私有模式 + 6 个 ANSI 模式**（见 `modes.rkt`） |
| 键盘 | kitty 键盘 `CSI ? u`（flags）；kitty 图形 APC（**默认不发**，见下） |
| 颜色 | OSC 10/11/12（前景/背景/光标）、OSC 4（调色板 0–15） |
| 尺寸 | DSR `CSI 6 n`（= ncurses u6/u7）、XTWINOPS `CSI 18/14/16 t` |

## Pm 判定

`caps-mode-state` 保留原始语义（不合并），另有若干语义谓词：

| Pm | `caps-mode-state` | `caps-mode-on?` | `caps-mode-settable?` | `caps-mode-available?` |
|----|-------------------|-----------------|-----------------------|------------------------|
| 1 set | `'set` | ✅ | ✅ | ✅ |
| 2 reset | `'reset` | — | ✅ | ✅ |
| 3 permanently set | `'permanently-set` | ✅ | — | ✅ |
| 4 permanently reset | `'permanently-reset` | — | — | — |
| 0 not recognized | `'unrecognized` | — | — | — |
| 无回复 | `#f` | — | — | — |

- `caps-mode-available?`（= `caps-mode-supported?`）：**能处于“开”**（Pm ∈ {1,2,3}）。
  `permanently-set` 是“一直开着”，算可用；只有 `permanently-reset`/不识别 才不可用。
- `caps-mode-settable?`：能自由置位/复位（Pm ∈ {1,2}）。

## 设计来源

| 技巧 | 来源 |
|------|------|
| `IDQUERIES = DA3 + XTVERSION + XTGETTCAP + DA2`；**DA2 放最后**（不能唯一识别） | notcurses `src/lib/termdesc.c` |
| **DA1 哨兵**：收到 `CSI c` 回复即前面都处理完 ⇒ "有 DA1 无目标回复 = 确定不支持" | crossterm `unix.rs`、termwiz `caps/probed.rs` |
| 逐功能 `DECRQM (CSI ? Ps $ p)` 判 `Pm` | Vim `src/term.c`、notcurses |
| kitty 键盘 `CSI ? u` | kitty 规范、crossterm、notcurses |
| 颜色/尺寸用 OSC、XTWINOPS 实测 | notcurses、Vim、termwiz |
| `u6/u7`（DSR + CPR） | ncurses `man 5 user_caps` |

## 扩展

- **加模式**：在 `modes.rkt` 的表里加一行即可（默认列表自动包含）。
- **加查询**：在 `query.rkt` 加构造器 + 解析器，在 `caps.rkt` 的 `probe-terminal` 里挂上。

## 注意

- 只做**只读查询**，不改终端持久状态（raw 模式由调用方负责）。
- tmux/screen 会拦截并自答 DA2/DECRQM；那反映 mux 的能力（正确行为）。`terminal-caps-tmux?` 可识别。
- XTGETTCAP 并非所有终端实现（VTE、xterm.js 就不应答），故颜色/尺寸另用 OSC/XTWINOPS。
- `#:kitty-graphics? #t` 会发 APC 查询；不消费 APC 的终端（如 Linux console）可能把字节泄漏到屏幕，故默认关闭。
