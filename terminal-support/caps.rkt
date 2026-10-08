#lang racket

;; ════════════════════════════════════════════════════════════════
;; terminal-support/caps.rkt —— 能力表：组装 + 访问
;;
;; `assemble-caps` 只把"按表查询"得到的结果表打包成 caps（纯数据，不做决策）；
;; `probe-terminal` 是 default-queries 的便捷封装。
;; 访问/谓词部分只做查表与解释，同样不决定启用任何功能。
;; ════════════════════════════════════════════════════════════════

(require racket/string
         racket/list
         "query.rkt"
         "catalog.rkt"
         "run.rkt"
         "modes.rkt"
         "device-attrs.rkt"
         "groups.rkt")

(provide (struct-out caps)
         assemble-caps probe-terminal caps->hash
         caps-mode-pm caps-mode-state caps-mode-supported?
         caps-mode-recognized? caps-mode-on? caps-mode-settable? caps-mode-available?
         caps-mode-name
         caps-da1-model caps-da1-attrs caps-da2-model
         caps-color caps-palette-color caps-colors-count
         caps-color-rgb caps-palette-color-rgb
         caps-osc-rgb? caps-truecolor caps-truecolor? caps-color-level)

;; ════════════════════════════════════════════════════════════════
;; 能力表（纯数据）
;; ════════════════════════════════════════════════════════════════

(struct caps
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
   colorterm term             ; string / #f —— 环境提示快照（COLORTERM / TERM）
   raw)          ; bytes
  #:transparent)

;; ════════════════════════════════════════════════════════════════
;; 组装（纯函数：结果表 + 原始回复 → caps）
;; ════════════════════════════════════════════════════════════════

(define (assemble-caps results raw
                       #:colorterm [colorterm #f]
                       #:term [term #f])
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
        (and (pair? da2) (= (car (car da2)) 84))   ; notcurses: tmux 用 84
        #f))

  (caps id id-source nm ver tmux?
        da1 da2 da3 xtv tcaps xtgettcap?
        (get 'kitty-flags #f)
        (and (get 'kitty-graphics #f) #t)
        (get 'xtmodkeys #f)
        (get 'cursor #f)
        (get 'text-size #f) (get 'pixel-size #f) (get 'cell-size #f)
        private-modes ansi-modes osc palette
        colorterm term
        raw))

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
         #:colorterm [colorterm (getenv "COLORTERM")]
         #:term [term (getenv "TERM")]
         #:timeout [timeout 0.30]
         #:idle [idle 0.05])
  (define gs (or groups (profile-groups profile)))
  ;; 额外指定的模式先去重（避免与组内模式撞 id）
  (define extra-private* (remove-duplicates (remove* (group-private-modes gs) extra-private)))
  (define extra-ansi*    (remove-duplicates (remove* (group-ansi-modes gs)    extra-ansi)))
  (define queries
    (append (group->queries gs
                            #:xtgettcap-names xtgettcap-names
                            #:palette-indices palette-indices
                            #:kitty-graphics? kitty-graphics?)
            (for/list ([m (in-list extra-private*)]) (decrqm-private-query m))
            (for/list ([m (in-list extra-ansi*)])    (decrqm-ansi-query m))))
  (define-values (raw results) (run-queries/raw queries #:timeout timeout #:idle idle))
  (assemble-caps results raw #:colorterm colorterm #:term term))

;; ════════════════════════════════════════════════════════════════
;; 访问 / 谓词（纯查表）
;; ════════════════════════════════════════════════════════════════

;; Pm 值 → 原始状态符号（不合并，保留语义）
(define (pm->state pm)
  (case pm
    [(1) 'set] [(2) 'reset]
    [(3) 'permanently-set] [(4) 'permanently-reset]
    [(0) 'unrecognized] [else 'unknown]))

(define (caps-mode-pm caps mode [ansi? #f])
  (hash-ref (if ansi? (caps-ansi-modes caps) (caps-private-modes caps)) mode #f))

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
  (if (pair? (caps-da1 caps)) (car (caps-da1 caps)) '()))

(define (caps-da1-model caps)
  (define cs (caps-da1-codes caps))
  (and (pair? cs) (da1-model-name (car cs))))

(define (caps-da1-attrs caps)
  (define cs (caps-da1-codes caps))
  ;; 仅当首位是 VT2xx+ 型号码(>=60)时，其后才是能力码；
  ;; VT100 系的 "?1;2"(VT100+AVO) 等，其余参数是 ID 的一部分，不是能力码。
  (define attrs (if (and (pair? cs) (>= (car cs) 60)) (cdr cs) '()))
  (for/list ([c (in-list attrs)]) (or (da1-attr-name c) (format "code ~a" c))))

(define (caps-da2-model caps)
  (define d (caps-da2 caps))
  (and (pair? d) (pair? (car d)) (da2-model-name (car (car d)))))

(define (caps-color caps code) (hash-ref (caps-osc caps) code #f))
(define (caps-palette-color caps i) (hash-ref (caps-palette caps) i #f))

;; OSC 颜色值（"rgb:rrrr/gggg/bbbb" 或 "#rrggbb"）→ (list r g b)，分量 0-255；不可解析则 #f。
;; 这样外部拿到颜色不需要自己拆字符串。
(define (hex-comp->byte h)
  (define n (string->number h 16))
  (case (string-length h)
    [(1) (* n 17)]
    [(2) n]
    [(3) (quotient n 16)]
    [(4) (quotient n 256)]
    [else (quotient (* n 255) (sub1 (expt 16 (string-length h))))]))

(define (parse-color-string s)
  (cond
    [(regexp-match #px"^rgb:([0-9A-Fa-f]+)/([0-9A-Fa-f]+)/([0-9A-Fa-f]+)$" s)
     => (λ (m) (list (hex-comp->byte (cadr m))
                     (hex-comp->byte (caddr m))
                     (hex-comp->byte (cadddr m))))]
    [(regexp-match #px"^#([0-9A-Fa-f]{6})$" s)
     => (λ (m) (define h (cadr m))
          (list (string->number (substring h 0 2) 16)
                (string->number (substring h 2 4) 16)
                (string->number (substring h 4 6) 16)))]
    [else #f]))

(define (caps-color-rgb caps code)
  (define s (caps-color caps code))
  (and s (parse-color-string s)))

(define (caps-palette-color-rgb caps i)
  (define s (caps-palette-color caps i))
  (and s (parse-color-string s)))

(define (caps-osc-rgb? caps)
  (for/or ([v (in-list (append (hash-values (caps-osc caps))
                               (hash-values (caps-palette caps))))])
    (and (string? v) (regexp-match? #px"^rgb:" v))))

(define (caps-truecolor caps)
  (cond
    [(not (caps-xtgettcap? caps)) 'unknown]
    [(or (hash-has-key? (caps-xtgettcap caps) "RGB")
         (hash-has-key? (caps-xtgettcap caps) "Tc")) #t]
    [else #f]))

(define (caps-truecolor? caps) (eq? (caps-truecolor caps) #t))

;; 色深判定：把混乱的多个来源揉成一个确定符号。
;;   'truecolor | '256 | '16 | 'unknown
;; 优先级：XTGETTCAP RGB/Tc > COLORTERM > XTGETTCAP Co > COLORTERM(其他值) > TERM > DA1 ANSI color
(define (caps-color-level caps)
  (define tc (caps-xtgettcap caps))
  (define co (or (caps-colors-count caps) 0))
  (define ct (caps-colorterm caps))
  (define term (caps-term caps))
  (define (term-match? rx) (and term (regexp-match? rx (string-downcase term))))
  (cond
    [(or (hash-has-key? tc "RGB") (hash-has-key? tc "Tc")) 'truecolor]
    [(and ct (member ct '("truecolor" "24bit"))) 'truecolor]
    [(>= co 16777216) 'truecolor]
    [(>= co 256) '256]
    [(and ct (positive? (string-length ct))) '256]   ; COLORTERM 有值但不认识
    [(term-match? #rx"256color") '256]
    [(term-match? #rx"truecolor|direct") 'truecolor]
    [(member "ANSI color" (caps-da1-attrs caps)) '16]
    [else 'unknown]))

(define (caps-colors-count caps)
  (define tc (caps-xtgettcap caps))
  (define v (or (hash-ref tc "Co" #f) (hash-ref tc "colors" #f)))
  (and (string? v) (string->number v)))

;; ════════════════════════════════════════════════════════════════
;; 检查 / 序列化（供测试、快照、日志）
;; ════════════════════════════════════════════════════════════════

;; 把 caps 摊平成可比较/可序列化的 hash（不含 raw）。
(define (caps->hash c)
  (hash 'id            (caps-id c)
        'id-source     (caps-id-source c)
        'name          (caps-name c)
        'version       (caps-version c)
        'tmux?         (caps-tmux? c)
        'xtversion     (caps-xtversion c)
        'xtgettcap?    (caps-xtgettcap? c)
        'xtgettcap     (caps-xtgettcap c)
        'kitty-flags   (caps-kitty-flags c)
        'xtmodkeys     (caps-xtmodkeys c)
        'text-size     (caps-text-size c)
        'pixel-size    (caps-pixel-size c)
        'cell-size     (caps-cell-size c)
        'cursor        (caps-cursor c)
        'private-modes (caps-private-modes c)
        'ansi-modes    (caps-ansi-modes c)
        'osc           (caps-osc c)
        'palette       (caps-palette c)
        'color-level   (caps-color-level c)
        'colorterm     (caps-colorterm c)
        'term          (caps-term c)))
