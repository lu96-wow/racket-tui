#lang racket

;; ════════════════════════════════════════════════════════════════
;; terminal-support/caps.rkt —— 组装（纯数据，不做决策）+ 能力表访问
;;
;; `assemble-caps` 只把"按表查询"得到的结果表打包成 terminal-caps；
;; 它不决定启用任何东西。`probe-terminal` 只是 default-specs 的便捷封装。
;; ════════════════════════════════════════════════════════════════

(require racket/string
         racket/list
         "query.rkt"
         "spec.rkt"
         "run.rkt"
         "modes.rkt"
         "features.rkt"
         "groups.rkt")

(provide (struct-out terminal-caps)
         assemble-caps probe-terminal
         caps-mode-pm caps-mode-state caps-mode-supported?
         caps-mode-recognized? caps-mode-on? caps-mode-settable? caps-mode-available?
         caps-mode-name
         caps-da1-model caps-da1-features caps-da2-model
         caps-color caps-palette-color caps-colors-count
         caps-osc-rgb? caps-truecolor caps-truecolor?)

(struct terminal-caps
  (id            ; string
   id-source     ; 'xtversion | 'xtgettcap | 'da2 | 'unknown
   name version  ; string / #f
   tmux?         ; boolean
   da1 da2 da3 xtversion
   xtgettcap     ; hash: 已找到的能力名 -> 值(string | #t)
   xtgettcap?    ; boolean —— 终端是否实现了 DCS +q
   kitty-flags   ; int 或 #f
   kitty-graphics? ; boolean
   xtmodkeys     ; int 或 #f
   cursor text-size pixel-size cell-size
   private-modes ansi-modes   ; hash: mode -> Pm
   osc palette                ; hash
   raw)          ; bytes
  #:transparent)

;; ════════════════════════════════════════════════════════════════
;; 组装（纯函数：结果表 + 原始回复 → terminal-caps）
;; ════════════════════════════════════════════════════════════════

(define (assemble-caps results raw)
  (define (get k [d #f]) (hash-ref results k d))

  (define da1  (get 'da1 '()))
  (define da2  (get 'da2 '()))
  (define da3  (get 'da3 #f))
  (define xtv  (get 'xtversion #f))
  (define tcaps-list (get 'xtgettcap '()))
  (define tcaps (for/hash ([e (in-list tcaps-list)] #:when (cadr e))
                  (values (car e) (or (caddr e) #t))))
  (define xtgettcap? (pair? tcaps-list))

  ;; 从结果表里收 DECRQM / OSC / palette
  (define private-modes (make-hash))
  (define ansi-modes (make-hash))
  (define osc (make-hash))
  (define palette (make-hash))
  (for ([(k v) (in-hash results)])
    (cond
      [(and (pair? k) (eq? (car k) 'decrqm-private) v) (hash-set! private-modes (cdr k) v)]
      [(and (pair? k) (eq? (car k) 'decrqm-ansi) v)    (hash-set! ansi-modes (cdr k) v)]
      [(and (pair? k) (eq? (car k) 'osc) v)            (hash-set! osc (cdr k) v)]
      [(and (pair? k) (eq? (car k) 'palette) v)        (hash-set! palette (cdr k) v)]
      [else (void)]))

  ;; 身份：XTVERSION > XTGETTCAP(TN) > DA2
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
        (and (pair? da2) (= (car (car da2)) 84))
        #f))

  (terminal-caps id id-source nm ver tmux?
                 da1 da2 da3 xtv tcaps xtgettcap?
                 (get 'kitty-flags #f)
                 (and (get 'kitty-graphics #f) #t)
                 (get 'xtmodkeys #f)
                 (get 'cursor #f)
                 (get 'text-size #f) (get 'pixel-size #f) (get 'cell-size #f)
                 private-modes ansi-modes osc palette raw))

;; ════════════════════════════════════════════════════════════════
;; 便捷入口：跑默认表 → 组装
;; ════════════════════════════════════════════════════════════════

(define (probe-terminal
         #:profile [profile default-profile]
         #:groups [groups #f]
         #:private-modes [extra-private '()]
         #:ansi-modes [extra-ansi '()]
         #:xtgettcap-names [xtgettcap-names default-xtgettcap-names]
         #:palette-indices [palette-indices default-palette-indices]
         #:kitty-graphics? [kitty-graphics? #f]
         #:timeout [timeout 0.30]
         #:idle [idle 0.05])
  (define gs (or groups (profile-groups profile)))
  ;; 额外指定的模式先去重（避免与组内模式撞 id）
  (define extra-private* (remove-duplicates (remove* (group-private-modes gs) extra-private)))
  (define extra-ansi*    (remove-duplicates (remove* (group-ansi-modes gs)    extra-ansi)))
  (define specs
    (append (group->specs gs
                          #:xtgettcap-names xtgettcap-names
                          #:palette-indices palette-indices
                          #:kitty-graphics? kitty-graphics?)
            (for/list ([m (in-list extra-private*)]) (decrqm-private-spec m))
            (for/list ([m (in-list extra-ansi*)])    (decrqm-ansi-spec m))))
  (define-values (raw results) (run-specs/raw specs #:timeout timeout #:idle idle))
  (assemble-caps results raw))

;; ════════════════════════════════════════════════════════════════
;; 能力表访问（纯查表）
;; ════════════════════════════════════════════════════════════════

(define (caps-mode-pm caps mode [ansi? #f])
  (hash-ref (if ansi? (terminal-caps-ansi-modes caps)
                (terminal-caps-private-modes caps))
            mode #f))

(define (caps-mode-state caps mode [ansi? #f])
  (define pm (caps-mode-pm caps mode ansi?))
  (and pm (pm->state pm)))

(define (caps-mode-recognized? caps mode [ansi? #f])
  (define pm (caps-mode-pm caps mode ansi?))
  (and pm (not (eqv? pm 0))))

(define (caps-mode-on? caps mode [ansi? #f])
  (and (memv (caps-mode-pm caps mode ansi?) '(1 3)) #t))

(define (caps-mode-settable? caps mode [ansi? #f])
  (and (memv (caps-mode-pm caps mode ansi?) '(1 2)) #t))

(define (caps-mode-available? caps mode [ansi? #f])
  (and (memv (caps-mode-pm caps mode ansi?) '(1 2 3)) #t))

(define (caps-mode-supported? caps mode [ansi? #f])
  (caps-mode-available? caps mode ansi?))

(define (caps-mode-name mode [ansi? #f])
  (cond [(assoc mode (if ansi? ansi-mode-names dec-private-mode-names)) => cdr]
        [else #f]))

(define (caps-da1-codes caps)
  (if (pair? (terminal-caps-da1 caps)) (car (terminal-caps-da1 caps)) '()))

(define (caps-da1-model caps)
  (define cs (caps-da1-codes caps))
  (and (pair? cs) (da1-model-name (car cs))))

(define (caps-da1-features caps)
  (define cs (caps-da1-codes caps))
  (define feats (if (and (pair? cs) (da1-model-name (car cs))) (cdr cs) cs))
  (for/list ([c (in-list feats)]) (or (da1-feature-name c) (format "code ~a" c))))

(define (caps-da2-model caps)
  (define d (terminal-caps-da2 caps))
  (and (pair? d) (pair? (car d)) (da2-model-name (car (car d)))))

(define (caps-color caps code) (hash-ref (terminal-caps-osc caps) code #f))
(define (caps-palette-color caps i) (hash-ref (terminal-caps-palette caps) i #f))

(define (caps-osc-rgb? caps)
  (for/or ([v (in-list (append (hash-values (terminal-caps-osc caps))
                               (hash-values (terminal-caps-palette caps))))])
    (and (string? v) (regexp-match? #px"^rgb:" v))))

(define (caps-truecolor caps)
  (cond
    [(not (terminal-caps-xtgettcap? caps)) 'unknown]
    [(or (hash-has-key? (terminal-caps-xtgettcap caps) "RGB")
         (hash-has-key? (terminal-caps-xtgettcap caps) "Tc")) #t]
    [else #f]))

(define (caps-truecolor? caps) (eq? (caps-truecolor caps) #t))

(define (caps-colors-count caps)
  (define tc (terminal-caps-xtgettcap caps))
  (define v (or (hash-ref tc "Co" #f) (hash-ref tc "colors" #f)))
  (and (string? v) (string->number v)))
