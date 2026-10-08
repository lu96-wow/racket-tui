#lang racket

;; ════════════════════════════════════════════════════════════════
;; terminal-support/env.rkt —— 环境事实
;;
;; 只管「从显式环境快照里读出会影响能力解读的事实」：
;;   · env-snapshot       抓取当前环境（由调用方显式调用，库不隐式读 env）
;;   · detect-mux         多路复用器（会代答终端查询）
;;   · env-ssh?           SSH 会话（env 提示可能过时；查询本身仍透明）
;;
;; 不做任何启用决策，也不在此模块外偷偷读环境。
;; ════════════════════════════════════════════════════════════════

(require racket/string)

(provide env-vars env-snapshot detect-mux env-ssh?)

;; 影响能力解读的环境变量 → 快照 hash（值可为 #f）
(define env-vars
  '("TERM" "COLORTERM" "TMUX" "STY" "ZELLIJ"
    "SSH_CONNECTION" "SSH_CLIENT" "SSH_TTY"))

(define (env-snapshot)
  (for/hash ([k (in-list env-vars)]) (values k (getenv k))))

;; 多路复用器：拦截/代答终端查询，故 caps 描述的是它而非外层终端。
;; 只能启发式；顺序 = 由内到外的常见假设。
(define (detect-mux env xtv da2)
  (define (v k) (hash-ref env k #f))
  (define t (let ([term (v "TERM")]) (and term (string-downcase term))))
  (define da2-pp (and (pair? da2) (pair? (car da2)) (car (car da2))))
  (cond
    [(or (v "TMUX")
         (and xtv (string-contains? (string-downcase xtv) "tmux"))
         (and da2-pp (= da2-pp 84))          ; notcurses: tmux 的 DA2 Pp=84
         (and t (string-prefix? t "tmux")))
     'tmux]
    [(or (v "STY") (and t (string-prefix? t "screen")))  'screen]
    [(v "ZELLIJ")                                        'zellij]
    [else #f]))

(define (env-ssh? env)
  (or (and (hash-ref env "SSH_CONNECTION" #f) #t)
      (and (hash-ref env "SSH_CLIENT" #f) #t)
      (and (hash-ref env "SSH_TTY" #f) #t)
      #f))
