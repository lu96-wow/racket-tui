#lang racket

;; ════════════════════════════════════════════════════════════════
;; terminal-support/catalog.rkt —— 查询目录 + 默认表
;;
;; 把 query.rkt 的原语包成命名的查询（`*-query`），并提供默认参数与
;; 组合表（`*-queries` / `group->queries` / `profile->queries`）。
;; 只提供组合基石，不做任何决策。
;; ════════════════════════════════════════════════════════════════

(require racket/list
         "query.rkt"
         "groups.rkt")

(provide
 ;; 单项查询构造器（→ query）
 da1-query da2-query da3-query xtversion-query
 xtgettcap-query kitty-flags-query xtmodkeys-query kitty-graphics-query
 decrqm-private-query decrqm-ansi-query
 osc-color-query osc-palette-query
 text-area-size-query text-area-pixel-size-query cell-pixel-size-query
 dsr-query
 ;; 默认参数
 default-xtgettcap-names default-palette-indices
 ;; 表（组合）
 identity-queries xtgettcap-queries kitty-queries
 mode-queries color-queries size-queries
 group->queries profile->queries default-queries)

;; ── 身份 / 设备属性 ──
(define (da1-query)       (query 'da1       (da1-request)       parse-da1))
(define (da2-query)       (query 'da2       (da2-request)       parse-da2))
(define (da3-query)       (query 'da3       (da3-request)       parse-da3))
(define (xtversion-query) (query 'xtversion (xtversion-request) parse-xtversion))

;; ── terminfo / 键盘 ──
(define (xtgettcap-query names) (query 'xtgettcap      (xtgettcap-request names) parse-xtgettcap))
(define (kitty-flags-query)     (query 'kitty-flags    (kitty-flags-request)     kitty-flags-value))
(define (xtmodkeys-query)       (query 'xtmodkeys      (xtmodkeys-request)       parse-xtmodkeys))
(define (kitty-graphics-query)  (query 'kitty-graphics (kitty-graphics-request)  kitty-graphics-reply?))

;; ── 模式（每个模式一条）──
(define (decrqm-private-query mode)
  (query (cons 'decrqm-private mode) (decrqm-private-request mode)
         (λ (raw) (decrqm-private-pm raw mode))))
(define (decrqm-ansi-query mode)
  (query (cons 'decrqm-ansi mode) (decrqm-ansi-request mode)
         (λ (raw) (decrqm-ansi-pm raw mode))))

;; ── 颜色 / 尺寸 ──
(define (osc-color-query code)
  (query (cons 'osc code) (osc-color-request code) (λ (raw) (osc-value raw code))))
(define (osc-palette-query idx)
  (query (cons 'palette idx) (osc-palette-request idx) (λ (raw) (osc-palette-value raw idx))))
(define (text-area-size-query)       (query 'text-size  (text-area-size-request)       (λ (raw) (window-size raw 8))))
(define (text-area-pixel-size-query) (query 'pixel-size (text-area-pixel-size-request) (λ (raw) (window-size raw 4))))
(define (cell-pixel-size-query)      (query 'cell-size  (cell-pixel-size-request)      (λ (raw) (window-size raw 6))))
(define (dsr-query)                  (query 'cursor     (dsr-request)                  cursor-position))

;; ── 默认参数（纯数据，可被调用方覆盖）──
(define default-xtgettcap-names
  '("TN" "Co" "RGB" "Tc" "colors" "ccc" "kmous" "XM" "cup" "smcup" "rmcup"
    "setaf" "setab" "sitm" "ritm" "Ms" "Cs" "Ss" "Se"
    "BD" "BE" "PS" "PE" "smxx" "rmxx"))
(define default-palette-indices (range 16))

;; ════════════════════════════════════════════════════════════════
;; 表（组合基石）
;; ════════════════════════════════════════════════════════════════

(define (identity-queries) (list (da2-query) (da3-query) (xtversion-query)))

(define (xtgettcap-queries [names default-xtgettcap-names])
  (list (xtgettcap-query names)))

(define (kitty-queries [kitty-graphics? #f])
  (append (list (kitty-flags-query) (xtmodkeys-query))
          (if kitty-graphics? (list (kitty-graphics-query)) '())))

(define (mode-queries groups)
  (append (for/list ([m (in-list (group-private-modes groups))]) (decrqm-private-query m))
          (for/list ([m (in-list (group-ansi-modes groups))])    (decrqm-ansi-query m))))

(define (color-queries [palette-indices default-palette-indices])
  (append (list (osc-color-query 10) (osc-color-query 11) (osc-color-query 12))
          (for/list ([i (in-list palette-indices)]) (osc-palette-query i))))

(define (size-queries)
  (list (text-area-size-query) (text-area-pixel-size-query) (cell-pixel-size-query)))

;; 按分组组表；DA1 始终放最后（哨兵 + 基本属性）
(define (group->queries groups
                        #:xtgettcap-names [xtgettcap-names default-xtgettcap-names]
                        #:palette-indices [palette-indices default-palette-indices]
                        #:kitty-graphics? [kitty-graphics? #f])
  (define (want? g) (and (memq g groups) #t))
  (append (if (want? 'identity)  (identity-queries) '())
          (if (want? 'xtgettcap) (xtgettcap-queries xtgettcap-names) '())
          (if (want? 'kitty)     (kitty-queries kitty-graphics?) '())
          (mode-queries groups)
          (if (want? 'colors)    (color-queries palette-indices) '())
          (if (want? 'sizes)     (size-queries) '())
          (if (or (want? 'sizes) (want? 'cursor)) (list (dsr-query)) '())
          (list (da1-query))))

(define (profile->queries profile
                          #:xtgettcap-names [xtgettcap-names default-xtgettcap-names]
                          #:palette-indices [palette-indices default-palette-indices]
                          #:kitty-graphics? [kitty-graphics? #f])
  (group->queries (profile-groups profile)
                  #:xtgettcap-names xtgettcap-names
                  #:palette-indices palette-indices
                  #:kitty-graphics? kitty-graphics?))

;; 默认表 = default-profile（standard）
(define (default-queries
         #:xtgettcap-names [xtgettcap-names default-xtgettcap-names]
         #:palette-indices [palette-indices default-palette-indices]
         #:kitty-graphics? [kitty-graphics? #f])
  (profile->queries default-profile
                    #:xtgettcap-names xtgettcap-names
                    #:palette-indices palette-indices
                    #:kitty-graphics? kitty-graphics?))
