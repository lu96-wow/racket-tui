#lang racket

;; ════════════════════════════════════════════════════════════════
;; 帧历史 + 帧间 diff —— 让调试循环「只在前后不一致时输出新内容」，
;; 同时不丢信息：每帧存的是整块 grid 的深拷贝，颜色/属性/光标可事后按需查询。
;;
;; 设计取向（以 AI 用起来顺手为准）：
;;   · 默认不打印任何东西；历史只留在内存里，需要时再取 → 不会刷屏
;;   · 帧边界是 flush!（见 io/output.rkt），去重后的帧才入历史
;;   · diff 只列发生变化的行，长帧里改一个数字也只出 2 行
;;
;;   (char-history)          ; 各帧纯文本（旧→新）
;;   (char-frame-at i)       ; 第 i 帧文本（i: 0=最旧）
;;   (char-history-ref i)    ; 第 i 帧的 grid 快照 → 再喂给 screen-styled-cells 等
;;   (char-diff)             ; 最近两帧的差异（无变化/帧不足返回 ""）
;;   (frame-diff a b)        ; 任意两帧文本的差异
;; ════════════════════════════════════════════════════════════════

(require "grid.rkt"
         "render.rkt")

(provide current-frame-history-size
         history-push! history-clear!
         char-history char-history-count char-history-ref
         char-history-frames char-frame-at
         frame-diff style-diff grid-diff char-diff char-style-diff)

;; 保留最近多少帧；0 = 关闭历史（不占内存）
(define current-frame-history-size (make-parameter 32))

;; 记录 = (vector index grid text)，列表按新→旧存
(define history (box '()))
(define next-index (box 0))

(define (history-push! g)
  (define size (current-frame-history-size))
  (when (and size (> size 0))
    (define rec (vector (unbox next-index) (grid-copy g) (grid->text g)))
    (set-box! next-index (add1 (unbox next-index)))
    (define new (cons rec (unbox history)))
    (set-box! history (if (> (length new) size) (take new size) new))))

(define (history-clear!)
  (set-box! history '())
  (set-box! next-index 0))

(define (ordered-history) (reverse (unbox history)))

(define (char-history) (map (λ (r) (vector-ref r 2)) (ordered-history)))
(define (char-history-count) (length (unbox history)))
(define (char-history-frames) (char-history))

;; i: 0 = 最旧；返回 grid 快照或 #f
(define (char-history-ref i)
  (define lst (ordered-history))
  (and (exact-integer? i) (<= 0 i) (< i (length lst))
       (vector-ref (list-ref lst i) 1)))

(define (char-frame-at i #:trim-right? [trim? #t])
  (define g (char-history-ref i))
  (and g (grid->text g #:trim-right? trim?)))

;; ── 帧间 diff ────────────────────────────────────────────
;; 输出统一 diff 风格，仅列变化的行：
;;   @@ row 2 @@
;;   -count = 41
;;   +count = 42
;; 连续变化的行合并到一个 hunk。

(define (consecutive-runs is)
  (if (null? is)
      '()
      (let loop ([prev (car is)] [run (list (car is))] [rest (cdr is)] [out '()])
        (cond
          [(null? rest) (reverse (cons (reverse run) out))]
          [(= (car rest) (add1 prev)) (loop (car rest) (cons (car rest) run) (cdr rest) out)]
          [else (loop (car rest) (list (car rest)) (cdr rest) (cons (reverse run) out))]))))

(define (frame-diff a b)
  (define la (string-split a "\n"))
  (define lb (string-split b "\n"))
  (define n (max (length la) (length lb)))
  (define (at lst i) (if (< i (length lst)) (list-ref lst i) ""))
  (define changed
    (for/list ([i (in-range n)] #:when (not (equal? (at la i) (at lb i)))) i))
  (cond
    [(null? changed) ""]
    [else
     (string-join
      (for/list ([run (in-list (consecutive-runs changed))])
        (define lo (car run))
        (define hi (last run))
        (define header
          (if (= lo hi)
              (format "@@ row ~a @@\n" lo)
              (format "@@ rows ~a..~a @@\n" lo hi)))
        (define body
          (string-join
           (for/list ([i (in-list run)])
             (string-append (format "-~a\n" (at la i))
                            (format "+~a\n" (at lb i))))
           ""))
        (string-append header body))
      "")]))

;; 最近两帧的 diff；历史不足或没变化 → ""
(define (char-diff #:styles? [styles? #f])
  (define h (unbox history))          ; 新→旧
  (cond
    [(>= (length h) 2)
     (define cur  (vector-ref (car h) 1))
     (define prev (vector-ref (cadr h) 1))
     (if styles?
         (grid-diff prev cur)
         (frame-diff (vector-ref (cadr h) 2) (vector-ref (car h) 2)))]
    [else ""]))

;; 最近两帧的样式（颜色/属性）差异
(define (char-style-diff)
  (define h (unbox history))
  (if (>= (length h) 2)
      (style-diff (vector-ref (cadr h) 1) (vector-ref (car h) 1))
      ""))

;; ── 样式 diff ────────────────────────────────────────────
;; 只列发生颜色/属性变化的列区间（把连续同 old/new 的格并成一段）：
;;   @@ row 2 style @@
;;     cols 3..5  fg#9 -> fg#46
(define (style-diff a b)
  (define rows (min (grid-rows a) (grid-rows b)))
  (define cols (min (grid-cols a) (grid-cols b)))
  (define (s g r c) (style->string (grid-ref g r c)))
  (define blocks '())
  (for ([r (in-range rows)])
    (define row-lines '())
    (define (emit! c0 c1 old new)
      (set! row-lines
            (cons (format "  ~a  ~a -> ~a"
                          (if (= c0 c1) (format "col ~a" c0) (format "cols ~a..~a" c0 c1))
                          (if (string=? old "") "<default>" old)
                          (if (string=? new "") "<default>" new))
                  row-lines)))
    (let loop ([c 0])
      (cond
        [(>= c cols) (void)]
        [(equal? (s a r c) (s b r c)) (loop (add1 c))]
        [else
         (define old (s a r c))
         (define new (s b r c))
         (define c0 c)
         (let extend ([c (add1 c)])
           (if (and (< c cols)
                    (not (equal? (s a r c) (s b r c)))
                    (equal? (s a r c) old)
                    (equal? (s b r c) new))
               (extend (add1 c))
               (begin (emit! c0 (sub1 c) old new) (loop c))))]))
    (when (pair? row-lines)
      (set! blocks (cons (format "@@ row ~a style @@\n~a\n" r
                                (string-join (reverse row-lines) "\n"))
                         blocks))))
  (string-join (reverse blocks) ""))

;; 文本 + 样式合并（日志默认用这个，颜色变化不会被静默丢掉）
(define (grid-diff a b)
  (string-append (frame-diff (grid->text a) (grid->text b))
                 (style-diff a b)))
