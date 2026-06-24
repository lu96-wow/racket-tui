# 输入系统安全隐患清单

创建时间: 2024
状态说明: 🔴 致命 | 🟠 严重 | 🟡 中等 | 🟢 轻微 | ✅ 已修复

---

## ✅ 1. `read-byte` 在 VMIN=0 下 CPU 空转 (已修复)

**修复方案**: ncurses ESCDELAY 风格 — 用 `sync/timeout` + `read-bytes-evt` 替代裸 `read-byte`
**新增**: `read-byte/timeout` 函数, `ESCDELAY=0.05` (50ms), ESC 后超时→独立 ESC 键
**文件**: input.rkt (159-161 read-byte/timeout, 210-243 read-event-impl)

---

## ✅ 2. 解析函数无终止条件 (已修复)

**修复方案**: 
- `read-csi-seq` → 添加 `CSI-MAX-BYTES=32` 防御上限 + 超时返回部分序列
- `read-paste-content` → 添加 `PASTE-MAX-BYTES=1MB` 防御上限 + 超时返回已有内容
- 所有 `read-byte` → `read-byte/timeout`

---

## 🟡 3. `kill-thread` 暴力终止 resize 线程

**文件**: input.rkt (237)
**风险**: `channel-put` 中途被 kill → 通道状态可能不一致

```racket
(define (resize-monitor-stop t)
  (when t (kill-thread t)))       ;; ← 在任意指令点终止，无清理机会
```

**修复方向**:
- [ ] 使用 `(thread/suspend-to-kill t)` 延迟终止
- [ ] 使用共享停止标志 + `sync/timeout` 让线程自行退出
- [ ] 使用 `async-channel` + `channel-put-evt` 非阻塞写入

---

## ✅ 4. `read-byte` 不处理 EOF (已修复)

`read-byte/timeout` 内部使用 `sync/timeout` + `read-bytes-evt`：
stdin 关闭/eof 时 `read-bytes-evt` 返回 `#f`，`(bytes? #f)` → `#f`，
调用处 `(not b)` 正确处理。无需额外检查。

---

## 🟡 5. resize-channel 无缓冲 → resize 事件延迟

**文件**: base.rkt (50), input.rkt (242)
**问题**: `(make-channel)` 创建同步 channel（无缓冲）。
主线程在 `read-event-impl` 解析多字节序列时，
resize 线程 `channel-put` 会阻塞，事件延迟投递。

```racket
read-event → sync(stdin, resize-channel) → 返回首字节
                                            └→ read-event-impl → read-byte × N
                                            ↑ resize 线程 channel-put 在此阻塞
```

**修复方向**:
- [ ] resize-channel 改为 `(make-channel 1)`（缓冲 1 条 resize 消息）
- [ ] 或使用 `async-channel` → `channel-put-evt`

---

## ❌ 6. `make-stdin-evt` 每次调用创建新对象 (不是错误)

`read-bytes-evt` 设计即为一次性事件。sync 消费后失效，必须重建。
与 Unix poll/select 每次调用必须重新填 fd_set 同理。

---

## ✅ 7. `oflag-set!` / `set-vmin-vtime!` 定义在 `provide` 之后

**文件**: base.rkt (78 provide, 81-84 define)
**影响**: 仅可读性，Racket 允许模块内前向引用

```racket
(provide ...)           ;; line 78
(define (oflag-set! t v) ...)       ;; line 81 — 在 provide 之后!
(define (set-vmin-vtime! t vmin vtime) ...)  ;; line 83
```

**修复方向**:
- [ ] 移动到 `provide` 之前（line 41 之后、line 47 之前）

---

## ✅ 8. `TERMIOS-SIZE 60` 硬编码

**文件**: base.rkt (17)
**影响**: 仅在 x86_64 Linux 正确，ARM/32-bit 可能不同

```racket
(define TERMIOS-SIZE 60)   ;; x86_64: sizeof(struct termios) = 60
```

**修复方向**:
- [ ] 方案A: 使用 FFI 调用 C 的 `sizeof`
- [ ] 方案B: 分配大缓冲区 + 按需截取
- [ ] 方案C: 使用 Racket 的 `malloc` 让 C 侧分配

---

## 修复优先级

```
P0 (立即):   #1 read-byte 空转
P1 (高):     #2 解析无终止条件
P2 (中):     #3 kill-thread, #4 EOF未处理, #5 channel缓冲
P3 (低):     #6-#8 轻微问题
```
