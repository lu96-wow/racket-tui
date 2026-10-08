#!/usr/bin/env racket
#lang racket

;; ════════════════════════════════════════════════════════════════
;; tools/probe-terminal.rkt
;;
;; 在真实终端里打印 terminal-support 探测到的能力表。
;; 查询逻辑都在 ../terminal-support/，本文件只负责 raw 模式和排版。
;;
;;   racket tools/probe-terminal.rkt                  ; 默认 profile=standard
;;   racket tools/probe-terminal.rkt --full           ; 查全部（82+6 模式）
;;   racket tools/probe-terminal.rkt --profile minimal
;;   racket tools/probe-terminal.rkt --groups mouse,paste,colors
;;   racket tools/probe-terminal.rkt --raw            ; 附原始回复字节
;;   racket tools/probe-terminal.rkt --kitty-graphics ; 额外探 kitty 图形(APC)
;; ════════════════════════════════════════════════════════════════

(require racket/cmdline
         racket/list
         racket/string
         "../base/terminal/base.rkt"
         "../terminal-support/main.rkt")

(define profile 'standard)
(define groups-opt #f)
(define raw? #f)
(define kitty-graphics? #f)
(define timeout 0.30)
(define idle 0.05)

(define (say . xs) (for-each display xs) (display "\r\n") (flush-output))
(define (env-or k) (or (getenv k) "-"))
(define (fmt-nums ns) (string-join (map number->string ns) ";"))

;; 显示宽度：CJK 算 2 列，其余算 1（用于列对齐）
(define (char-width c)
  (define n (char->integer c))
  (if (or (<= #x1100 n #x115F) (<= #x2E80 n #xA4CF) (<= #xAC00 n #xD7A3)
          (<= #xF900 n #xFAFF) (<= #xFE30 n #xFE4F) (<= #xFF00 n #xFF60)
          (<= #xFFE0 n #xFFE6))
      2 1))
(define (str-width s) (for/sum ([c (in-string s)]) (char-width c)))
(define (pad s n) (string-append s (make-string (max 0 (- n (str-width s))) #\space)))
(define (pair->s p) (if p (format "~a x ~a" (car p) (cdr p)) "-"))
(define (lst->s l) (if (null? l) "-" (string-join l ", ")))

(define (state-label st)
  (case st
    [(set) "置位"] [(reset) "复位(可设)"]
    [(permanently-set) "永久置位"] [(permanently-reset) "永久复位"]
    [(unrecognized) "不识别"] [else "无回复"]))

(define (da3-show s)
  (if (and s (regexp-match? #px"^[0-9A-Fa-f]+$" s) (even? (string-length s)))
      (format "~a  (hex → ~s)" s (hex->bytes s))
      (or s "-")))

(define (run)
  (define groups (or groups-opt
                     (with-handlers ([exn? (λ (e) (eprintf "~a\n" (exn-message e)) (exit 2))])
                       (profile-groups profile))))
  (define private-modes (group-private-modes groups))
  (define ansi-modes (group-ansi-modes groups))

  (say (format "TERM=~a  COLORTERM=~a  TERM_PROGRAM=~a  VTE_VERSION=~a"
               (env-or "TERM") (env-or "COLORTERM") (env-or "TERM_PROGRAM")
               (env-or "VTE_VERSION")))
  (say (format "profile=~a  groups=~a" (if groups-opt "(自定义)" profile) groups))
  (say "（只读查询；Ctrl-C 可中断）")
  (say "")

  (define t0 (current-inexact-milliseconds))
  (define caps (probe-terminal #:groups groups
                               #:timeout timeout #:idle idle
                               #:kitty-graphics? kitty-graphics?))
  (define probe-ms (- (current-inexact-milliseconds) t0))

  (say (format "== 身份 ==   (探测耗时 ~a ms)" (real->decimal-string probe-ms 1)))
  (say (format "  id        : ~a   (来源 ~a)" (caps-id caps) (caps-id-source caps)))
  (when (caps-name caps)
    (say (format "  name/ver  : ~a / ~a" (caps-name caps) (caps-version caps))))
  (say (format "  tmux?     : ~a" (caps-tmux? caps)))
  (say (format "  XTVERSION : ~a" (or (caps-xtversion caps) "-")))
  (say (format "  DA1       : ~a" (lst->s (map fmt-nums (caps-da1 caps)))))
  (say (format "  DA1 属性  : ~a" (lst->s (caps-da1-attrs caps))))
  (say (format "  DA2       : ~a   型号: ~a" (lst->s (map fmt-nums (caps-da2 caps))) (or (caps-da2-model caps) "-")))
  (say (format "  DA3       : ~a" (da3-show (caps-da3 caps))))
  (define tc (caps-xtgettcap caps))
  (say (format "  XTGETTCAP : ~a"
               (cond
                 [(not (caps-xtgettcap? caps)) "（未实现 DCS +q）"]
                 [(zero? (hash-count tc)) "（有回复，但所查名字都未找到）"]
                 [else (string-join (for/list ([(k v) (in-hash tc)])
                                      (format "~a=~a" k (if (string? v) v "(有)"))) "  ")])))
  (say "")

  (say "== 尺寸 ==")
  (say (format "  文本区 cells : ~a" (pair->s (caps-text-size caps))))
  (say (format "  文本区 pixels: ~a" (pair->s (caps-pixel-size caps))))
  (say (format "  单元 pixels  : ~a" (pair->s (caps-cell-size caps))))
  (say (format "  DSR 光标     : ~a" (pair->s (caps-cursor caps))))
  (say "")

  (define (mode-table title modes ansi?)
    (say title)
    (say (format "  ~a  ~a  ~a  ~a" (pad "模式" 8) (pad "Pm" 3) (pad "判定" 10) "名称"))
    (for ([m (in-list (sort modes <))])
      (define pm (caps-mode-pm caps m ansi?))
      (say (format "  ~a  ~a  ~a  ~a"
                   (pad (format "~a~a" (if ansi? "" "?") m) 8)
                   (pad (if pm (number->string pm) "-") 3)
                   (pad (state-label (caps-mode-state caps m ansi?)) 10)
                   (or (caps-mode-name m ansi?) "")))))
  (mode-table "== DECRQM 私有模式 ==" private-modes #f)
  (say "")
  (mode-table "== DECRQM ANSI 模式 ==" ansi-modes #t)
  (say "")

  (say "== 能力判定 ==")
  (for ([m (in-list (sort private-modes <))])
    (when (memv m '(1006 1002 1003 1004 1005 1016 47 1049 2004 2026 2027 2048))
      (say (format "  ~a  ~a  ~a"
                   (pad (format "?~a" m) 8)
                   (pad (or (caps-mode-name m) (format "~a" m)) 22)
                   (state-label (caps-mode-state caps m))))))
  (say "")

  (say "== 颜色 (OSC) ==")
  (define (color-line label code)
    (define s (caps-color caps code))
    (define rgb (caps-color-rgb caps code))
    (say (format "  ~a: ~a~a" label (or s "-")
                 (if rgb (format "   (~a,~a,~a)" (car rgb) (cadr rgb) (caddr rgb)) ""))))
  (color-line "fg(10) " 10)
  (color-line "bg(11) " 11)
  (color-line "cur(12)" 12)
  (say (format "  色深: ~a   osc-rgb?: ~a   真彩(XTGETTCAP RGB/Tc): ~a   色数(Co): ~a"
               (caps-color-level caps) (caps-osc-rgb? caps)
               (case (caps-truecolor caps) [(#t) "#t"] [(#f) "#f"] [else "未知"])
               (or (caps-colors-count caps) "-")))
  (define pal (caps-palette caps))
  (when (positive? (hash-count pal))
    (say (format "  调色板 : ~a"
                 (string-join (for/list ([i (in-range 16)])
                                (format "~a=~a" i (or (caps-palette-color caps i) "-"))) "  "))))
  (say "")

  (say "== kitty ==")
  (say (format "  键盘 flags : ~a" (or (caps-kitty-flags caps) "（无回复）")))
  (say (format "  modifyOtherKeys : ~a" (or (caps-xtmodkeys caps) "（无回复）")))
  (say (format "  graphics   : ~a" (if kitty-graphics?
                                       (caps-kitty-graphics? caps)
                                       "（未查询）")))
  (say "")

  (when raw?
    (say "== 原始回复 ==")
    (say (format "  ~s" (caps-raw caps)))
    (say "")))

(define (main)
  (command-line
   #:program "probe-terminal"
   #:once-each
   [("--profile") p "minimal | standard | full（默认 standard）" (set! profile (string->symbol p))]
   [("--full") "等价 --profile full" (set! profile 'full)]
   [("--groups") g "逗号分隔的组名（覆盖 profile）"
    (set! groups-opt (map string->symbol (string-split g ",")))]
   [("--raw") "附加原始回复字节" (set! raw? #t)]
   [("--kitty-graphics") "额外探 kitty 图形(APC，非 kitty 终端可能漏到屏幕)" (set! kitty-graphics? #t)]
   [("--timeout") t "总超时秒数（默认 0.30）" (set! timeout (string->number t))]
   [("--idle") t "空闲超时秒数（默认 0.05）" (set! idle (string->number t))]
   #:args ()
   (unless (terminal?)
     (eprintf "错误：必须在真实 TTY 里运行（stdin 要是终端）。\n")
     (eprintf "例如： racket tools/probe-terminal.rkt\n")
     (exit 2)))
  (dynamic-wind
   void
   (λ () (enter-raw-mode!) (run))
   (λ ()
     ;; 先吞掉可能迟到的回复，别让它们泄漏给 shell
     (with-handlers ([exn? void])
       (read-reply #:timeout 0.10 #:idle 0.03))
     (exit-raw-mode!)
     (say "完成。"))))

(module+ main (main))
