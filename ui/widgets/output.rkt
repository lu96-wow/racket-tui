#lang racket

(require "../component.rkt"
         "../../base/io/build-input.rkt"
         "../../base/io/output-styles.rkt"
         "../../base/io/output-color.rkt"
         "../../base/io/output.rkt")

(provide make-output
         ;; fold
         out-fold out-fold? out-fold-title out-fold-children out-fold-expanded?
         out-fold-expand! out-fold-collapse! out-fold-toggle!
         out-fold-expand-all! out-fold-collapse-all!
         ;; styled line
         out-line out-line? out-line-text out-line-style)

;; ═══════════════════════════════════════════════════════
;; 数据模型
;; ═══════════════════════════════════════════════════════

(struct out-fold (title children expanded?) #:mutable #:transparent)
(define (out-fold-expand! f)   (set-out-fold-expanded?! f #t))
(define (out-fold-collapse! f) (set-out-fold-expanded?! f #f))
(define (out-fold-toggle! f)
  (set-out-fold-expanded?! f (not (out-fold-expanded? f))))

(define (out-fold-expand-all! b)
  (when (out-fold? b)
    (out-fold-expand! b)
    (for ([c (out-fold-children b)]) (out-fold-expand-all! c))))

(define (out-fold-collapse-all! b)
  (when (out-fold? b)
    (out-fold-collapse! b)
    (for ([c (out-fold-children b)]) (out-fold-collapse-all! c))))

;; 带样式的行
(struct out-line (text style) #:transparent)

;; ═══════════════════════════════════════════════════════
;; 展开 → (values flat-lines flat-styles fold-map)
;;   每行有对应的 style 名; fold-at[i] = fold|#f
;; ═══════════════════════════════════════════════════════

(define (flatten-blocks blocks default-style)
  (define lines '())
  (define styles '())
  (define folds  '())
  (define (walk bs indent)
    (for ([b bs])
      (cond
        [(string? b)
         (set! lines  (append lines  (list (string-append indent b))))
         (set! styles (append styles (list default-style)))
         (set! folds  (append folds  (list #f)))]
        [(out-line? b)
         (set! lines  (append lines  (list (string-append indent (out-line-text b)))))
         (set! styles (append styles (list (out-line-style b))))
         (set! folds  (append folds  (list #f)))]
        [(out-fold? b)
         (define marker (if (out-fold-expanded? b) "[-] " "[+] "))
         (set! lines  (append lines  (list (string-append indent marker (out-fold-title b)))))
         (set! styles (append styles (list 'output-fold)))
         (set! folds  (append folds  (list b)))
         (when (out-fold-expanded? b)
           (walk (out-fold-children b) (string-append "  " indent)))]
        [else
         (set! lines  (append lines  (list (string-append indent (format "~a" b)))))
         (set! styles (append styles (list default-style)))
         (set! folds  (append folds  (list #f)))])))
  (walk blocks "")
  (values lines styles (list->vector folds)))

;; ═══════════════════════════════════════════════════════
;; make-output
;; ═══════════════════════════════════════════════════════

(define (make-output #:blocks [blocks-box (box '())]
                     #:style [style 'output-normal]
                     #:focus-style [focus-style 'output-focus]
                     #:show? [show? (box #t)])
  (define show-box (if (boolean? show?) (box show?) show?))
  (define dirty    (box #t))
  (define scroll-y (box 0))
  (define cache    (box (list)))        ;; 扁平行
  (define styles   (box (list)))        ;; 每行样式
  (define fold-at  (box (vector)))      ;; 行→fold
  (define at-bottom (box #t))           ;; 流式 auto-scroll

  (define vp-x (box 0)) (define vp-y (box 0))
  (define vp-w (box 0)) (define vp-h (box 0))
  (define dragging? (box #f))

  ;; ── 刷新缓存 ──
  (define (refresh-cache)
    (define-values (ls ss fa) (flatten-blocks (unbox blocks-box) style))
    (set-box! cache ls)
    (set-box! styles ss)
    (set-box! fold-at fa))

  ;; ── render? 检测变化 + auto-scroll ──
  (define (check-dirty x y w h focused?)
    (define-values (new-ls _1 _2) (flatten-blocks (unbox blocks-box) style))
    (unless (equal? new-ls (unbox cache))
      (define was-at-bottom (unbox at-bottom))
      (refresh-cache)
      (set-box! dirty #t)
      ;; 流式: 之前在底部 → 自动滚到底
      (when was-at-bottom
        (define new-n (length (unbox cache)))
        (set-box! scroll-y (max 0 (- new-n h)))
        (set-box! at-bottom #t))))

  ;; ── 判定是否在底部 ──
  (define (update-at-bottom!)
    (define max-sy (max 0 (- (length (unbox cache)) (unbox vp-h))))
    (set-box! at-bottom (>= (unbox scroll-y) max-sy)))

  ;; ── 鼠标: scrollbar 拖拽 ──
  (define (scrollbar-drag my)
    (define h (unbox vp-h))
    (define n (length (unbox cache)))
    (when (> n h)
      (define thumb-h (max 1 (quotient (* h h) n)))
      (define rel-y (- my (unbox vp-y) (quotient thumb-h 2)))
      (define sy-range (- n h))
      (define thumb-range (- h thumb-h))
      (set-box! scroll-y
                (if (<= thumb-range 0)
                    0
                    (max 0 (min sy-range
                                 (quotient (* rel-y sy-range) thumb-range)))))
      (update-at-bottom!)))

  ;; ── 鼠标 click ──
  (define (mouse-click mx my)
    (define sb-x (+ (unbox vp-x) (unbox vp-w) -1))
    (if (= mx sb-x)
        (begin (set-box! dragging? #t)
               (scrollbar-drag my)
               (set-box! dirty #t))
        (let* ((sy (unbox scroll-y))
               (li (+ sy (- my (unbox vp-y))))
               (fa (unbox fold-at)))
          (when (and (>= li 0) (< li (vector-length fa)))
            (define f (vector-ref fa li))
            (when f
              (out-fold-toggle! f)
              (refresh-cache)
              (set-box! dirty #t))))))

  ;; ── scroll helper ──
  (define (do-scroll delta)
    (define l (unbox cache))
    (define max-sy (max 0 (- (length l) (unbox vp-h))))
    (set-box! scroll-y (max 0 (min max-sy (+ (unbox scroll-y) delta))))
    (update-at-bottom!)
    (set-box! dirty #t))

  ;; ── render ──
  (define (render focused? x y w h)
    (set-box! vp-x x) (set-box! vp-y y)
    (set-box! vp-w w) (set-box! vp-h h)

    (define ls (unbox cache))
    (define ss (unbox styles))
    (define n (length ls))

    ;; 滚动 clamp
    (define max-sy (max 0 (- n h)))
    (when (> (unbox scroll-y) max-sy)
      (set-box! scroll-y max-sy))
    (define sy (unbox scroll-y))

    ;; 背景
    (for ([sr (in-range h)])
      (write-bytes (format-styled-at! (+ y sr) x style (make-string w #\space))))

    ;; 逐行 — 每行用自己的 style
    (for ([sr (in-range h)])
      (define li (+ sy sr))
      (when (< li n)
        (define line (list-ref ls li))
        (define line-style (list-ref ss li))
        (define visible (if (> (string-length line) w)
                           (substring line 0 w)
                           line))
        (write-bytes (format-styled-at! (+ y sr) x line-style visible))))

    ;; 滚动条
    (when (> n h)
      (define thumb-h (max 1 (quotient (* h h) n)))
      (define thumb-y (quotient (* sy h) n))
      (for ([i (in-range h)])
        (write-bytes (format-styled-at! (+ y i) (+ x w -1) style " ")))
      (for ([i (in-range thumb-h)])
        (when (< (+ thumb-y i) h)
          (write-bytes (format-styled-at! (+ y thumb-y i) (+ x w -1)
                                          (if (unbox dragging?) 'button-pressed 'cursor) " "))))))

  ;; ── handler ──
  (define handler
    (build-input
     #:up         (λ () (do-scroll -1))
     #:down       (λ () (do-scroll 1))
     #:pageup     (λ () (do-scroll (- (unbox vp-h))))
     #:pagedown   (λ () (do-scroll (unbox vp-h)))
     #:home       (λ () (set-box! scroll-y 0) (update-at-bottom!) (set-box! dirty #t))
     #:end        (λ () (define l (unbox cache))
                         (set-box! scroll-y (max 0 (- (length l) (unbox vp-h))))
                         (set-box! at-bottom #t)
                         (set-box! dirty #t))
     #:enter      (λ () (define fa (unbox fold-at))
                         (define sy (unbox scroll-y))
                         (when (and (>= sy 0) (< sy (vector-length fa)))
                           (define f (vector-ref fa sy))
                           (when f
                             (out-fold-toggle! f)
                             (refresh-cache)
                             (set-box! dirty #t))))
     #:mouse-press   (λ (btn mx my mods) (when (eq? btn 'left) (mouse-click mx my)))
     #:mouse-move    (λ (mx my mods)
                       (when (unbox dragging?)
                         (scrollbar-drag my)
                         (set-box! dirty #t)))
     #:mouse-release (λ (btn mx my mods)
                       (when (eq? btn 'left)
                         (set-box! dragging? #f)))
     #:mouse-scroll (λ (dir x y mods)
                      (case dir [(up) (do-scroll -1)] [(down) (do-scroll 1)]))))

  (refresh-cache)
  (component render handler #t show-box 0 1 dirty check-dirty))
