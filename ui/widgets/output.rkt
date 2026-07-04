#lang racket

(require "../component.rkt"
         "../output-buffer.rkt"
         "../../base/io/build-input.rkt"
         "../../base/io/output-color.rkt"
         "../../base/io/output-styles.rkt"
         "../../base/io/output.rkt")

(provide make-output
         output-model-put-string! output-model-put-char!
         output-model-put-styled-string! output-model-put-styled-char!
         output-model-put-string-in-block! output-model-put-styled-string-in-block!
         output-model-clear! output-model-toggle-fold!)

(define (make-output #:max-lines   [max-lines #f]
                     #:style       [style 'info]
                     #:show?       [show? (box #t)]
                     #:auto-scroll? [auto? #t])

  (define show-box (if (boolean? show?) (box show?) show?))
  (define model   (make-output-model #:max-lines max-lines))
  (define dirty   (box #t))
  (define scroll  (box 0))
  (define auto    (box auto?))
  (define vp-w (box 80)) (define vp-h (box 24))
  (define vp-x (box 1))  (define vp-y (box 1))
  (define last-total (box 0))

  ;; 当前活跃的折叠块 id（在 begin-fold! / end-fold! 之间自动关联）
  (define active-block-id (box #f))

  ;; ── 内部: 内容区宽度（右侧 1 列留给滚动条）──
  (define (content-width) (max 1 (- (unbox vp-w) 1)))

  ;; ── 基础输出 ──

  (define (append! str)
    (define bid (unbox active-block-id))
    (if bid
        (output-model-put-string-in-block! model str style bid)
        (output-model-put-string! model str))
    (set-box! dirty #t))

  (define (append-styled! str st)
    (define bid (unbox active-block-id))
    (if bid
        (output-model-put-styled-string-in-block! model str st bid)
        (output-model-put-styled-string! model str st))
    (set-box! dirty #t))

  (define (clear!)
    (output-model-clear! model) (set-box! scroll 0)
    (set-box! active-block-id #f)
    (set-box! last-total 0) (set-box! dirty #t))

  (define (scroll-end!)
    (set-box! auto #t) (set-box! scroll 0) (set-box! dirty #t))

  ;; ── 折叠块 ──

  (define (begin-fold! header-text [block-style style])
    (define bid (output-model-begin-block! model header-text block-style))
    (set-box! active-block-id bid)
    (set-box! dirty #t)
    bid)

  (define (end-fold!)
    (define bid (unbox active-block-id))
    (when bid (output-model-end-block! model bid))
    (set-box! active-block-id #f)
    (set-box! dirty #t))

  (define (toggle-fold! bid)
    (output-model-toggle-block! model bid)
    (define cw (content-width))
    (define h (unbox vp-h))
    (when (and (> cw 0) (> h 0))
      (define total (vector-ref (compute-prefix-sum model cw)
                                (output-model-count model)))
      (set-box! scroll (max 0 (min (unbox scroll) (max 0 (- total h))))))
    (set-box! dirty #t))

  ;; ── 旧 fold API (单行) ──

  (define (fold! idx)
    (output-model-toggle-fold! model idx) (set-box! dirty #t))

  ;; ── 渲染 ──

  (define (render focused? x y w h)
    (set-box! vp-w w) (set-box! vp-h h)
    (set-box! vp-x x) (set-box! vp-y y)
    (when (and (> w 0) (> h 0))
      (define cw (content-width))
      (define bar-col (+ x cw))
      (define p (compute-prefix-sum model cw))
      (define total (vector-ref p (output-model-line-count model)))
      (when (and (unbox auto) (> total (unbox last-total)))
        (set-box! scroll (max 0 (- total h))))
      (set-box! last-total total)
      (define sy (max 0 (min (unbox scroll) (max 0 (- total h)))))
      (define-values (slots _li) (extract-visible-slots model p sy h))
      ;; ── 文本渲染 ──
      (for ([row (in-range h)])
        (define txt (if (< row (length slots)) (list-ref slots row) ""))
        (define pad (- cw (string-display-width txt)))
        (define line (if (> pad 0) (string-append txt (make-string pad #\space)) txt))
        (define line-style (slot-style model p sy row style))
        (write-bytes (format-styled-at (+ y row) x line-style line)))
      ;; ── 滚动条（内容溢出时显示）──
      (when (and (> w 1) (> total h))
        (define thumb-h (max 1 (quotient (* h h) total)))
        (define thumb-y (quotient (* sy (- h thumb-h)) (max 1 (- total h))))
        (for ([row (in-range h)])
          (define in-thumb? (<= thumb-y row (+ thumb-y thumb-h -1)))
          (write-bytes (format-styled-at (+ y row) bar-col
                         (if in-thumb? 'scroll-thumb 'scroll-track)
                         (if in-thumb? "█" "│")))))))

  ;; 根据 slot 位置查找对应行的 style
  (define (slot-style model prefix sy row style)
    (define ls (output-model-lines model))
    (define n (output-model-count model))
    (define slot-idx (+ sy row))
    (define li (prefix-find prefix slot-idx))
    (if (and (< li n) (>= li 0))
        (or (output-line-style (vector-ref ls li)) style)
        style))

  ;; ── 滚动 ──

  (define (scroll-by! delta)
    (define cw (content-width))
    (define h (unbox vp-h))
    (when (and (> cw 0) (> h 0))
      (define p (compute-prefix-sum model cw))
      (define total (vector-ref p (output-model-line-count model)))
      (define cur (unbox scroll))
      (define max-sy (max 0 (- total h)))
      (define new-sy (max 0 (min (+ cur delta) max-sy)))
      (unless (= new-sy cur)
        (set-box! scroll new-sy) (set-box! dirty #t)
        (set-box! auto (>= new-sy max-sy)))))

  ;; ── 事件 ──

  (define (click-line mx my)
    ;; 返回被点击的 output-line，或 #f
    (define w (unbox vp-w))
    (define h (unbox vp-h))
    (define x (unbox vp-x))
    (define y (unbox vp-y))
    (when (and (> w 0) (> h 0)
               (<= x mx (+ x w -1))
               (<= y my (+ y h -1)))
      (define rel-row (- my y))
      (define cw (content-width))
      (define p (compute-prefix-sum model cw))
      (define total (vector-ref p (output-model-count model)))
      ;; clamp — 和 render 一致
      (define sy (max 0 (min (unbox scroll) (max 0 (- total h)))))
      (define slot-idx (+ sy rel-row))
      (define li (prefix-find p slot-idx))
      (define ls (output-model-lines model))
      (define n (output-model-count model))
      (and (< li n) (vector-ref ls li))))

  (define handler
    (build-input
     #:up           (λ () (scroll-by! -1))
     #:down         (λ () (scroll-by!  1))
     #:pageup       (λ () (scroll-by! (- (unbox vp-h))))
     #:pagedown     (λ () (scroll-by! (unbox vp-h)))
     #:home         (λ () (set-box! scroll 0) (set-box! auto #f)
                         (set-box! dirty #t))
     #:end          (λ () (set-box! scroll 0) (set-box! auto #t)
                         (set-box! dirty #t))
     #:mouse-scroll (λ (dir x y mods)
                      (scroll-by! (if (eq? dir 'up) -3 3)))
     #:mouse-press  (λ (btn mx my mods)
                      (set-box! auto #f)
                      ;; 点击折叠块 header → 切换
                      (when (eq? btn 'left)
                        (define line (click-line mx my))
                        (when (and line (output-line-block-header? line))
                          (output-model-toggle-block! model (output-line-block-id line))
                          (set-box! dirty #t))))))

  (values (component render handler #t show-box 0 1 dirty #f)
          append! append-styled! clear!
          fold! begin-fold! end-fold! toggle-fold!
          scroll-end!))
