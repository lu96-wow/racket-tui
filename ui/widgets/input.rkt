#lang racket

(require "../component.rkt"
         "../../base/io/build-input.rkt"
         "../../base/io/output-styles.rkt"
         "../../base/io/output-color.rkt"
         "../../base/io/output.rkt")

(provide make-input)

;; ═══════════════════════════════════════════════════════════
;; Gap Buffer: 借鉴 racket/gui text% 绝对位置模型
;; 布局: [left...][gap...][right...]  gap-start=cursor=有效字符数
;; ═══════════════════════════════════════════════════════════

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

(struct gap-buf (chars widths gap-start gap-end total-len capacity) #:mutable)

(define (make-gap-buf)
  (define cap 256)
  (gap-buf (make-vector cap #\nul) (make-vector cap 0) 0 cap 0 cap))

(define (gb-logic->phys gb pos)
  (if (< pos (gap-buf-gap-start gb))
      pos
      (+ pos (- (gap-buf-gap-end gb) (gap-buf-gap-start gb)))))

(define (gb-ref gb pos)      (vector-ref (gap-buf-chars gb)  (gb-logic->phys gb pos)))
(define (gb-width-ref gb pos)(vector-ref (gap-buf-widths gb) (gb-logic->phys gb pos)))

(define (gb-ensure-gap! gb need)
  (when (< (- (gap-buf-gap-end gb) (gap-buf-gap-start gb)) need)
    (define old-cap (gap-buf-capacity gb))
    (define new-cap (* 2 (+ old-cap need)))
    (define nc (make-vector new-cap #\nul))
    (define nw (make-vector new-cap 0))
    (define gs (gap-buf-gap-start gb))
    (define ge (gap-buf-gap-end gb))
    (vector-copy! nc 0  (gap-buf-chars gb)  0 gs)
    (vector-copy! nw 0  (gap-buf-widths gb) 0 gs)
    (vector-copy! nc (+ gs need) (gap-buf-chars gb)  ge old-cap)
    (vector-copy! nw (+ gs need) (gap-buf-widths gb) ge old-cap)
    (set-gap-buf-chars!  gb nc)
    (set-gap-buf-widths! gb nw)
    (set-gap-buf-gap-end!   gb (+ gs need))
    (set-gap-buf-capacity!  gb new-cap)))

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

(define (gb-insert! gb ch w)
  (gb-ensure-gap! gb 1)
  (define gs (gap-buf-gap-start gb))
  (vector-set! (gap-buf-chars gb)  gs ch)
  (vector-set! (gap-buf-widths gb) gs w)
  (set-gap-buf-gap-start! gb (add1 gs))
  (set-gap-buf-total-len! gb (add1 (gap-buf-total-len gb))))

(define (gb-backspace! gb)
  (when (> (gap-buf-gap-start gb) 0)
    (set-gap-buf-gap-end!   gb (sub1 (gap-buf-gap-end gb)))
    (set-gap-buf-gap-start! gb (sub1 (gap-buf-gap-start gb)))
    (set-gap-buf-total-len! gb (sub1 (gap-buf-total-len gb)))))

(define (gb-delete! gb)
  (when (< (gap-buf-gap-start gb) (gap-buf-total-len gb))
    (set-gap-buf-gap-end!   gb (add1 (gap-buf-gap-end gb)))
    (set-gap-buf-total-len! gb (sub1 (gap-buf-total-len gb)))))

(define (gb->string gb)
  (define cs (gap-buf-chars gb))
  (define gs (gap-buf-gap-start gb))
  (define ge (gap-buf-gap-end gb))
  (define tl (gap-buf-total-len gb))
  (string-append
   (list->string (for/list ([i (in-range gs)]) (vector-ref cs i)))
   (list->string (for/list ([i (in-range ge (+ ge (- tl gs)))]) (vector-ref cs i)))))

;; ═══════════════════════════════════════════════════════════
;; 行索引（按需扫描换行符）
;; ═══════════════════════════════════════════════════════════
(define (compute-lines gb)
  (define tl (gap-buf-total-len gb))
  (let loop ([pos 0] [start 0] [acc '()])
    (cond [(>= pos tl) (reverse (cons start acc))]
          [(char=? (gb-ref gb pos) #\newline)
           (loop (add1 pos) (add1 pos) (cons start acc))]
          [else (loop (add1 pos) start acc)])))

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
                    #:multiline?  [multiline? #f]
                    #:initial-text [initial-text ""])
  ;; ── buffer 状态 ──
  (define gb           (box (make-gap-buf)))
  (define lines-cache  (box '(0)))
  (define lines-valid? (box #f))
  (define dirty        (box #t))

  ;; ── 持久滚动状态（渲染时更新）──
  (define view-scroll-y (box 0))
  (define view-scroll-x (box 0))
  (define vp-x (box 0)) (define vp-y (box 0))
  (define vp-w (box 0)) (define vp-h (box 0))

  ;; 初始化文本
  (unless (equal? initial-text "")
    (define b (unbox gb))
    (for ([ch (in-string initial-text)])
      (gb-insert! b ch (char-display-width ch)))
    (set-box! gb b)
    (set-box! lines-valid? #f))

  ;; ── 行缓存 ──
  (define (get-lines)
    (unless (unbox lines-valid?)
      (set-box! lines-cache (compute-lines (unbox gb)))
      (set-box! lines-valid? #t))
    (unbox lines-cache))

  (define (invalid-lines!)
    (set-box! lines-valid? #f))

  (define (buf-text)   (gb->string (unbox gb)))
  (define (cursor-pos) (gap-buf-gap-start (unbox gb)))
  (define (buf-total)  (gap-buf-total-len (unbox gb)))

  ;; ── 鼠标→光标 ──
  (define (mouse->cursor mx my)
    (define ls (get-lines))
    (define li (+ (unbox view-scroll-y) (- my (unbox vp-y))))
    (define n  (length ls))
    (define b  (unbox gb))
    (define pos
      (cond [(< li 0) 0]
            [(>= li n) (buf-total)]
            [else
             (define lstart (list-ref ls li))
             (define lend   (if (< (add1 li) n) (list-ref ls (add1 li)) (buf-total)))
             (define rx (- mx (unbox vp-x)))
             (let loop ([p lstart] [col 0])
               (cond [(>= p lend) p] [(>= col rx) p]
                     [else (loop (add1 p) (+ col (gb-width-ref b p)))]))]))
    (when (not (= pos (cursor-pos)))
      (gb-move-gap! b pos)
      (set-box! dirty #t)))

  ;; ── 编辑操作（只改 buffer，不碰滚动）──
  (define (do-insert str)
    (define b (unbox gb))
    (define norm (regexp-replace* #rx"\r\n|\r" str "\n"))
    (for ([ch (in-string norm)])
      (unless (and (not multiline?) (char=? ch #\newline))
        (gb-insert! b ch (char-display-width ch))))
    (set-box! gb b)
    (invalid-lines!)
    (set-box! dirty #t)
    (on-change (buf-text)))

  (define (do-backspace)
    (when (> (cursor-pos) 0)
      (define b (unbox gb))
      (gb-backspace! b)
      (set-box! gb b)
      (invalid-lines!)
      (set-box! dirty #t)
      (on-change (buf-text))))

  (define (do-delete)
    (define b (unbox gb))
    (when (< (cursor-pos) (buf-total))
      (gb-delete! b)
      (set-box! gb b)
      (invalid-lines!)
      (set-box! dirty #t)
      (on-change (buf-text))))

  (define (do-move-left)
    (when (> (cursor-pos) 0)
      (define b (unbox gb))
      (gb-move-gap! b (sub1 (cursor-pos)))
      (set-box! gb b)
      (set-box! dirty #t)))

  (define (do-move-right)
    (define b (unbox gb))
    (when (< (cursor-pos) (buf-total))
      (gb-move-gap! b (add1 (cursor-pos)))
      (set-box! gb b)
      (set-box! dirty #t)))

  (define (do-move-up)
    (define b  (unbox gb))
    (define ls (get-lines))
    (define ci (cursor-pos))
    (define-values (li col) (pos->line+col ls ci))
    (when (> li 0)
      (define ps (list-ref ls (sub1 li)))
      (define pe (list-ref ls li))
      (define pl (- pe ps))
      (gb-move-gap! b (+ ps (min col (max 0 (sub1 pl)))))
      (set-box! gb b)
      (set-box! dirty #t)))

  (define (do-move-down)
    (define b  (unbox gb))
    (define ls (get-lines))
    (define ci (cursor-pos))
    (define-values (li col) (pos->line+col ls ci))
    (define n  (length ls))
    (when (< (add1 li) n)
      (define ps (list-ref ls (add1 li)))
      (define pe (if (< (+ li 2) n) (list-ref ls (+ li 2)) (buf-total)))
      (define pl (- pe ps))
      (gb-move-gap! b (+ ps (min col (max 0 (sub1 pl)))))
      (set-box! gb b)
      (set-box! dirty #t)))

  (define (do-move-home)
    (define b  (unbox gb))
    (define ls (get-lines))
    (define ci (cursor-pos))
    (define-values (li _) (pos->line+col ls ci))
    (define ps (list-ref ls li))
    (unless (= ci ps)
      (gb-move-gap! b ps)
      (set-box! gb b)
      (set-box! dirty #t)))

  (define (do-move-end)
    (define b  (unbox gb))
    (define ls (get-lines))
    (define ci (cursor-pos))
    (define-values (li _) (pos->line+col ls ci))
    (define n  (length ls))
    (define pe (if (< (add1 li) n) (sub1 (list-ref ls (add1 li))) (buf-total)))
    (unless (= ci pe)
      (gb-move-gap! b pe)
      (set-box! gb b)
      (set-box! dirty #t)))

  ;; ═══════════════════════════════════════════════════════════
  ;; 渲染：唯一计算滚动偏移的地方
  ;; ═══════════════════════════════════════════════════════════
  (define (render focused? x y w h)
    (set-box! vp-x x) (set-box! vp-y y)
    (set-box! vp-w w) (set-box! vp-h h)
    (define b  (unbox gb))
    (define ls (get-lines))
    (define ci (cursor-pos))
    (define tl (buf-total))
    (define-values (cur-li cur-col) (pos->line+col ls ci))
    (define n-lines (length ls))

    ;; ── 垂直滚动：确保光标行在 [0, h) 内 ──
    (define old-sy (unbox view-scroll-y))
    (define new-sy
      (cond [(< cur-li old-sy)       cur-li]
            [(>= cur-li (+ old-sy h)) (add1 (- cur-li h))]
            [(> old-sy (max 0 (- n-lines h))) (max 0 (- n-lines h))]
            [else old-sy]))
    (unless (= new-sy old-sy)
      (set-box! view-scroll-y new-sy))
    (define scr new-sy)

    ;; ── 水平滚动：仅光标贴边才移 ──
    (define old-sx (unbox view-scroll-x))

    ;; ── 清屏 ──
    (for ([sr (in-range h)])
      (cursor-move (+ y sr) x)
      (put-string (make-string w #\space)))

    ;; ── 空+无焦点 → placeholder ──
    (when (and (zero? tl) (not focused?)
               (positive? (string-length placeholder)))
      (put-styled-at! y x 'input-normal
                      (if (> (string-length placeholder) w)
                          (substring placeholder 0 w) placeholder)))

    ;; ── 逐行渲染 ──
    (for ([sr (in-range h)])
      (define li (+ scr sr))
      (when (< li n-lines)
        (define lstart (list-ref ls li))
        (define lend   (if (< (add1 li) n-lines)
                           (max lstart (sub1 (list-ref ls (add1 li))))
                           tl))

        ;; 计算总宽度
        (define total-w (for/sum ([p (in-range lstart lend)]) (gb-width-ref b p)))

        ;; ── 水平滚动（光标所在行）──
        (define hs
          (cond [(not (= li cur-li)) 0]
                [(<= total-w w)      0]
                [else
                 (define cur-col-x (for/sum ([p (in-range lstart ci)]) (gb-width-ref b p)))
                 (define cur-w (if (and (< ci tl) (not (char=? (gb-ref b ci) #\newline)))
                                   (gb-width-ref b ci) 1))
                 (define cur-r (+ cur-col-x cur-w))
                 ;; 仅贴边触发
                 (cond ((< cur-col-x old-sx)         (max 0 cur-col-x))
                       ((> cur-r (+ old-sx w -1))   (max 0 (min cur-col-x (- cur-r w))))
                       ((> old-sx cur-col-x)         (max 0 cur-col-x))
                       (else old-sx))]))
        (when (= li cur-li)
          (set-box! view-scroll-x hs))

        ;; ── 构建可见行字符串 ──
        (define line-str
          (call-with-output-string
           (λ (out)
             (let loop ([p lstart] [col 0])
               (when (< p lend)
                 (define cw (gb-width-ref b p))
                 (define cr (+ col cw))
                 (cond [(<= cr hs)            (loop (add1 p) cr)]
                       [(and (>= col hs) (<= cr (+ hs w)))
                        (write-char (if (char=? (gb-ref b p) #\newline) #\space (gb-ref b p)) out)
                        (loop (add1 p) cr)]
                       [else (loop (add1 p) cr)]))))))

        (define style (if focused? 'input-focus 'input-normal))
        (put-styled-at! (+ y sr) x style line-str)

        ;; ── 光标 ──
        (when (and focused? (= li cur-li))
          (define cur-col-x (for/sum ([p (in-range lstart ci)]) (gb-width-ref b p)))
          (define sx (- cur-col-x hs))
          (when (and (>= sx 0) (< sx w))
            (define cch (if (and (< ci tl) (not (char=? (gb-ref b ci) #\newline)))
                            (string (gb-ref b ci)) " "))
            (put-styled-at! (+ y sr) (+ x sx) 'cursor cch))))))

  ;; ── handler ──
  (define handler
    (if multiline?
        (build-input
         #:char      (λ (ch) (when (<= 32 ch 126) (do-insert (string (integer->char ch)))))
         #:utf-char   do-insert
         #:backspace  do-backspace
         #:delete     do-delete
         #:left       do-move-left
         #:right      do-move-right
         #:up         do-move-up
         #:down       do-move-down
         #:home       do-move-home
         #:end        do-move-end
         #:enter      (λ () (on-submit (buf-text)))
         #:escape     (λ () (do-insert "\n"))
         #:paste      (λ (data) (do-insert (bytes->string/utf-8 data)))
         #:mouse-press (λ (btn mx my mods) (when (eq? btn 'left) (mouse->cursor mx my)))
         #:mouse-move  (λ (mx my mods)       (mouse->cursor mx my)))
        (build-input
         #:char      (λ (ch) (when (<= 32 ch 126) (do-insert (string (integer->char ch)))))
         #:utf-char   do-insert
         #:backspace  do-backspace
         #:delete     do-delete
         #:left       do-move-left
         #:right      do-move-right
         #:home       do-move-home
         #:end        do-move-end
         #:enter      (λ () (on-submit (buf-text)))
         #:escape     void
         #:paste      (λ (data) (do-insert (bytes->string/utf-8 data)))
         #:mouse-press (λ (btn mx my mods) (when (eq? btn 'left) (mouse->cursor mx my)))
         #:mouse-move  (λ (mx my mods)       (mouse->cursor mx my)))))

  (component render handler #t #t 0 1 dirty #f))
