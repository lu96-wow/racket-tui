#lang racket

;; ════════════════════════════════════════════════════════════════
;; terminal-support/query.rkt
;;
;; 终端查询序列的构造 + 回复解析（纯函数：无 I/O、无 FFI）。
;;
;; 这些序列/判定的正确实现取自现成开源项目：
;;   · xterm ctlseqs          https://invisible-island.net/xterm/ctlseqs/ctlseqs.html
;;   · kitty keyboard         https://sw.kovidgoyal.net/kitty/keyboard-protocol/
;;   · ncurses u6..u9         man 5 user_caps / terminfo(5)
;;   · notcurses termdesc.c   IDQUERIES = DA3 + XTVERSION + XTGETTCAP + DA2
;;   · crossterm unix.rs      kitty 探测 = "CSI ?u" + "CSI c" 哨兵
;;   · termwiz caps/probed.rs XTVERSION 探测 + DA1 哨兵
;;   · Vim term.c             DECRQM(2026/2048) + builtin kitty/modifyOtherKeys
;; ════════════════════════════════════════════════════════════════

(require racket/string)

(provide ESC ST BEL
         ;; 查询构造
         da1-query da2-query da3-query xtversion-query
         dsr-query kitty-flags-query kitty-graphics-query xtmodkeys-query
         decrqm-private-query decrqm-ansi-query
         xtgettcap-query osc-color-query osc-palette-query
         text-area-size-query text-area-pixel-size-query cell-pixel-size-query
         ;; 解析
         parse-da1 parse-da2 parse-da3 parse-xtversion parse-dcs
         parse-dsr parse-kitty-flags parse-apc kitty-graphics-ok? parse-xtmodkeys
         parse-decrqm-private parse-decrqm-ansi
         parse-xtgettcap parse-osc parse-window-reports
         da1-reply?
         ;; 复用取值函数（从整段原始回复里取单项；供 spec 的 parse 用）
         decrqm-private-pm decrqm-ansi-pm
         osc-value osc-palette-value window-size
         xtgettcap-lookup cursor-position kitty-flags-value
         ;; 辅助
         bytes->hex hex->bytes pm->state pm->label
         split-name-version)

;; ── 基础字节 ──
(define ESC (bytes 27))
(define ST  (bytes 27 92))   ; ESC \
(define BEL (bytes 7))

(define (b->s b) (bytes->string/latin-1 b))
(define (s->b s) (string->bytes/latin-1 s))

;; Racket 正则不支持 \x1b / \xHH(\d 也不支持)，ESC 只能 regexp-quote 真字符
(define ESC-C (string (integer->char 27)))
(define BEL-C (string (integer->char 7)))
(define ESC-Q (regexp-quote ESC-C))
(define (rx . parts) (regexp (apply string-append ESC-Q parts)))

;; ════════════════════════════════════════════════════════════════
;; 查询构造
;; ════════════════════════════════════════════════════════════════

;; Device Attributes
(define (da1-query) (bytes-append ESC (s->b "[c")))       ; Primary  (哨兵)
(define (da2-query) (bytes-append ESC (s->b "[>c")))      ; Secondary (身份，放最后问)
(define (da3-query) (bytes-append ESC (s->b "[=c")))      ; Tertiary  (VTE 识别)

;; XTVERSION：名字+版本
(define (xtversion-query) (bytes-append ESC (s->b "[>0q")))

;; DSR：光标位置（= ncurses u6/u7，取尺寸兜底）
(define (dsr-query) (bytes-append ESC (s->b "[6n")))

;; kitty 键盘渐进增强 flags
(define (kitty-flags-query) (bytes-append ESC (s->b "[?u")))

;; modifyOtherKeys 级别查询（xterm 377+；Vim 的 t_CRK）
(define (xtmodkeys-query) (bytes-append ESC (s->b "[?4m")))

;; DECRQM：某模式是否被识别/置位
(define (decrqm-private-query mode) (bytes-append ESC (s->b (format "[?~a$p" mode))))
(define (decrqm-ansi-query mode)    (bytes-append ESC (s->b (format "[~a$p" mode))))

;; XTGETTCAP：直接查 terminfo 能力（名字按字节 hex，多个用 ';' 分隔）
(define (byte->hex2 x)
  (string-upcase (if (< x 16)
                     (string-append "0" (number->string x 16))
                     (number->string x 16))))
(define (bytes->hex b)
  (apply string-append (for/list ([x (in-bytes b)]) (byte->hex2 x))))

(define (xtgettcap-query names)   ; names : (listof string)
  (bytes-append ESC (s->b "P+q")
                (s->b (string-join (for/list ([n (in-list names)])
                                     (bytes->hex (s->b n))) ";"))
                ST))

;; OSC 颜色查询：10=前景 11=背景 12=光标
(define (osc-color-query n)
  (bytes-append ESC (s->b (format "]~a;?" n)) ST))

;; OSC 4：调色板第 i 号色
(define (osc-palette-query i)
  (bytes-append ESC (s->b (format "]4;~a;?" i)) ST))

;; XTWINOPS 尺寸查询（termwiz 也用）
(define (text-area-size-query)       (bytes-append ESC (s->b "[18t")))  ; → CSI 8;rows;cols t
(define (text-area-pixel-size-query) (bytes-append ESC (s->b "[14t")))  ; → CSI 4;h;w t
(define (cell-pixel-size-query)      (bytes-append ESC (s->b "[16t")))  ; → CSI 6;h;w t

;; kitty 图形协议查询（APC，默认不发：不消费 APC 的终端会把字节泄漏到屏幕）
(define kitty-graphics-query
  (bytes-append ESC (bytes 95) (s->b "Gi=1,a=q;") ST))   ; ESC _ G i=1,a=q; ESC \

;; ════════════════════════════════════════════════════════════════
;; 解析 —— 全部作用在"累积的原始回复字节"上
;; ════════════════════════════════════════════════════════════════

;; regexp-match* 只返回整串（不含捕获组），故逐串再用 regexp-match 取组
(define (all-matches rx b)
  (for/list ([s (in-list (regexp-match* rx (b->s b)))])
    (regexp-match rx s)))

(define (split-nums s)
  (for/list ([x (in-list (string-split s ";"))] #:unless (string=? x ""))
    (string->number x)))

;; CSI ? Pm... c   → (listof (listof int))
(define (parse-da1 b)
  (for/list ([m (in-list (all-matches (rx "\\[\\?([0-9;]*)c") b))])
    (split-nums (cadr m))))

;; CSI > Pp;Pv;Pc c → (listof (listof int))
(define (parse-da2 b)
  (for/list ([m (in-list (all-matches (rx "\\[>([0-9;]*)c") b))])
    (split-nums (cadr m))))

;; CSI r;c R → (listof (cons row col))
(define (parse-dsr b)
  (for/list ([m (in-list (all-matches (rx "\\[([0-9]+);([0-9]+)R") b))])
    (cons (string->number (cadr m)) (string->number (caddr m)))))

;; CSI ? flags u → (listof int)
(define (parse-kitty-flags b)
  (for/list ([m (in-list (all-matches (rx "\\[\\?([0-9]+)u") b))])
    (string->number (cadr m))))

;; CSI > 4 ; Pv m → Pv （modifyOtherKeys 级别）
(define xtmodkeys-rx (rx "\\[>4;([0-9]+)m"))
(define (parse-xtmodkeys b)
  (for/first ([m (in-list (all-matches xtmodkeys-rx b))])
    (string->number (cadr m))))

;; CSI ? Ps;Pm $ y → (listof (cons mode Pm))
(define (parse-decrqm-private b)
  (for/list ([m (in-list (all-matches (rx "\\[\\?([0-9]+);([0-9]+)\\$y") b))])
    (cons (string->number (cadr m)) (string->number (caddr m)))))

;; CSI Ps;Pm $ y → (listof (cons mode Pm))
(define (parse-decrqm-ansi b)
  (for/list ([m (in-list (all-matches (rx "\\[([0-9]+);([0-9]+)\\$y") b))])
    (cons (string->number (cadr m)) (string->number (caddr m)))))

;; DCS ... ST → (listof body-string)   例：">|VTE(8001)"、"1+r544E=..."
(define dcs-rx (regexp (string-append ESC-Q "P(.*?)" ESC-Q "\\\\")))
(define (parse-dcs b)
  (for/list ([m (in-list (all-matches dcs-rx b))])
    (cadr m)))

;; XTVERSION 回复体：">|NAME(VERSION)"
(define (parse-xtversion b)
  (for/first ([body (in-list (parse-dcs b))]
              #:when (regexp-match? #px"^>\\|" body))
    (substring body 2)))

;; DA3 回复体："!|..."（VTE 等）
(define (parse-da3 b)
  (for/first ([body (in-list (parse-dcs b))]
              #:when (regexp-match? #px"^!\\|" body))
    (substring body 2)))

;; XTGETTCAP 回复体："[01]+rNAMEHEX[=VALUEHEX]"
;; → (listof (list name found? value-or-#f))
(define xtgettcap-body-rx
  #px"^([01])\\+r([0-9A-Fa-f]+)(?:=([0-9A-Fa-f]+))?$")
(define (parse-xtgettcap b)
  (for/list ([body (in-list (parse-dcs b))]
             #:when (regexp-match? #px"^[01]\\+r" body))
    (define m (regexp-match xtgettcap-body-rx body))
    (define name  (b->s (hex->bytes (caddr m))))
    (define value (and (cadddr m) (b->s (hex->bytes (cadddr m)))))
    (list name (equal? (cadr m) "1") value)))

;; OSC ... (BEL | ST) → (listof content-string)  例："10;rgb:ffff/ffff/ffff"
(define osc-rx
  (regexp (string-append ESC-Q "\\]([^" BEL-C ESC-C "]*?)(?:" BEL-C "|" ESC-Q "\\\\)")))
(define (parse-osc b)
  (for/list ([m (in-list (all-matches osc-rx b))])
    (cadr m)))

;; APC ... (BEL | ST) → (listof content-string)  例："Gi=1;OK"
(define apc-rx
  (regexp (string-append ESC-Q "_([^" BEL-C ESC-C "]*?)(?:" BEL-C "|" ESC-Q "\\\\)")))
(define (parse-apc b)
  (for/list ([m (in-list (all-matches apc-rx b))])
    (cadr m)))

(define (kitty-graphics-ok? b)
  (for/or ([s (in-list (parse-apc b))]) (regexp-match? #px"^G[^;]*;OK" s)))

;; XTWINOPS 尺寸报告 → hash: 4/6/8 -> (cons 高/行 宽/列)
;;   CSI 8 ; rows ; cols t   文本区(cells)
;;   CSI 4 ; height ; width t 文本区(pixels)
;;   CSI 6 ; height ; width t 单元(pixels)
(define window-rx (rx "\\[([0-9]+);([0-9]+);([0-9]+)t"))
(define (parse-window-reports b)
  (for/hash ([m (in-list (all-matches window-rx b))])
    (values (string->number (cadr m))
            (cons (string->number (caddr m)) (string->number (cadddr m))))))

;; DA1 回复是否已出现：CSI ? ... c  （用作收尾哨兵）
(define da1-reply-rx (rx "\\[\\?[0-9;]*c"))
(define (da1-reply? b)
  (regexp-match? da1-reply-rx (b->s b)))

;; ════════════════════════════════════════════════════════════════
;; 复用取值函数 —— 从整段原始回复里取某一项
;; ════════════════════════════════════════════════════════════════

(define (decrqm-private-pm raw mode)
  (for/first ([p (in-list (parse-decrqm-private raw))] #:when (= (car p) mode)) (cdr p)))

(define (decrqm-ansi-pm raw mode)
  (for/first ([p (in-list (parse-decrqm-ansi raw))] #:when (= (car p) mode)) (cdr p)))

(define (osc-value raw code)
  (define prefix (format "~a;" code))
  (for/first ([s (in-list (parse-osc raw))] #:when (string-prefix? s prefix))
    (substring s (string-length prefix))))

(define (osc-palette-value raw idx)
  (define prefix (format "4;~a;" idx))
  (for/first ([s (in-list (parse-osc raw))] #:when (string-prefix? s prefix))
    (substring s (string-length prefix))))

(define (window-size raw code) (hash-ref (parse-window-reports raw) code #f))

(define (xtgettcap-lookup raw name)
  (for/first ([e (in-list (parse-xtgettcap raw))] #:when (string=? (car e) name))
    (and (cadr e) (caddr e))))

(define (cursor-position raw)
  (for/first ([c (in-list (parse-dsr raw))]) c))

(define (kitty-flags-value raw)
  (for/first ([f (in-list (parse-kitty-flags raw))]) f))

;; ════════════════════════════════════════════════════════════════
;; 辅助
;; ════════════════════════════════════════════════════════════════

(define (hex->bytes h)
  (define n (- (string-length h) (remainder (string-length h) 2)))
  (list->bytes
   (for/list ([i (in-range 0 n 2)])
     (string->number (substring h i (+ i 2)) 16))))

;; Pm 值 → 原始状态符号（不合并，保留语义）
(define (pm->state pm)
  (case pm
    [(1) 'set] [(2) 'reset]
    [(3) 'permanently-set] [(4) 'permanently-reset]
    [(0) 'unrecognized] [else 'unknown]))

(define (pm->label pm)
  (case pm
    [(0) "not recognized"] [(1) "set"] [(2) "reset"]
    [(3) "permanently set"] [(4) "permanently reset"]
    [else "?"]))

;; "VTE(8001)" → (values "VTE" "8001")；无括号则 (values s #f)
(define (split-name-version s)
  (define m (regexp-match #px"^(.*?)\\((.*)\\)$" s))
  (if m (values (cadr m) (caddr m)) (values s #f)))
