#lang racket

;; ════════════════════════════════════════════════════════════════
;; demo/terminal-support-detect.rkt —— 全量探测示例
;;
;;   racket demo/terminal-support-detect.rkt
;;
;; 演示完整的组合流程（terminal-support 不做任何决策）：
;;   ① 定查哪些  group->queries (profile 'full + kitty 图形)
;;   ② 调 api 查  run-queries/raw（显式端口）
;;   ③ 返回 hash  id -> value
;;   ④ 句柄查表  assemble-caps #:env -> caps；再打印
;;
;; 本文件只负责"进入 raw 模式 + 打印"，raw 模式借 base 的 termios。
;; ════════════════════════════════════════════════════════════════

(require racket/list
         racket/string
         "../base/terminal/base.rkt"
         "../terminal-support/main.rkt")

(define (say . xs) (for-each display xs) (display "\r\n") (flush-output))
(define (pad s n) (~a s #:min-width n))
(define (pair->s p) (if p (format "~a x ~a" (car p) (cdr p)) "-"))
(define (lst->s l) (if (null? l) "-" (string-join (map ~a l) ", ")))
;; 终端派生的字符串一律可视化后再打印（否则其中的控制序列会被执行）
(define (vs x) (if (string? x) (vis-string x) (or x "-")))
(define (state-s st)
  (case st [(set) "set"] [(reset) "reset"]
    [(permanently-set) "perm-set"] [(permanently-reset) "perm-reset"]
    [(unrecognized) "unrecognized"] [else "—"]))

;; ── ③ 打印原始结果 hash（id -> value）──
(define (print-results results)
  (say "── 原始结果 hash (id -> value) ──")
  (for ([k (in-list (sort (hash-keys results)
                          (λ (a b) (string<? (format "~a" a) (format "~a" b)))))])
    (say (format "  ~a => ~s" k (hash-ref results k)))))

;; ── ④ 打印组装后的句柄（caps）──
(define (print-caps caps)
  (say "")
  (say "── caps 句柄 ──")
  (say (format "  id/source : ~a  (~a)" (vs (caps-id caps)) (caps-id-source caps)))
  (say (format "  name/ver  : ~a / ~a" (vs (caps-name caps)) (vs (caps-version caps))))
  (say (format "  mux/ssh?  : ~a / ~a" (caps-mux caps) (caps-ssh? caps)))
  (say (format "  DA1/2/3   : ~a | ~a | ~a"
               (lst->s (map ~a (caps-da1 caps))) (lst->s (map ~a (caps-da2 caps)))
               (vs (caps-da3 caps))))
  (say (format "  DA1 型号/属性: ~a | ~a" (or (caps-da1-model caps) "-") (lst->s (caps-da1-attrs caps))))
  (say (format "  DA2 型号  : ~a" (or (caps-da2-model caps) "-")))
  (say (format "  尺寸      : cells ~a / pixels ~a / 单元 ~a / 光标 ~a"
               (pair->s (caps-text-size caps)) (pair->s (caps-pixel-size caps))
               (pair->s (caps-cell-size caps)) (pair->s (caps-cursor caps))))
  (say (format "  色深      : ~a   (truecolor=~a, Co=~a, osc-rgb?=~a)"
               (caps-color-level caps) (caps-truecolor caps)
               (or (caps-colors-count caps) "-") (caps-osc-rgb? caps)))
  (say (format "  kitty     : flags=~a graphics=~a" (caps-kitty-flags caps) (caps-kitty-graphics? caps)))
  (say (format "  xtmodkeys : ~a" (caps-xtmodkeys caps)))
  (say (format "  XTGETTCAP :~a" (if (caps-xtgettcap? caps) "" " （未实现）")))
  (when (caps-xtgettcap? caps)
    (for ([k (in-list (sort (hash-keys (caps-xtgettcap caps)) string<?))])
      (define v (hash-ref (caps-xtgettcap caps) k))
      (say (format "    ~a = ~a" (pad k 6) (if (string? v) (vis-string v) "(bool)")))))
  (say "")
  (say "  私有模式 (DECRQM CSI ? Ps $ p):")
  (for ([m (in-list (sort (hash-keys (caps-private-modes caps)) <))])
    (say (format "    ~a = ~a (~a)  ~a"
                 (pad (~a m) 6) (caps-mode-pm caps m) (state-s (caps-mode-state caps m))
                 (or (caps-mode-name m) ""))))
  (say "  ANSI 模式 (DECRQM CSI Ps $ p):")
  (for ([m (in-list (sort (hash-keys (caps-ansi-modes caps)) <))])
    (say (format "    ~a = ~a (~a)  ~a"
                 (pad (~a m) 6) (caps-mode-pm caps m #t) (state-s (caps-mode-state caps m #t))
                 (or (caps-mode-name m #t) "")))))

(define (run)
  ;; ① 定查哪些：全部组 + kitty 图形
  (define queries (group->queries (profile-groups 'full) #:kitty-graphics? #t))
  (say (format "查询条数: ~a" (length queries)))

  ;; ② 调 api 查：显式端口
  (define t0 (current-inexact-milliseconds))
  (define-values (raw results)
    (run-queries/raw queries
                     #:in (current-input-port) #:out (current-output-port)
                     #:timeout 0.30 #:idle 0.05))
  (define ms (- (current-inexact-milliseconds) t0))
  (say (format "原始回复 ~a 字节，耗时 ~a ms" (bytes-length raw) (real->decimal-string ms 1)))
  (say "")

  ;; ③ 原始 hash
  (print-results results)

  ;; ④ 组装成句柄（env 显式快照）
  (define caps (assemble-caps results raw #:env (env-snapshot)))
  (print-caps caps))

(define (main)
  (unless (terminal?)
    (eprintf "需要真实 TTY（stdin 要是终端）。\n")
    (exit 2))
  (dynamic-wind
   void
   (λ () (enter-raw-mode!) (run))
   (λ ()
     ;; 退出前吞掉迟到回复，别泄漏给 shell
     (with-handlers ([exn? void]) (read-reply #:timeout 0.10 #:idle 0.03))
     (exit-raw-mode!)
     (say "完成。"))))

(module+ main (main))
