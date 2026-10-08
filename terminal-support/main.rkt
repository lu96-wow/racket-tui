#lang racket

;; ════════════════════════════════════════════════════════════════
;; terminal-support/main.rkt —— 门户（对外唯一入口）
;;
;; 分层（各层也可单独 require）：
;;   query.rkt   查询逻辑：请求构造 + 回复解析 + 复用取值函数（纯函数）
;;   io.rkt      传输：一次写出、一次读回
;;   modes.rkt   表：模式编号↔名称（纯数据）
;;   features.rkt表：DA1/DA2 码↔名称（纯数据）
;;   groups.rkt  表：查询分组 + profile（纯数据）
;;   spec.rkt    查询实现 + 默认表（query 结构 + 组合基石）
;;   run.rkt     按表查询（run-specs）
;;   caps.rkt    组装（assemble-caps，纯数据，不做决策）+ 能力表访问
;;
;; 本模块不做决策、不启用任何功能，只提供组合基石。
;; ════════════════════════════════════════════════════════════════

(require "query.rkt"
         "io.rkt"
         "modes.rkt"
         "features.rkt"
         "groups.rkt"
         "spec.rkt"
         "run.rkt"
         "caps.rkt")

;; ── 查询逻辑（构造/解析/取值）──
(provide (all-from-out "query.rkt")
         ;; ── 传输 ──
         (all-from-out "io.rkt")
         ;; ── 表：模式 / 设备属性 / 分组 ──
         (all-from-out "modes.rkt")
         (all-from-out "features.rkt")
         (all-from-out "groups.rkt")
         ;; ── 查询实现 + 默认表 ──
         (all-from-out "spec.rkt")
         ;; ── 按表查询 ──
         (all-from-out "run.rkt")
         ;; ── 组装 + 能力表访问 ──
         (all-from-out "caps.rkt"))
