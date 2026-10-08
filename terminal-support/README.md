# terminal-support

终端能力**探测**（运行时查询）。**纯 Racket，无 FFI，不依赖 `base`。**

本模块只做两件事：**发查询** + **建能力表（纯数据）**。
**不做任何"启用/关闭功能"**——那属于调用方的策略。

作为 `tui` 的子库，门户模块路径为 `tui/terminal-support/main`。

## 模块（分层）

| 文件 | 层 | 职责 |
|------|----|------|
| `query.rkt` | 查询原语 | 单元类型 `query` + 请求构造 `*-request` + 解析 `parse-*` + 取值函数 + 颜色值解析（纯函数） |
| `io.rkt` | 传输 | `exchange-queries` / `read-reply`：一次写出、一次读回 |
| `modes.rkt` | 表 | 模式编号 ↔ 名称；`all-private-modes` / `all-ansi-modes` |
| `device-attrs.rkt` | 表 | DA1/DA2 码 ↔ 名称 |
| `env.rkt` | 环境事实 | `env-snapshot` / `detect-mux` / `env-ssh?` |
| `groups.rkt` | 表 | 查询分组 + profile |
| `catalog.rkt` | 查询目录+默认表 | `*-query` 构造器 + `*-queries` 表 + `group->queries` |
| `run.rkt` | 按表查询 | `run-queries` / `run-queries/raw` |
| `caps.rkt` | 能力表 | `assemble-caps`（纯数据）+ 访问 |
| `main.rkt` | **门户** | 对外唯一入口（重新导出各层） |

## 数据模型

```racket
(struct query (id request parse))   ; 一条查询
;;   id      : symbol 或 (cons 类别 参数) —— 结果键，在结果 hash 中唯一
;;   request : bytes                      —— 发送字节
;;   parse   : (-> bytes any/c)           —— 从整段原始回复取本项的值
```

- **表** = `(listof query)`。
- **结果表** = `(hash/c id any/c)`：`run-queries` 的产物，`id → 值`（`#f` = 无数据）。

```racket
(struct caps (id id-source name version mux ssh?
              da1 da2 da3 xtversion
              xtgettcap xtgettcap?
              kitty-flags kitty-graphics? xtmodkeys
              cursor text-size pixel-size cell-size
              private-modes ansi-modes
              osc palette
              colorterm term
              raw)
  #:transparent)
```

## 组合基石（不做决策，只组合）

```racket
;; 1) 用分组组一张表
(define qs (group->queries '(identity mouse paste sync colors)))

;; 2) 按表查询 → 原始回复 + 结果表（id -> value）
(define-values (raw results) (run-queries/raw qs))

;; 3) 纯组装成能力表（env 显式传入）
(define c (assemble-caps results raw #:env (env-snapshot)))

;; 或加自定义查询
(define my (query 'my-id #"\e[>0q" parse-xtversion))
(run-queries (cons my qs))
```

- 表：`identity-queries xtgettcap-queries kitty-queries mode-queries color-queries size-queries`，
  以及 `group->queries / profile->queries / default-queries`（纯数据，按需取用）。
- 传输端口是**显式参数**：`run-queries/raw #:in #:out`（默认 `current-*-port`）。
- **结果 hash 的 `id` 必须唯一**：重复 `id` 直接报错（不静默覆盖）。
- 组装是纯函数：`assemble-caps results raw #:env env`（env 由 `env-snapshot` 或调用方给）。
- **库不提供“一步到位”的封装**：外部按上面三步自己组合。

## 查哪些：可配置（profile / 分组）

| profile | 私有模式 | ANSI | 说明 |
|---------|:---:|:---:|------|
| `'minimal` | 4 | 0 | 身份 + 尺寸 + 光标 |
| `'standard`（默认） | 24 | 2 | 核心鼠标/键盘/备用屏/粘贴/focus/同步/颜色/尺寸 |
| `'full` | 82 | 6 | 全部 |

```racket
(profile->queries 'full)
(group->queries '(identity mouse paste colors))
(decrqm-private-query 1006)   ; 额外单条查询
```

分组（`groups.rkt`）：
- DECRQM：`mouse mouse-extra keyboard keyboard-extra focus cursor screen paste paste-extra
  sync unicode resize selection readline printing misc`
- 非 DECRQM：`identity xtgettcap kitty colors sizes`

## 查询范围（'full 时）

| 类别 | 内容 |
|------|------|
| 设备属性 | DA1 `CSI c`、DA2 `CSI > c`、DA3 `CSI = c` |
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

## 色深 / 颜色

模块把"乱"的多个来源揉成确定结论，外部只读字段，**不需要二次解析**：

```racket
(caps-color-level c)         ; 'truecolor | '256 | '16 | 'unknown
(caps-color c 10)            ; "rgb:cccc/cccc/cccc"（原始串）
(caps-color-rgb c 10)        ; (204 204 204)  —— 已拆成 0-255 分量
(caps-palette-color-rgb c 5) ; (170 0 187)
(caps-truecolor c)           ; #t / #f / 'unknown（仅 XTGETTCAP RGB/Tc）
(caps-osc-rgb? c)            ; OSC 是否以 rgb: 回复（≠ 真彩）
```

`caps-color-level` 优先级：**XTGETTCAP `RGB`/`Tc` > `COLORTERM` > XTGETTCAP `Co`
> `COLORTERM`(其他值) > `TERM`(含 256color/direct/truecolor) > DA1 `ANSI color`**。
`COLORTERM`/`TERM` 由 `#:env` 快照传入 `assemble-caps`，存入 `caps-colorterm`/`caps-term`。

**注意**：`caps-truecolor` 只看 XTGETTCAP；不要用 OSC 的 `rgb:` 判真彩（那只是 OSC 回复格式）。

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
- **SSH 对查询透明**：`XTVERSION`/`DECRQM`/`OSC` 仍到达本地终端并回传，无需特殊处理。
  但 `COLORTERM` 默认不随 SSH 转发（`TERM` 会）——所以 `caps-color-level` 把查询排在 env 之前。
  `caps-ssh?` 仅作元数据（表示 env 提示可能过时）。
- tmux/screen/zellij 会拦截并自答 DA2/DECRQM；那反映 mux 的能力（正确行为）。
  `caps-mux` 给出具体是哪个（`'tmux/'screen/'zellij/#f`），`caps-mux?` 为布尔。
- 环境事实（`TERM`/`COLORTERM`/多路复用器/SSH）作为**显式输入 `#:env`**（`env-snapshot` 可抓当前环境）
  传给 `assemble-caps`，保持纯函数、可测。
- `#:kitty-graphics? #t` 会发 APC 查询；不消费 APC 的终端可能把字节泄漏到屏幕，故默认关闭。
- 终止用"读到静默"（`#:idle`），不是 DA1 早停：回复非严格有序，早停会漏读并泄漏给 shell。
