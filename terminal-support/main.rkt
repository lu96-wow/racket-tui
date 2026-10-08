#lang racket

;; ════════════════════════════════════════════════════════════════
;; terminal-support/main.rkt —— 门户（对外唯一入口）
;;
;; 分层（各层也可单独 require）：
;;   query.rkt       查询原语：单元类型 query + 请求构造 + 解析 + 取值（纯函数）
;;   io.rkt          传输：一次写出、一次读回
;;   modes.rkt       表：模式编号↔名称（纯数据）
;;   device-attrs.rkt表：DA1/DA2 码↔名称（纯数据）
;;   groups.rkt      表：查询分组 + profile（纯数据）
;;   catalog.rkt     查询目录 + 默认表（*-query / *-queries / group->queries）
;;   run.rkt         按表查询（run-queries）
;;   caps.rkt        能力表：assemble-caps（纯数据，不做决策）+ 访问
;;
;; 本模块不做决策、不启用任何功能，只提供组合基石。
;; ════════════════════════════════════════════════════════════════

(require "query.rkt"
         "io.rkt"
         "modes.rkt"
         "device-attrs.rkt"
         "groups.rkt"
         "catalog.rkt"
         "run.rkt"
         "caps.rkt")

(provide
 ;; 查询原语（单元类型 / 请求 / 解析 / 取值）
 (all-from-out "query.rkt")
 ;; 传输
 (all-from-out "io.rkt")
 ;; 表：模式 / 设备属性 / 分组
 (all-from-out "modes.rkt")
 (all-from-out "device-attrs.rkt")
 (all-from-out "groups.rkt")
 ;; 查询目录 + 默认表
 (all-from-out "catalog.rkt")
 ;; 按表查询
 (all-from-out "run.rkt")
 ;; 能力表：组装 + 访问
 (all-from-out "caps.rkt"))
