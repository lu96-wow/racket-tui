#lang racket

;; ════════════════════════════════════════════════════════════════
;; terminal-support/spec.rkt —— 查询实现 + 默认表
;;
;; 一个 `query` 描述"发什么 + 怎么解析"；一张"表"就是一串 query。
;; 本模块只提供组合基石，不做任何决策（不决定启用什么、不决定问不问）。
;;
;;   query  : (id request parse)
;;   id     : 结果键（symbol 或 (cons 类别 参数)）
;;   request: bytes
;;   parse  : (-> bytes any/c)  从整段原始回复里取该项
;; ════════════════════════════════════════════════════════════════

(require racket/list
         "query.rkt"
         "groups.rkt")

(provide (struct-out query)
         ;; 单项 spec 构造器
         da1-spec da2-spec da3-spec xtversion-spec
         xtgettcap-spec kitty-flags-spec xtmodkeys-spec kitty-graphics-spec
         decrqm-private-spec decrqm-ansi-spec
         osc-color-spec osc-palette-spec
         text-area-size-spec text-area-pixel-size-spec cell-pixel-size-spec
         dsr-spec
         ;; 默认参数
         default-xtgettcap-names default-palette-indices
         ;; 表（组合）
         identity-specs xtgettcap-specs kitty-specs
         mode-specs color-specs size-specs
         group->specs profile->specs default-specs)

(struct query (id request parse) #:transparent)

(define (mk id request parse) (query id request parse))

;; ── 身份 / 设备属性 ──
(define (da1-spec)        (mk 'da1        (da1-query)        parse-da1))
(define (da2-spec)        (mk 'da2        (da2-query)        parse-da2))
(define (da3-spec)        (mk 'da3        (da3-query)        parse-da3))
(define (xtversion-spec)  (mk 'xtversion  (xtversion-query)  parse-xtversion))

;; ── terminfo / 键盘 ──
(define (xtgettcap-spec names) (mk 'xtgettcap (xtgettcap-query names) parse-xtgettcap))
(define (kitty-flags-spec)     (mk 'kitty-flags   (kitty-flags-query)   kitty-flags-value))
(define (xtmodkeys-spec)       (mk 'xtmodkeys     (xtmodkeys-query)     parse-xtmodkeys))
(define (kitty-graphics-spec)  (mk 'kitty-graphics kitty-graphics-query kitty-graphics-ok?))

;; ── 模式（每个模式一条）──
(define (decrqm-private-spec mode)
  (mk (cons 'decrqm-private mode) (decrqm-private-query mode)
      (λ (raw) (decrqm-private-pm raw mode))))
(define (decrqm-ansi-spec mode)
  (mk (cons 'decrqm-ansi mode) (decrqm-ansi-query mode)
      (λ (raw) (decrqm-ansi-pm raw mode))))

;; ── 颜色 / 尺寸 ──
(define (osc-color-spec code)
  (mk (cons 'osc code) (osc-color-query code) (λ (raw) (osc-value raw code))))
(define (osc-palette-spec idx)
  (mk (cons 'palette idx) (osc-palette-query idx) (λ (raw) (osc-palette-value raw idx))))
(define (text-area-size-spec)       (mk 'text-size  (text-area-size-query)       (λ (raw) (window-size raw 8))))
(define (text-area-pixel-size-spec) (mk 'pixel-size (text-area-pixel-size-query) (λ (raw) (window-size raw 4))))
(define (cell-pixel-size-spec)      (mk 'cell-size  (cell-pixel-size-query)      (λ (raw) (window-size raw 6))))
(define (dsr-spec)                  (mk 'cursor     (dsr-query)                  cursor-position))

;; ── 默认参数（纯数据，可被调用方覆盖）──
(define default-xtgettcap-names
  '("TN" "Co" "RGB" "Tc" "colors" "ccc" "kmous" "XM" "cup" "smcup" "rmcup"
    "setaf" "setab" "sitm" "ritm" "Ms" "Cs" "Ss" "Se"
    "BD" "BE" "PS" "PE" "smxx" "rmxx"))
(define default-palette-indices (range 16))

;; ════════════════════════════════════════════════════════════════
;; 表（组合基石）
;; ════════════════════════════════════════════════════════════════

(define (identity-specs) (list (da2-spec) (da3-spec) (xtversion-spec)))

(define (xtgettcap-specs [names default-xtgettcap-names])
  (list (xtgettcap-spec names)))

(define (kitty-specs [kitty-graphics? #f])
  (append (list (kitty-flags-spec) (xtmodkeys-spec))
          (if kitty-graphics? (list (kitty-graphics-spec)) '())))

(define (mode-specs groups)
  (append (for/list ([m (in-list (group-private-modes groups))]) (decrqm-private-spec m))
          (for/list ([m (in-list (group-ansi-modes groups))])    (decrqm-ansi-spec m))))

(define (color-specs [palette-indices default-palette-indices])
  (append (list (osc-color-spec 10) (osc-color-spec 11) (osc-color-spec 12))
          (for/list ([i (in-list palette-indices)]) (osc-palette-spec i))))

(define (size-specs)
  (list (text-area-size-spec) (text-area-pixel-size-spec) (cell-pixel-size-spec)))

;; 按分组组表；DA1 始终放最后（哨兵 + 基本属性）
(define (group->specs groups
                      #:xtgettcap-names [xtgettcap-names default-xtgettcap-names]
                      #:palette-indices [palette-indices default-palette-indices]
                      #:kitty-graphics? [kitty-graphics? #f])
  (define (want? g) (and (memq g groups) #t))
  (append (if (want? 'identity)  (identity-specs) '())
          (if (want? 'xtgettcap) (xtgettcap-specs xtgettcap-names) '())
          (if (want? 'kitty)     (kitty-specs kitty-graphics?) '())
          (mode-specs groups)
          (if (want? 'colors)    (color-specs palette-indices) '())
          (if (want? 'sizes)     (size-specs) '())
          (if (or (want? 'sizes) (want? 'cursor)) (list (dsr-spec)) '())
          (list (da1-spec))))

(define (profile->specs profile
                        #:xtgettcap-names [xtgettcap-names default-xtgettcap-names]
                        #:palette-indices [palette-indices default-palette-indices]
                        #:kitty-graphics? [kitty-graphics? #f])
  (group->specs (profile-groups profile)
                #:xtgettcap-names xtgettcap-names
                #:palette-indices palette-indices
                #:kitty-graphics? kitty-graphics?))

;; 默认表 = default-profile（standard）
(define (default-specs
         #:xtgettcap-names [xtgettcap-names default-xtgettcap-names]
         #:palette-indices [palette-indices default-palette-indices]
         #:kitty-graphics? [kitty-graphics? #f])
  (profile->specs default-profile
                  #:xtgettcap-names xtgettcap-names
                  #:palette-indices palette-indices
                  #:kitty-graphics? kitty-graphics?))
