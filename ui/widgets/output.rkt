#lang racket

(require "../component.rkt"
         "../output-buffer.rkt"
         "./scrollbar.rkt"
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
  (define active-block-id (box #f))

  (define (content-width) (max 1 (- (unbox vp-w) 1)))
  (define sb (make-scrollbar))

  ;; ── 基础 ──

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

  ;; ── 折叠 ──

  (define (begin-fold! header-text [block-style style])
    (define bid (output-model-begin-block! model header-text block-style))
    (set-box! active-block-id bid) (set-box! dirty #t) bid)

  (define (end-fold!)
    (define bid (unbox active-block-id))
    (when bid (output-model-end-block! model bid))
    (set-box! active-block-id #f) (set-box! dirty #t))

  (define (toggle-fold! bid)
    (output-model-toggle-block! model bid)
    (let ([cw (content-width)] [h (unbox vp-h)])
      (when (and (> cw 0) (> h 0))
        (let ([total (vector-ref (compute-prefix-sum model cw)
                                 (output-model-count model))])
          (set-box! scroll (max 0 (min (unbox scroll) (max 0 (- total h))))))))
    (set-box! dirty #t))

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
      (for ([row (in-range h)])
        (define txt (if (< row (length slots)) (list-ref slots row) ""))
        (define pad (- cw (string-display-width txt)))
        (define line (if (> pad 0) (string-append txt (make-string pad #\space)) txt))
        (define s (slot-style model p sy row style))
        (write-bytes (format-styled-at (+ y row) x s line)))
      (when (> total h)
        ((scrollbar-render sb) bar-col y h total sy))))

  (define (slot-style model prefix sy row style)
    (let* ([ls (output-model-lines model)]
           [n (output-model-count model)]
           [li (prefix-find prefix (+ sy row))])
      (if (and (< li n) (>= li 0))
          (or (output-line-style (vector-ref ls li)) style)
          style)))

  ;; ── 滚动 ──

  (define (scroll-by! delta)
    (let ([cw (content-width)] [h (unbox vp-h)])
      (when (and (> cw 0) (> h 0))
        (let* ([p (compute-prefix-sum model cw)]
               [total (vector-ref p (output-model-line-count model))]
               [cur (unbox scroll)]
               [max-sy (max 0 (- total h))]
               [new-sy (max 0 (min (+ cur delta) max-sy))])
          (unless (= new-sy cur)
            (set-box! scroll new-sy) (set-box! dirty #t)
            (set-box! auto (>= new-sy max-sy)))))))

  ;; ── 点击 ──

  (define (click-line mx my)
    (let ([w (unbox vp-w)] [h (unbox vp-h)]
          [x (unbox vp-x)] [y (unbox vp-y)])
      (and (> w 0) (> h 0) (<= x mx (+ x w -1)) (<= y my (+ y h -1))
           (let* ([cw (content-width)]
                  [p (compute-prefix-sum model cw)]
                  [total (vector-ref p (output-model-count model))]
                  [sy (max 0 (min (unbox scroll) (max 0 (- total h))))]
                  [li (prefix-find p (+ sy (- my y)))]
                  [ls (output-model-lines model)]
                  [n (output-model-count model)])
             (and (< li n) (vector-ref ls li))))))

  ;; ── 滚动条点击/拖拽 ──

  (define (sb-ctx)
    (values (unbox vp-y) (unbox vp-h)
            (vector-ref (compute-prefix-sum model (content-width))
                        (output-model-count model))
            (unbox scroll)))

  (define (sb-press my)
    (call-with-values sb-ctx
      (λ (y h total sy)
        (let-values ([(new-sy ok?) ((scrollbar-press sb) my y h total sy)])
          (when ok? (set-box! scroll new-sy) (set-box! dirty #t))))))

  (define (sb-move my)
    (call-with-values sb-ctx
      (λ (y h total sy)
        (let-values ([(new-sy ok?) ((scrollbar-move sb) my y h total sy)])
          (when ok? (set-box! scroll new-sy) (set-box! dirty #t))))))

  (define (sb-release) ((scrollbar-release sb)))

  ;; ── 事件 ──

  (define handler
    (build-input
     #:up           (λ () (scroll-by! -1))
     #:down         (λ () (scroll-by!  1))
     #:pageup       (λ () (scroll-by! (- (unbox vp-h))))
     #:pagedown     (λ () (scroll-by! (unbox vp-h)))
     #:home         (λ () (set-box! scroll 0) (set-box! auto #f) (set-box! dirty #t))
     #:end          (λ () (set-box! scroll 0) (set-box! auto #t) (set-box! dirty #t))
     #:mouse-scroll (λ (dir x y mods) (scroll-by! (if (eq? dir 'up) -3 3)))
     #:mouse-press  (λ (btn mx my mods)
                      (set-box! auto #f)
                      (when (eq? btn 'left)
                        (let ([bar-col (+ (unbox vp-x) (content-width))])
                          (if (= mx bar-col)
                              (sb-press my)
                              (let ([line (click-line mx my)])
                                (when (and line (output-line-block-header? line))
                                  (output-model-toggle-block! model (output-line-block-id line))
                                  (set-box! dirty #t)))))))
     #:mouse-move   (λ (mx my mods) (sb-move my))
     #:mouse-release (λ (btn mx my mods) (when (eq? btn 'left) (sb-release)))))

  (values (component render handler #t show-box 0 1 dirty #f)
          append! append-styled! clear!
          fold! begin-fold! end-fold! toggle-fold!
          scroll-end!))
