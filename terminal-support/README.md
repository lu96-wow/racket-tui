# terminal-support

终端能力**探测**（运行时查询）。**纯 Racket，无 FFI，不依赖 `base`。**

本模块只做两件事：**发查询** + **建能力表（纯数据）**。
**不做任何"启用/关闭功能"**——那属于调用方的策略。

## 模块（分层）

| 文件 | 层 | 职责 |
|------|----|------|
| `query.rkt` | 查询逻辑 | 请求构造 + 回复解析 + **复用取值函数**（纯函数） |
| `io.rkt` | 传输 | 一次写出、一次读回 |
| `modes.rkt` | 表 | 模式编号 ↔ 名称 |
| `features.rkt` | 表 | DA1 特性码 / DA2 型号码 ↔ 名称 |
| `groups.rkt` | 表 | 查询分组 + profile |
| `spec.rkt` | 查询实现+默认表 | `query` 结构 + 单项 spec 构造器 + 组合表 |
| `run.rkt` | 按表查询 | `run-specs` / `run-specs/raw` |
| `caps.rkt` | 组装 | `assemble-caps`（纯数据，不做决策）+ 能力表访问 |
| `main.rkt` | **门户** | 对外唯一入口（重新导出各层） |

## 组合基石（不做决策，只组合）

一个 `query` = `(id request parse)`；一张表 = 一串 query。

```racket
;; 1) 用分组组一张表
(define specs (group->specs '(identity mouse paste sync colors)))

;; 2) 按表查询 → 原始回复 + 结果表（id -> value）
(define-values (raw results) (run-specs/raw specs))

;; 3) 纯组装成能力表
(define caps (assemble-caps results raw))

;; 或加自定义查询
(define my (query 'my-id #"\e[>0q" parse-xtversion))
(run-specs (cons my specs))
```

`probe-terminal` 只是 `default-specs`（= `default-profile`）的便捷封装。
表：`identity-specs xtgettcap-specs kitty-specs mode-specs color-specs size-specs`，
以及 `group->specs / profile->specs / default-specs`。

**结果容器：`id -> value` 的 hash，且 `id` 必须唯一**——重复 id 会直接报错（不静默覆盖，
避免丢结果）。`probe-terminal` 的 `#:private-modes/#:ansi-modes` 会先对组内模式去重，
所以“额外指定已有的模式”不会误报。

## 用法

```racket
(require "terminal-support/main.rkt")

;; 前提：终端已进入 raw 模式（关闭 ECHO/ICANON）
(define caps (probe-terminal))              ; 默认 profile='standard（只查 TUI 需要的）

(terminal-caps-id caps)
(caps-mode-available? caps 1006)            ; SGR 鼠标是否可用
(caps-mode-state caps 2026)                 ; 'set/'reset/'permanently-set/'permanently-reset/'unrecognized/#f
(caps-da1-features caps)                    ; => ("132 columns" "Sixel graphics" ...)
(caps-da2-model caps)                       ; => "VT100" / "tmux" ...
(caps-truecolor? caps)                      ; 由 XTGETTCAP RGB/Tc 判定
(terminal-caps-text-size caps)              ; => (rows . cols) 或 #f
```

## 查哪些：可配置（profile / 分组）

不是所有终端都支持所有模式，**全查是浪费**（xterm.js 全查要 ~100ms+）。
默认用 `'standard`，只查 TUI 真正需要的；需要全量再 `'full`。

| profile | 私有模式 | ANSI | 说明 |
|---------|:---:|:---:|------|
| `'minimal` | 4 | 0 | 身份 + 尺寸 + 光标 |
| `'standard`（默认） | 24 | 2 | 核心鼠标/键盘/备用屏/粘贴/focus/同步/颜色/尺寸 |
| `'full` | 82 | 6 | 全部（含 extra/杂项） |

```racket
(probe-terminal #:profile 'full)
(probe-terminal #:groups '(identity mouse paste colors))   ; 精确选组
(probe-terminal #:private-modes '(1006 2026))              ; 额外指定模式
```

分组全集见 `groups.rkt`：`identity xtgettcap kitty colors sizes`（非 DECRQM）
与 `mouse mouse-extra keyboard keyboard-extra focus cursor screen paste paste-extra
sync unicode resize selection readline printing misc`（DECRQM）。
可用 `(profile-groups 'full)` / `(group-private-modes gs)` 查询。

## 查询范围（'full 时）

| 类别 | 内容 |
|------|------|
| 设备属性 | DA1 `CSI c`（哨兵）、DA2 `CSI > c`、DA3 `CSI = c` |
| 身份 | XTVERSION `CSI > 0 q`、XTGETTCAP `DCS + q`（TN/Co/RGB/Tc/… 24 项） |
| 模式 | DECRQM 逐项：82 个 DEC 私有 + 6 个 ANSI |
| 键盘 | kitty `CSI ? u`、modifyOtherKeys `CSI ? 4 m`；kitty 图形 APC（默认不发） |
| 颜色 | OSC 10/11/12、OSC 4 调色板 0–15 |
| 尺寸 | DSR `CSI 6 n`（= ncurses u6/u7）、XTWINOPS `CSI 18/14/16 t` |

## Pm 判定

| Pm | `caps-mode-state` | `on?` | `settable?` | `available?` |
|----|-------------------|:---:|:---:|:---:|
| 1 set | `'set` | ✅ | ✅ | ✅ |
| 2 reset | `'reset` | — | ✅ | ✅ |
| 3 permanently set | `'permanently-set` | ✅ | — | ✅ |
| 4 permanently reset | `'permanently-reset` | — | — | — |
| 0 not recognized | `'unrecognized` | — | — | — |
| 无回复 | `#f` | — | — | — |

`caps-mode-supported?` = `available?`：**能处于"开"**（含 permanently-set）。
`permanently-set` 是"一直开着"，算可用；只有 `permanently-reset`/不识别才不可用。

## 真彩判定

`caps-truecolor?` 只看 **XTGETTCAP `RGB`/`Tc`**。**不要用 OSC 的 `rgb:` 判真彩**——
那只是 OSC 的回复格式，256 色终端也这么回（用 `caps-osc-rgb?` 表示"终端应答了颜色查询"）。
无 XTGETTCAP 的终端（如 VTE/xterm.js）请由调用方回退到 `COLORTERM`。

## 设计来源

| 技巧 | 来源 |
|------|------|
| `IDQUERIES = DA3 + XTVERSION + XTGETTCAP + DA2`；**DA2 放最后** | notcurses `termdesc.c` |
| **DA1 哨兵**（可选早停；默认关闭，因 xterm.js 回复非严格有序） | crossterm、termwiz |
| 逐功能 DECRQM 判 Pm | Vim `term.c`、notcurses |
| kitty `CSI ? u`；modifyOtherKeys `CSI ? 4 m` | kitty 规范、Vim |
| 颜色/尺寸用 OSC、XTWINOPS 实测 | notcurses、Vim、termwiz |
| `u6/u7`（DSR + CPR） | ncurses `man 5 user_caps` |

## 注意

- 只做**只读查询**，不改终端持久状态（raw 模式由调用方负责）。
- tmux/screen 会拦截并自答 DA2/DECRQM；那反映 mux 的能力（正确行为）。`terminal-caps-tmux?` 可识别。
- `#:kitty-graphics? #t` 会发 APC 查询；不消费 APC 的终端（如 Linux console）可能把字节泄漏到屏幕，故默认关闭。
- 终止用"读到静默"（`#:idle`），不是 DA1 早停：xterm.js 等回复非严格有序，早停会漏读并泄漏给 shell。
