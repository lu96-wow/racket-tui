#!/usr/bin/env racket
#lang racket

;; ════════════════════════════════════════════════════════════════
;; tools/probe-terminal.rkt
;;
;; 在真实终端里打印 terminal-support 探测到的能力表。
;; 查询逻辑都在 ../terminal-support/，本文件只负责 raw 模式和排版。
;;
;;   racket tools/probe-terminal.rkt
;;   racket tools/probe-terminal.rkt --raw             ; 附原始回复字节
;;   racket tools/probe-terminal.rkt --kitty-graphics   ; 额外探 kitty 图形(APC,慎用)
;;   racket tools/probe-terminal.rkt --timeout 0.5
;; ════════════════════════════════════════════════════════════════

(require racket/cmdline
         racket/list
         "../base/terminal/base.rkt"
         "../terminal-support/main.rkt")

(define raw? #f)
(define kitty-graphics? #f)
(define timeout 0.30)
(define idle 0.05)

;; raw 模式下 OPOST/ONLCR 被关，换行自带宽 \r
(define (say . xs) (for-each display xs) (display "\r\n") (flush-output))
(define (env-or k) (or (getenv k) "-"))
(define (fmt-nums ns) (string-join (map number->string ns) ";"))
(define (pad s n) (~a s #:min-width n))
(define (pair->s p) (if p (format "~a x ~a" (car p) (cdr p)) "-"))

(define (state-label st)
  (case st
    [(set) "置位"]
    [(reset) "复位(可设)"]
    [(permanently-set) "永久置位"]
    [(permanently-reset) "永久复位"]
    [(unrecognized) "不识别"]
    [else "无回复"]))

(define (da3-show s)
  (if (and s (regexp-match? #px"^[0-9A-Fa-f]+$" s) (even? (string-length s)))
      (format "~a  (hex → ~s)" s (hex->bytes s))
      (or s "-")))

(define (run)
  (say (format "TERM=~a  COLORTERM=~a  TERM_PROGRAM=~a  VTE_VERSION=~a"
               (env-or "TERM") (env-or "COLORTERM") (env-or "TERM_PROGRAM")
               (env-or "VTE_VERSION")))
  (say "（只读查询；Ctrl-C 可中断）")
  (say "")

  (define t0 (current-inexact-milliseconds))
  (define caps (probe-terminal #:timeout timeout #:idle idle
                               #:kitty-graphics? kitty-graphics?))
  (define probe-ms (- (current-inexact-milliseconds) t0))

  (say (format "== 身份 ==   (探测耗时 ~a ms)" (real->decimal-string probe-ms 1)))
  (say (format "  id        : ~a   (来源 ~a)" (terminal-caps-id caps) (terminal-caps-id-source caps)))
  (when (terminal-caps-name caps)
    (say (format "  name/ver  : ~a / ~a" (terminal-caps-name caps) (terminal-caps-version caps))))
  (say (format "  tmux?     : ~a" (terminal-caps-tmux? caps)))
  (say (format "  XTVERSION : ~a" (or (terminal-caps-xtversion caps) "-")))
  (say (format "  DA1       : ~a" (map fmt-nums (terminal-caps-da1 caps))))
  (say (format "  DA2       : ~a" (map fmt-nums (terminal-caps-da2 caps))))
  (say (format "  DA3       : ~a" (da3-show (terminal-caps-da3 caps))))
  (define tc (terminal-caps-xtgettcap caps))
  (say (format "  XTGETTCAP : ~a"
               (if (zero? (hash-count tc))
                   "（无回复 / 终端未实现 DCS +q）"
                   (string-join (for/list ([(k v) (in-hash tc)])
                                  (format "~a=~a" k (or v "(无)"))) "  "))))
  (say "")

  (say "== 尺寸 ==")
  (say (format "  文本区 cells : ~a" (pair->s (terminal-caps-text-size caps))))
  (say (format "  文本区 pixels: ~a" (pair->s (terminal-caps-pixel-size caps))))
  (say (format "  单元 pixels  : ~a" (pair->s (terminal-caps-cell-size caps))))
  (say (format "  DSR 光标     : ~a" (pair->s (terminal-caps-cursor caps))))
  (say "")

  (define (mode-table title modes ansi?)
    (say title)
    (say (format "  ~a  ~a  ~a  ~a" (pad "模式" 8) (pad "Pm" 3) (pad "判定" 8) "名称"))
    (for ([m (in-list modes)])
      (define pm (caps-mode-pm caps m ansi?))
      (define st (caps-mode-state caps m ansi?))
      (say (format "  ~a  ~a  ~a  ~a"
                   (pad (format "~a~a" (if ansi? "" "?") m) 8)
                   (pad (if pm (number->string pm) "-") 3)
                   (pad (state-label st) 8)
                   (or (caps-mode-name m ansi?) "")))))

  (mode-table "== DECRQM 私有模式 ==" default-private-modes #f)
  (say "")
  (mode-table "== DECRQM ANSI 模式 ==" default-ansi-modes #t)
  (say "")

  (say "== 能力判定 ==")
  (say (format "  ~a  ~a  ~a  ~a" (pad "模式" 8) (pad "名称" 22) (pad "状态" 10) "可用?"))
  (for ([m (in-list '(1006 1002 1003 1004 1005 1015 1016 47 1049 2004 2026 2027 2048))])
    (say (format "  ~a  ~a  ~a  ~a"
                 (pad (format "?~a" m) 8)
                 (pad (or (caps-mode-name m) (format "~a" m)) 22)
                 (pad (state-label (caps-mode-state caps m)) 10)
                 (if (caps-mode-available? caps m) "可用" "不可用"))))
  (say "")

  (say "== 颜色 (OSC) ==")
  (say (format "  fg(10) : ~a" (or (caps-color caps 10) "-")))
  (say (format "  bg(11) : ~a" (or (caps-color caps 11) "-")))
  (say (format "  cur(12): ~a" (or (caps-color caps 12) "-")))
  (say (format "  truecolor: ~a" (caps-truecolor? caps)))
  (define pal (terminal-caps-palette caps))
  (when (positive? (hash-count pal))
    (say (format "  调色板 : ~a"
                 (string-join (for/list ([i (in-range 16)])
                                (format "~a=~a" i (or (caps-palette-color caps i) "-"))) "  "))))
  (say "")

  (say "== kitty ==")
  (say (format "  keyboard flags : ~a" (or (terminal-caps-kitty-flags caps) "（无回复）")))
  (say (format "  graphics       : ~a" (if kitty-graphics?
                                           (terminal-caps-kitty-graphics? caps)
                                           "（未查询）")))
  (say "")

  (when raw?
    (say "== 原始回复 ==")
    (say (format "  ~s" (terminal-caps-raw caps)))
    (say "")))

(define (main)
  (command-line
   #:program "probe-terminal"
   #:once-each
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
     ;; 先吞掉可能迟到的回复，别让它们泄漏给 shell（终端处理 80+ 查询可能较慢）
     (with-handlers ([exn? void])
       (read-reply #:timeout 0.10 #:idle 0.03))
     (exit-raw-mode!)
     (say "完成。"))))

(module+ main (main))
