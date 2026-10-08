#lang racket

;; ════════════════════════════════════════════════════════════════
;; terminal-support/caps.rkt
;;
;; 只做两件事：**发查询** + **建能力表（纯数据）**。
;; 不含任何"启用/关闭功能"的逻辑——启用策略留给外部调用方。
;;
;; 设计取自 notcurses termdesc.c：身份用 XTVERSION > XTGETTCAP(TN) > DA2（DA2 最后），
;; 能用 DECRQM 逐项问的就不靠身份/固化表；哨兵取自 crossterm/termwiz（DA1 最后）。
;;
;; 前提：调用方已进入 raw 模式（关闭 ECHO/ICANON）；本模块不做 FFI。
;; ════════════════════════════════════════════════════════════════

(require racket/string
         racket/list
         "query.rkt"
         "io.rkt"
         "modes.rkt")

(provide (struct-out terminal-caps)
         probe-terminal
         default-private-modes default-ansi-modes
         default-xtgettcap-names default-palette-indices
         caps-mode-pm caps-mode-state caps-mode-supported?
         caps-mode-recognized? caps-mode-on? caps-mode-settable? caps-mode-available?
         caps-mode-name
         caps-color caps-palette-color caps-truecolor?)

;; XTGETTCAP 默认查的能力名（很多终端不实现 DCS +q，无回复即空表）
(define default-xtgettcap-names
  '("TN" "Co" "RGB" "colors" "ccc" "kmous" "XM" "cup" "smcup" "rmcup"
    "setaf" "setab" "sitm" "ritm" "Ms" "Cs" "Ss" "Se"
    "BD" "BE" "PS" "PE" "smxx" "rmxx" "Tc"))

;; OSC 4 默认查的调色板下标
(define default-palette-indices (range 16))

(struct terminal-caps
  (id            ; string  —— 最佳身份串
   id-source     ; 'xtversion | 'xtgettcap | 'da2 | 'unknown
   name version  ; string / #f —— 仅当身份来自 XTVERSION
   tmux?         ; boolean
   da1 da2 da3 xtversion    ; 原始解析结果
   xtgettcap     ; hash: 能力名 -> 值(string) 或 #f
   kitty-flags   ; int 或 #f  (CSI ? u)
   kitty-graphics? ; boolean（仅当显式开启 APC 查询）
   cursor        ; (cons row col) 或 #f  (DSR/CPR)
   text-size     ; (cons rows cols) 或 #f  (CSI 18 t)
   pixel-size    ; (cons height width) 或 #f (CSI 14 t)
   cell-size     ; (cons height width) 或 #f (CSI 16 t)
   private-modes ; hash: mode -> Pm
   ansi-modes    ; hash: mode -> Pm
   osc           ; hash: 10/11/12 -> "rgb:..."
   palette       ; hash: index -> "rgb:..."
   raw)          ; bytes —— 原始回复（调试用）
  #:transparent)

;; ── 模式判定（纯查表，不含启用逻辑）──
(define (caps-mode-pm caps mode [ansi? #f])
  (hash-ref (if ansi? (terminal-caps-ansi-modes caps)
                (terminal-caps-private-modes caps))
            mode #f))

(define (caps-mode-state caps mode [ansi? #f])
  (define pm (caps-mode-pm caps mode ansi?))
  (and pm (pm->state pm)))

;; 终端认识这个模式号（Pm 非 0）
(define (caps-mode-recognized? caps mode [ansi? #f])
  (define pm (caps-mode-pm caps mode ansi?))
  (and pm (not (eqv? pm 0))))

;; 当前处于“开”（set 或 permanently-set）
(define (caps-mode-on? caps mode [ansi? #f])
  (and (memv (caps-mode-pm caps mode ansi?) '(1 3)) #t))

;; 可自由置位/复位（set/reset）
(define (caps-mode-settable? caps mode [ansi? #f])
  (and (memv (caps-mode-pm caps mode ansi?) '(1 2)) #t))

;; 能用：能处于“开”（set/reset/permanently-set）；permanently-reset 与不识别则不能
(define (caps-mode-available? caps mode [ansi? #f])
  (and (memv (caps-mode-pm caps mode ansi?) '(1 2 3)) #t))

;; 兼容旧名：= available?（能开即为支持）
(define (caps-mode-supported? caps mode [ansi? #f])
  (caps-mode-available? caps mode ansi?))

(define (caps-mode-name mode [ansi? #f])
  (cond [(assoc mode (if ansi? ansi-mode-names dec-private-mode-names)) => cdr]
        [else #f]))

;; ── 颜色 ──
(define (caps-color caps code)          ; 10 前景 / 11 背景 / 12 光标
  (hash-ref (terminal-caps-osc caps) code #f))

(define (caps-palette-color caps i)
  (hash-ref (terminal-caps-palette caps) i #f))

(define (caps-truecolor? caps)
  (for/or ([v (in-list (append (hash-values (terminal-caps-osc caps))
                               (hash-values (terminal-caps-palette caps))))])
    (and (string? v) (regexp-match? #px"^rgb:" v))))

;; ════════════════════════════════════════════════════════════════
;; 探测
;; ════════════════════════════════════════════════════════════════

(define (probe-terminal
         #:private-modes [private-modes default-private-modes]
         #:ansi-modes [ansi-modes default-ansi-modes]
         #:xtgettcap-names [names default-xtgettcap-names]
         #:palette-indices [palette-indices default-palette-indices]
         #:kitty-graphics? [kitty-graphics? #f]
         #:timeout [timeout 0.30]
         #:idle [idle 0.05])
  ;; 查询顺序：身份 → 逐功能 → 颜色 → 尺寸 → DSR → DA2 → DA1(哨兵最后)
  (define queries
    (append (list (xtversion-query) (da3-query))
            (list (xtgettcap-query names))
            (list (kitty-flags-query))
            (if kitty-graphics? (list kitty-graphics-query) '())
            (for/list ([m (in-list private-modes)]) (decrqm-private-query m))
            (for/list ([m (in-list ansi-modes)])    (decrqm-ansi-query m))
            (list (osc-color-query 10) (osc-color-query 11) (osc-color-query 12))
            (for/list ([i (in-list palette-indices)]) (osc-palette-query i))
            (list (text-area-size-query) (text-area-pixel-size-query) (cell-pixel-size-query))
            (list (dsr-query))
            (list (da2-query))
            (list (da1-query))))
  (define raw (exchange-queries queries #:timeout timeout #:idle idle))

  (define da1  (parse-da1 raw))
  (define da2  (parse-da2 raw))
  (define da3  (parse-da3 raw))
  (define xtv  (parse-xtversion raw))
  (define tcaps (for/hash ([e (in-list (parse-xtgettcap raw))])
                  (values (car e) (cadr e))))
  (define kitty (for/first ([f (in-list (parse-kitty-flags raw))]) f))
  (define cursor (for/first ([c (in-list (parse-dsr raw))]) c))
  (define priv (for/hash ([p (in-list (parse-decrqm-private raw))])
                 (values (car p) (cdr p))))
  (define ansi (for/hash ([p (in-list (parse-decrqm-ansi raw))])
                 (values (car p) (cdr p))))
  (define wins (parse-window-reports raw))

  ;; OSC：10/11/12 与 4;idx
  (define osc (make-hash))
  (define palette (make-hash))
  (for ([s (in-list (parse-osc raw))])
    (define parts (string-split s ";"))
    (define code (and (pair? parts) (string->number (car parts))))
    (cond
      [(and code (memv code '(10 11 12)) (>= (length parts) 2))
       (hash-set! osc code (string-join (cdr parts) ";"))]
      [(and code (= code 4) (>= (length parts) 3))
       (define idx (string->number (cadr parts)))
       (when idx (hash-set! palette idx (string-join (cddr parts) ";")))]
      [else (void)]))

  ;; 身份：XTVERSION > XTGETTCAP(TN) > DA2（DA2 不能唯一识别，放最后）
  (define tn (hash-ref tcaps "TN" #f))
  (define-values (id id-source)
    (cond [xtv                   (values xtv 'xtversion)]
          [(and tn (string? tn)) (values tn 'xtgettcap)]
          [(pair? da2)           (values (format "DA2:~a"
                                                 (string-join (map number->string (car da2)) ";"))
                                         'da2)]
          [else                  (values "unknown" 'unknown)]))
  (define-values (nm ver)
    (if (eq? id-source 'xtversion) (split-name-version xtv) (values #f #f)))

  (define tmux?
    (or (and (getenv "TMUX") #t)
        (and xtv (string-contains? (string-downcase xtv) "tmux"))
        (and (pair? da2) (= (car (car da2)) 84))   ; notcurses: tmux 用 84
        #f))

  (terminal-caps id id-source nm ver tmux?
                 da1 da2 da3 xtv tcaps
                 kitty (and kitty-graphics? (kitty-graphics-ok? raw))
                 cursor
                 (hash-ref wins 8 #f)   ; 文本区 cells
                 (hash-ref wins 4 #f)   ; 文本区 pixels
                 (hash-ref wins 6 #f)   ; 单元 pixels
                 priv ansi osc palette raw))
