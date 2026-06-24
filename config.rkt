#lang racket

;; ════════════════════════════════════════════════════════════════
;; TUI 可调参数 — 所有硬编码的超时、上限、间隔集中在此
;; ════════════════════════════════════════════════════════════════

;; ESC 序列字节间超时 (秒), 等价 ncurses ESCDELAY 环境变量
;; 用于区分独立 ESC 按键 vs ESC 开头的控制序列
(define ESCDELAY 0.05)    ; 50ms

;; CSI 序列最大字节数 (防御性上限, 超过则截断)
(define CSI-MAX-BYTES 32)

;; 粘贴内容最大字节数 (防御性上限, 超过则截断)
(define PASTE-MAX-BYTES 1048576)  ; 1MB

;; UTF-8 后续字节读取超时 (秒)
;; 终端通常在一次 write 中发送完整多字节字符
(define UTF8-READ-TIMEOUT 0.5)

;; 粘贴内容字节间读取超时 (秒)
;; 粘贴数据通常成块到达, 较长超时容忍网络延迟
(define PASTE-READ-TIMEOUT 1.0)

;; 窗口大小轮询间隔 (秒)
(define RESIZE-POLL-INTERVAL 0.1)  ; 100ms

;; ════════════════════════════════════════════════════════════════

(provide ESCDELAY CSI-MAX-BYTES PASTE-MAX-BYTES
         UTF8-READ-TIMEOUT PASTE-READ-TIMEOUT
         RESIZE-POLL-INTERVAL)