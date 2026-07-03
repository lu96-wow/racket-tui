#lang racket

(require "../component.rkt"
         "../../base/io/build-input.rkt"
         "../../base/io/output-styles.rkt"
         "../../base/io/output-color.rkt"
         "../../base/io/output.rkt")

(provide make-output
         out-fold out-fold? out-fold-title out-fold-children out-fold-expanded?
         out-fold-expand! out-fold-collapse! out-fold-toggle!
         out-fold-expand-all! out-fold-collapse-all!)

;; ═══════════════════════════════════════════════════════
;; 数据模型: 可折叠块
;; ═══════════════════════════════════════════════════════

(struct out-fold (title children expanded?) #:mutable #:transparent)

(define (out-fold-expand! f)   (set-out-fold-expanded?! f #t))
(define (out-fold-collapse! f) (set-out-fold-expanded?! f #f))
(define (out-fold-toggle! f)
  (set-out-fold-expanded?! f (not (out-fold-expanded? f))))

(define (out-fold-expand-all! b)
  (when (out-fold? b)
    (out-fold-expand! b)
    (for ([c (out-fold-children b)])
      (out-fold-expand-all! c))))

(define (out-fold-collapse-all! b)
  (when (out-fold? b)
    (out-fold-collapse! b)
    (for ([c (out-fold-children b)])
      (out-fold-collapse-all! c))))

;; ═══════════════════════════════════════════════════════
;; 展开 → 扁平行 + fold 映射 vector
;;   fold-at[i] = fold 对象 (第 i 行是 fold 标题) 或 #f
;; ═══════════════════════════════════════════════════════

(define (flatten-blocks blocks)
  (define lines '())
  (define folds '())
  (define (walk bs indent)
    (for ([b bs])
      (cond
        [(string? b)
         (set! lines (append lines (list (string-append indent b))))
         (set! folds (append folds (list #f)))]
        [(out-fold? b)
         (define marker (if (out-fold-expanded? b) "[-] " "[+] "))
         (set! lines (append lines (list (string-append indent marker (out-fold-title b)))))
         (set! folds (append folds (list b)))
         (when (out-fold-expanded? b)
           (walk (out-fold-children b) (string-append "  " indent)))]
        [else
         (set! lines (append lines (list (string-append indent (format "~a" b)))))
         (set! folds (append folds (list #f)))])))
  (walk blocks "")
  (values lines (list->vector folds)))

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
  (define cache    (box (list)))     ;; 扁平行列表
  (define fold-at  (box (vector)))   ;; 行→fold 映射

  (define vp-x (box 0)) (define vp-y (box 0))
  (define vp-w (box 0)) (define vp-h (box 0))
  (define dragging? (box #f))  ;; 滚动条拖拽状态

  ;; ── 刷新缓存 ──
  (define (refresh-cache)
    (define-values (lines fa) (flatten-blocks (unbox blocks-box)))
    (set-box! cache lines)
    (set-box! fold-at fa))

  ;; ── render? 检测 blocks 变化 ──
  (define (check-dirty x y w h focused?)
    (define-values (new-lines _) (flatten-blocks (unbox blocks-box)))
    (unless (equal? new-lines (unbox cache))
      (refresh-cache)
      (set-box! dirty #t)))

  ;; ── 鼠标: scrollbar 拖拽 ──
  (define (scrollbar-drag my)
    (define h (unbox vp-h))
    (define n (length (unbox cache)))
    (when (> n h)
      (define thumb-h (max 1 (quotient (* h h) n)))
      (define rel-y (- my (unbox vp-y) (quotient thumb-h 2)))
      (define sy-range (- n h))
      (define thumb-range (- h thumb-h))
      (if (<= thumb-range 0)
          (set-box! scroll-y 0)
          (set-box! scroll-y (max 0 (min sy-range
                                         (quotient (* rel-y sy-range) thumb-range)))))))

  ;; ── 鼠标 click: fold toggle 或 scrollbar drag 开始 ──
  (define (mouse-click mx my)
    (define sb-x (+ (unbox vp-x) (unbox vp-w) -1))
    (if (= mx sb-x)
        ;; 点击滚动条 → 开始拖拽
        (begin (set-box! dragging? #t)
               (scrollbar-drag my)
               (set-box! dirty #t))
        ;; 点击内容区 → toggle fold
        (let* ((sy (unbox scroll-y))
               (li (+ sy (- my (unbox vp-y))))
               (fa (unbox fold-at)))
          (when (and (>= li 0) (< li (vector-length fa)))
            (define f (vector-ref fa li))
            (when f
              (out-fold-toggle! f)
              (refresh-cache)
              (set-box! dirty #t))))))

  ;; ── render ──
  (define (render focused? x y w h)
    (set-box! vp-x x) (set-box! vp-y y)
    (set-box! vp-w w) (set-box! vp-h h)

    (define lines (unbox cache))
    (define n (length lines))

    ;; 滚动 clamp
    (define max-sy (max 0 (- n h)))
    (when (> (unbox scroll-y) max-sy)
      (set-box! scroll-y max-sy))
    (define sy (unbox scroll-y))

    ;; 背景
    (for ([sr (in-range h)])
      (write-bytes (format-styled-at! (+ y sr) x style (make-string w #\space))))

    ;; 逐行
    (for ([sr (in-range h)])
      (define li (+ sy sr))
      (when (< li n)
        (define line (list-ref lines li))
        (define visible (if (> (string-length line) w)
                           (substring line 0 w)
                           line))
        (write-bytes (format-styled-at! (+ y sr) x
                                        (if focused? focus-style style)
                                        visible))))

    ;; 滚动条
    (when (> n h)
      (define thumb-h (max 1 (quotient (* h h) n)))
      (define thumb-y (quotient (* sy h) n))
      ;; 轨道
      (for ([i (in-range h)])
        (write-bytes (format-styled-at! (+ y i) (+ x w -1) style " ")))
      ;; 滑块
      (for ([i (in-range thumb-h)])
        (when (< (+ thumb-y i) h)
          (write-bytes (format-styled-at! (+ y thumb-y i) (+ x w -1)
                                          (if (unbox dragging?) 'button-pressed 'cursor) " "))))))

  ;; ── handler ──
  (define handler
    (build-input
     #:up         (λ () (when (> (unbox scroll-y) 0)
                           (set-box! scroll-y (sub1 (unbox scroll-y)))
                           (set-box! dirty #t)))
     #:down       (λ () (define l (unbox cache))
                         (when (< (unbox scroll-y) (max 0 (- (length l) (unbox vp-h))))
                           (set-box! scroll-y (add1 (unbox scroll-y)))
                           (set-box! dirty #t)))
     #:pageup     (λ () (set-box! scroll-y (max 0 (- (unbox scroll-y) (unbox vp-h))))
                         (set-box! dirty #t))
     #:pagedown   (λ () (define l (unbox cache))
                         (set-box! scroll-y (min (max 0 (- (length l) (unbox vp-h)))
                                                 (+ (unbox scroll-y) (unbox vp-h))))
                         (set-box! dirty #t))
     #:home       (λ () (set-box! scroll-y 0) (set-box! dirty #t))
     #:end        (λ () (define l (unbox cache))
                         (set-box! scroll-y (max 0 (- (length l) (unbox vp-h))))
                         (set-box! dirty #t))
     #:enter      (λ () (define fa (unbox fold-at))
                         (define sy (unbox scroll-y))
                         (when (and (>= sy 0) (< sy (vector-length fa)))
                           (define f (vector-ref fa sy))
                           (when f
                             (out-fold-toggle! f)
                             (refresh-cache)
                             (set-box! dirty #t))))
     #:mouse-press (λ (btn mx my mods) (when (eq? btn 'left) (mouse-click mx my)))
     #:mouse-move  (λ (mx my mods)
                     (when (unbox dragging?)
                       (scrollbar-drag my)
                       (set-box! dirty #t)))
     #:mouse-release (λ (btn mx my mods)
                       (when (eq? btn 'left)
                         (set-box! dragging? #f)))
     #:mouse-scroll (λ (dir x y mods)
                      (case dir
                        [(up)   (when (> (unbox scroll-y) 0)
                                  (set-box! scroll-y (sub1 (unbox scroll-y)))
                                  (set-box! dirty #t))]
                        [(down) (define l (unbox cache))
                                (when (< (unbox scroll-y) (max 0 (- (length l) (unbox vp-h))))
                                  (set-box! scroll-y (add1 (unbox scroll-y)))
                                  (set-box! dirty #t))]))))

  (refresh-cache)
  (component render handler #t show-box 0 1 dirty check-dirty))
