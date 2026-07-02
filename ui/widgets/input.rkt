#lang racket

(require "../component.rkt"
         "../../base/io/build-input.rkt"
         "../../base/io/output-styles.rkt"
         "../../base/io/output-color.rkt"
         "../../base/io/output.rkt")

(provide make-input)

;; ═══════════════════════════════════════════════════════════
;; 借鉴 racket/gui text% 的核心设计:
;;   1. 绝对位置模型 — cursor/selection 是 0..len 的偏移
;;   2. Gap Buffer — 插入删除 O(1)，移动光标 O(move-distance)
;;   3. 显示宽度并行数组 — CJK/emoji 宽度缓存
;;
;; 相比 racket/gui 的简化:
;;   - 不用红黑树行索引（TUI 文本短，O(n) 扫描够用）
;;   - 不用 snip 链（直接用 gap buffer 字符数组）
;; ═══════════════════════════════════════════════════════════

;; ── 字符显示宽度 ─────────────────────────────────────────
(define (char-display-width ch)
  (define cp (char->integer ch))
  (cond [(<= #x1100 cp #x115F) 2] [(<= #x2329 cp #x232A) 2]
        [(<= #x2E80 cp #x303E) 2] [(<= #x3040 cp #x33BF) 2]
        [(<= #x3400 cp #x4DBF) 2] [(<= #x4E00 cp #x9FFF) 2]
        [(<= #xA000 cp #xA4CF) 2] [(<= #xAC00 cp #xD7AF) 2]
        [(<= #xF900 cp #xFAFF) 2] [(<= #xFE10 cp #xFE19) 2]
        [(<= #xFE30 cp #xFE6F) 2] [(<= #xFF01 cp #xFF60) 2]
        [(<= #xFFE0 cp #xFFE6) 2]
        [(<= #x1F300 cp #x1F5FF) 2] [(<= #x1F600 cp #x1F64F) 2]
        [(<= #x1F680 cp #x1F6FF) 2] [(<= #x1F900 cp #x1F9FF) 2]
        [(<= #x20000 cp #x2FFFF) 2] [(<= #x30000 cp #x3FFFF) 2]
        [else 1]))

;; ── Gap Buffer ───────────────────────────────────────────
;; 布局:
;;   [有效字符...][gap-未使用空间][有效字符...]
;;   0         gap-start       gap-end    capacity
;;
;;   cursor = gap-start
;;   total-len = 有效字符总数 (不含 gap 内垃圾)
(struct gap-buf (chars widths gap-start gap-end total-len capacity)
  #:mutable)

(define INIT-CAP 256)

(define (make-gap-buf)
  (gap-buf (make-vector INIT-CAP #\nul)
           (make-vector INIT-CAP 0)
           0 INIT-CAP 0 INIT-CAP))

;; gap 大小
(define (gb-gap-size gb)
  (- (gap-buf-gap-end gb) (gap-buf-gap-start gb)))

;; 确保 gap 至少 need 个槽位
(define (gb-ensure-gap! gb need)
  (when (< (gb-gap-size gb) need)
    (define old-cap (gap-buf-capacity gb))
    (define new-cap (* 2 (+ old-cap need)))
    (define new-chars (make-vector new-cap #\nul))
    (define new-widths (make-vector new-cap 0))
    (define gs (gap-buf-gap-start gb))
    (define ge (gap-buf-gap-end gb))
    ;; 复制左半 [0, gs)
    (vector-copy! new-chars  0 (gap-buf-chars gb)  0 gs)
    (vector-copy! new-widths 0 (gap-buf-widths gb) 0 gs)
    ;; 复制右半 [ge, old-cap) → [gs+need, ...)
    (define right-len (- old-cap ge))
    (vector-copy! new-chars  (+ gs need) (gap-buf-chars gb)  ge old-cap)
    (vector-copy! new-widths (+ gs need) (gap-buf-widths gb) ge old-cap)
    ;; 更新
    (set-gap-buf-chars!  gb new-chars)
    (set-gap-buf-widths! gb new-widths)
    (set-gap-buf-gap-end!   gb (+ gs need))
    (set-gap-buf-capacity!  gb new-cap)))

;; 移动光标 → 移动 gap
(define (gb-move-gap! gb pos)
  (define gs (gap-buf-gap-start gb))
  (define ge (gap-buf-gap-end gb))
  (define cs (gap-buf-chars gb))
  (define ws (gap-buf-widths gb))
  (cond [(= pos gs) (void)]
        [(< pos gs)
         (define n (- gs pos))
         (vector-copy! cs (- ge n) cs pos gs)
         (vector-copy! ws (- ge n) ws pos gs)
         (set-gap-buf-gap-start! gb pos)
         (set-gap-buf-gap-end!   gb (- ge n))]
        [else
         (define n (- pos gs))
         (vector-copy! cs gs cs ge (+ ge n))
         (vector-copy! ws gs ws ge (+ ge n))
         (set-gap-buf-gap-start! gb (+ gs n))
         (set-gap-buf-gap-end!   gb (+ ge n))]))

;; 在 cursor 处插入字符
(define (gb-insert! gb ch w)
  (gb-ensure-gap! gb 1)
  (define gs (gap-buf-gap-start gb))
  (vector-set! (gap-buf-chars gb)  gs ch)
  (vector-set! (gap-buf-widths gb) gs w)
  (set-gap-buf-gap-start!  gb (add1 gs))
  (set-gap-buf-total-len!  gb (add1 (gap-buf-total-len gb))))

;; backspace: 删光标左边
(define (gb-backspace! gb)
  (when (> (gap-buf-gap-start gb) 0)
    (set-gap-buf-gap-end!   gb (sub1 (gap-buf-gap-end gb)))
    (set-gap-buf-gap-start! gb (sub1 (gap-buf-gap-start gb)))
    (set-gap-buf-total-len! gb (sub1 (gap-buf-total-len gb)))))

;; delete: 删光标右边
(define (gb-delete! gb)
  (when (< (gap-buf-gap-start gb) (gap-buf-total-len gb))
    (set-gap-buf-gap-end!   gb (add1 (gap-buf-gap-end gb)))
    (set-gap-buf-total-len! gb (sub1 (gap-buf-total-len gb)))))

;; 逻辑位置 → 物理索引 (跳过 gap)
(define (gb-logic->phys gb pos)
  (if (< pos (gap-buf-gap-start gb))
      pos
      (+ pos (- (gap-buf-gap-end gb) (gap-buf-gap-start gb)))))

(define (gb-ref gb pos)
  (vector-ref (gap-buf-chars gb) (gb-logic->phys gb pos)))

(define (gb-width-ref gb pos)
  (vector-ref (gap-buf-widths gb) (gb-logic->phys gb pos)))

;; gap-buffer → string
(define (gb->string gb)
  (define cs (gap-buf-chars gb))
  (define gs (gap-buf-gap-start gb))
  (define ge (gap-buf-gap-end gb))
  (define tl (gap-buf-total-len gb))
  (string-append
   (list->string (for/list ([i (in-range gs)]) (vector-ref cs i)))
   (list->string (for/list ([i (in-range ge (+ ge (- tl gs)))]) (vector-ref cs i)))))

;; ── 行索引 ────────────────────────────────────────────────
;; 扫描换行符，返回行起始位置列表
(define (compute-lines gb)
  (define tl (gap-buf-total-len gb))
  (let loop ([pos 0] [start 0] [acc '()])
    (cond [(>= pos tl) (reverse (cons start acc))]
          [(char=? (gb-ref gb pos) #\newline)
           (loop (add1 pos) (add1 pos) (cons start acc))]
          [else (loop (add1 pos) start acc)])))

;; pos → (values line-index col-in-line)
(define (pos->line+col lines pos)
  (define n (length lines))
  (let loop ([li 0])
    (if (>= li (sub1 n))
        (values li (- pos (list-ref lines li)))
        (if (< pos (list-ref lines (add1 li)))
            (values li (- pos (list-ref lines li)))
            (loop (add1 li))))))

;; ═══════════════════════════════════════════════════════════
;; make-input
;; ═══════════════════════════════════════════════════════════
(define (make-input #:placeholder [placeholder ""]
                    #:on-submit   [on-submit void]
                    #:on-change   [on-change void]
                    #:multiline?  [multiline? #f])
  ;; ── 状态 ──
  (define gb           (box (make-gap-buf)))
  (define lines        (box '(0)))
  (define lines-dirty? (box #t))
  (define dirty        (box #t))
  (define scroll-y     (box 0))
  (define pos-x (box 0))
  (define pos-y (box 0))
  (define pos-w (box 0))
  (define pos-h (box 0))

  ;; ── 行缓存 ──
  (define (get-lines)
    (when (unbox lines-dirty?)
      (set-box! lines (compute-lines (unbox gb)))
      (set-box! lines-dirty? #f))
    (unbox lines))

  (define (mark-lines-dirty!)
    (set-box! lines-dirty? #t))

  (define (text-string) (gb->string (unbox gb)))
  (define (cursor-pos)  (gap-buf-gap-start (unbox gb)))

  ;; ── 滚动 ──
  (define (ensure-cursor-visible!)
    (define ls  (get-lines))
    (define ci  (cursor-pos))
    (define-values (li _) (pos->line+col ls ci))
    (define h   (unbox pos-h))
    (define scr (unbox scroll-y))
    (cond [(< li scr)          (set-box! scroll-y li)]
          [(>= li (+ scr h))   (set-box! scroll-y (add1 (- li h)))]
          [else                (void)]))

  ;; ── 鼠标→光标 ──
  (define (mouse->cursor mx my)
    (define ls  (get-lines))
    (define scr (unbox scroll-y))
    (define li  (+ scr (- my (unbox pos-y))))
    (define n   (length ls))
    (define b   (unbox gb))
    (define new-pos
      (cond [(< li 0)  0]
            [(>= li n) (gap-buf-total-len b)]
            [else
             (define line-start (list-ref ls li))
             (define line-end   (if (< (add1 li) n)
                                    (list-ref ls (add1 li))
                                    (gap-buf-total-len b)))
             (define rel-x (- mx (unbox pos-x)))
             (let loop ([pos line-start] [col-w 0])
               (cond [(>= pos line-end) pos]
                     [(>= col-w rel-x) pos]
                     [else (loop (add1 pos) (+ col-w (gb-width-ref b pos)))]))]))
    (when (not (= new-pos (cursor-pos)))
      (gb-move-gap! b new-pos)
      (set-box! dirty #t)))

  ;; ── 编辑操作 ──
  (define (do-insert str)
    (define b (unbox gb))
    (for ([ch (in-string str)])
      (unless (and (not multiline?) (char=? ch #\newline))
        (gb-insert! b ch (char-display-width ch))))
    (set-box! gb b)
    (mark-lines-dirty!)
    (set-box! dirty #t)
    (ensure-cursor-visible!)
    (on-change (text-string)))

  (define (do-backspace)
    (define b (unbox gb))
    (when (> (cursor-pos) 0)
      (gb-backspace! b)
      (set-box! gb b)
      (mark-lines-dirty!)
      (set-box! dirty #t)
      (ensure-cursor-visible!)
      (on-change (text-string))))

  (define (do-delete)
    (define b (unbox gb))
    (when (< (cursor-pos) (gap-buf-total-len b))
      (gb-delete! b)
      (set-box! gb b)
      (mark-lines-dirty!)
      (set-box! dirty #t)
      (on-change (text-string))))

  (define (do-move-left)
    (when (> (cursor-pos) 0)
      (define b (unbox gb))
      (gb-move-gap! b (sub1 (cursor-pos)))
      (set-box! gb b)
      (set-box! dirty #t)
      (ensure-cursor-visible!)))

  (define (do-move-right)
    (define b (unbox gb))
    (when (< (cursor-pos) (gap-buf-total-len b))
      (gb-move-gap! b (add1 (cursor-pos)))
      (set-box! gb b)
      (set-box! dirty #t)
      (ensure-cursor-visible!)))

  (define (do-move-up)
    (define b  (unbox gb))
    (define ls (get-lines))
    (define ci (cursor-pos))
    (define-values (li col) (pos->line+col ls ci))
    (when (> li 0)
      (define pstart (list-ref ls (sub1 li)))
      (define pend   (list-ref ls li))
      (define plen   (- pend pstart))
      (gb-move-gap! b (+ pstart (min col (max 0 (sub1 plen)))))
      (set-box! gb b)
      (set-box! dirty #t)
      (ensure-cursor-visible!)))

  (define (do-move-down)
    (define b  (unbox gb))
    (define ls (get-lines))
    (define ci (cursor-pos))
    (define-values (li col) (pos->line+col ls ci))
    (define n  (length ls))
    (when (< (add1 li) n)
      (define pstart (list-ref ls (add1 li)))
      (define pend   (if (< (+ li 2) n) (list-ref ls (+ li 2)) (gap-buf-total-len b)))
      (define plen   (- pend pstart))
      (gb-move-gap! b (+ pstart (min col (max 0 (sub1 plen)))))
      (set-box! gb b)
      (set-box! dirty #t)
      (ensure-cursor-visible!)))

  (define (do-move-home)
    (define b  (unbox gb))
    (define ls (get-lines))
    (define ci (cursor-pos))
    (define-values (li _) (pos->line+col ls ci))
    (define pstart (list-ref ls li))
    (when (not (= ci pstart))
      (gb-move-gap! b pstart)
      (set-box! gb b)
      (set-box! dirty #t)))

  (define (do-move-end)
    (define b  (unbox gb))
    (define ls (get-lines))
    (define ci (cursor-pos))
    (define-values (li _) (pos->line+col ls ci))
    (define n (length ls))
    (define pend (if (< (add1 li) n)
                     (sub1 (list-ref ls (add1 li)))
                     (gap-buf-total-len b)))
    (when (not (= ci pend))
      (gb-move-gap! b pend)
      (set-box! gb b)
      (set-box! dirty #t)))

  ;; ── render ──
  (define (render focused? x y w h)
    (set-box! pos-x x)
    (set-box! pos-y y)
    (set-box! pos-w w)
    (set-box! pos-h h)
    ;; 清区域
    (for ([i (in-range h)])
      (cursor-move (+ y i) x)
      (put-string (make-string w #\space)))
    (define b  (unbox gb))
    (define ls (get-lines))
    (define ci (cursor-pos))
    (define tl (gap-buf-total-len b))
    (define-values (cur-li cur-col) (pos->line+col ls ci))
    (define scr (unbox scroll-y))
    (cond
      ;; 空 + 无焦点 → placeholder
      [(and (zero? tl) (not focused?))
       (when (positive? (string-length placeholder))
         (put-styled-at! y x 'input-normal
                         (if (> (string-length placeholder) w)
                             (substring placeholder 0 w)
                             placeholder)))]
      [else
       (for ([screen-row (in-range h)])
         (define li (+ scr screen-row))
         (when (< li (length ls))
           (define line-start (list-ref ls li))
           (define line-end   (if (< (add1 li) (length ls))
                                  (max line-start (sub1 (list-ref ls (add1 li))))
                                  tl))
           (define line-len (- line-end line-start))

           ;; ── 视口 [hscroll, hscroll+w) 在 buffer 上的浮动窗口 ──
           (define total-w
             (for/sum ([p (in-range line-start line-end)]) (gb-width-ref b p)))

           ;; 计算水平滚动偏移：确保光标在窗口内
           (define hscroll
             (cond
               [(not (= li cur-li)) 0]
               [(<= total-w w) 0]
               [else
                (define cursor-col-x (for/sum ([p (in-range line-start ci)])
                                       (gb-width-ref b p)))
                (define cursor-w (if (and (< ci tl)
                                          (not (char=? (gb-ref b ci) #\newline)))
                                     (gb-width-ref b ci)
                                     1))
                (cond [(< cursor-col-x (quotient w 2)) 0]
                      [(> (+ cursor-col-x cursor-w) (- total-w (quotient w 2)))
                       (max 0 (- total-w w))]
                      [else (- cursor-col-x (quotient w 2))])]))

           ;; ── 逐字符渲染：完全在窗口内的才画 ──
           ;; 窗口 = 屏幕列 [0, w) ← 映射到 buffer 显示列 [hscroll, hscroll+w)
           (define style (if focused? 'input-focus 'input-normal))
           (let loop ([p line-start] [col 0])
             (when (< p line-end)
               (define cw (gb-width-ref b p))
               (define char-right (+ col cw))
               (define screen-x (- col hscroll))
               (cond
                 ;; 字符完全在窗口左边 → 跳过
                 [(<= char-right hscroll)
                  (loop (add1 p) char-right)]
                 ;; 字符在窗口内（完全可见）
                 [(and (>= col hscroll) (<= char-right (+ hscroll w)))
                  (put-styled-at! (+ y screen-row) (+ x screen-x) style
                                  (if (char=? (gb-ref b p) #\newline) " " (string (gb-ref b p))))
                  (loop (add1 p) char-right)]
                 ;; 字符超出窗口右边或跨边界 → 不画
                 [else
                  (loop (add1 p) char-right)])))

           ;; ── 光标 ──
           (when (and focused? (= li cur-li))
             (define cursor-col-x (for/sum ([p (in-range line-start ci)])
                                    (gb-width-ref b p)))
             (define screen-x (- cursor-col-x hscroll))
             (when (and (>= screen-x 0) (< screen-x w))
               (define cch (if (and (< ci tl)
                                    (not (char=? (gb-ref b ci) #\newline)))
                               (string (gb-ref b ci))
                               " "))
               (put-styled-at! (+ y screen-row) (+ x screen-x) 'cursor cch)))))]))

  ;; ── handler ──
  (define handler
    (if multiline?
        (build-input
         #:char      (λ (ch) (when (<= 32 ch 126)
                                (do-insert (string (integer->char ch)))))
         #:utf-char   do-insert
         #:backspace  do-backspace
         #:delete     do-delete
         #:left       do-move-left
         #:right      do-move-right
         #:up         do-move-up
         #:down       do-move-down
         #:home       do-move-home
         #:end        do-move-end
         #:enter      (λ () (do-insert "\n"))
         #:escape     void
         #:paste       (λ (data) (do-insert (bytes->string/utf-8 data)))
         #:mouse-press (λ (btn mx my mods) (when (eq? btn 'left) (mouse->cursor mx my)))
         #:mouse-move  (λ (mx my mods)       (mouse->cursor mx my)))
        (build-input
         #:char      (λ (ch) (when (<= 32 ch 126)
                                (do-insert (string (integer->char ch)))))
         #:utf-char   do-insert
         #:backspace  do-backspace
         #:delete     do-delete
         #:left       do-move-left
         #:right      do-move-right
         #:home       do-move-home
         #:end        do-move-end
         #:enter      (λ () (on-submit (text-string)))
         #:escape     void
         #:paste       (λ (data) (do-insert (bytes->string/utf-8 data)))
         #:mouse-press (λ (btn mx my mods) (when (eq? btn 'left) (mouse->cursor mx my)))
         #:mouse-move  (λ (mx my mods)       (mouse->cursor mx my)))))

  ;; ── 构造 component ──
  (component render handler #t #t 0 1 dirty #f))
