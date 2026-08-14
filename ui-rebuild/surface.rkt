#lang racket

;; ═══════════════════════════════════════════════════════════════════════════
;; surface.rkt — 格点缓冲（cell buffer）+ diff 生成 ANSI
;;
;; 这是声明式渲染的地基：widget 只往 surface 写格点（纯数据），
;; 渲染器把 surface 与上一帧比较，只输出变化的 run。
;; 不再有 per-component 字节缓存、dirty box、last-bounds 等。
;;
;;   cell    = (cell ch style)        ch: char,  style: 样式名或 #f(默认)
;;   surface = rows × cols 的格点数组
;;
;; 限制：当前按"1 字符 = 1 列"处理，暂未做 CJK/宽字符的 2 列占位。
;;       宽字符支持属于后续组件层/排版层的职责。
;; ═══════════════════════════════════════════════════════════════════════════

(require "../base/ansi/ansi-format.rkt"
         "../base/io/output-color.rkt")

(provide cell cell-ch cell-style cell?
         surface make-surface surface-rows surface-cols
         surface-ref surface-set! surface-put! surface-put-string!
         surface-diff-bytes)

;; ── cell ──

(struct cell (ch style) #:transparent)

;; ── surface ──

;; grid: (vectorof (vectorof cell))，行优先
(struct surface (rows cols grid) #:transparent)

(define (make-surface rows cols)
  (define blank-row (make-vector cols (cell #\space #f)))
  (surface rows cols
           (build-vector rows (λ (_) (vector-copy blank-row)))))

(define (surface-ref s r c)
  (vector-ref (vector-ref (surface-grid s) r) c))

(define (surface-set! s r c v)
  (vector-set! (vector-ref (surface-grid s) r) c v))

(define (in-bounds? s r c)
  (and (< -1 r (surface-rows s))
       (< -1 c (surface-cols s))))

;; 写单个格点（自动裁剪）
(define (surface-put! s r c ch style)
  (when (in-bounds? s r c)
    (surface-set! s r c (cell ch style))))

;; 写一串字符（自动裁剪）
(define (surface-put-string! s r c str style)
  (for ([i (in-naturals)] [ch (in-string str)])
    (surface-put! s r (+ c i) ch style)))

;; ── 比较 ──

(define (cell=? a b)
  (and (char=? (cell-ch a) (cell-ch b))
       (equal? (cell-style a) (cell-style b))))

(define (size-same? s prev)
  (and prev
       (= (surface-rows s) (surface-rows prev))
       (= (surface-cols s) (surface-cols prev))))

;; ── diff → ANSI bytes ──

(define (surface-diff-bytes s prev)
  (if (size-same? s prev)
      (diff-bytes s prev)
      (full-bytes s)))

;; 全量绘制（首帧 / resize）
(define (full-bytes s)
  (define out (open-output-bytes))
  (write-bytes format-screen-clear out)
  (for ([r (in-range (surface-rows s))])
    (write-bytes (row-all-bytes s r) out))
  (get-output-bytes out))

;; 增量绘制
(define (diff-bytes s prev)
  (define out (open-output-bytes))
  (for ([r (in-range (surface-rows s))])
    (write-bytes (row-diff-bytes s prev r) out))
  (get-output-bytes out))

;; 一整行：按"同一非默认样式"分组输出
(define (row-all-bytes s r)
  (define sr (vector-ref (surface-grid s) r))
  (define cols (surface-cols s))
  (define out (open-output-bytes))
  (let loop ([c 0])
    (cond
      [(>= c cols) (get-output-bytes out)]
      [else
       (define style (cell-style (vector-ref sr c)))
       (if style
           (let-values ([(end text) (take-same-style sr c cols style)])
             (write-bytes (run-bytes r c style text) out)
             (loop end))
           (loop (add1 c)))])))

;; 一行 diff：只输出"变化且同样式"的 run
(define (row-diff-bytes s prev r)
  (define sr (vector-ref (surface-grid s) r))
  (define pr (vector-ref (surface-grid prev) r))
  (define cols (surface-cols s))
  (define out (open-output-bytes))
  (let loop ([c 0])
    (cond
      [(>= c cols) (get-output-bytes out)]
      [(cell=? (vector-ref sr c) (vector-ref pr c)) (loop (add1 c))]
      [else
       (define style (cell-style (vector-ref sr c)))
       (let-values ([(end text) (take-changed-style sr pr c cols style)])
         (write-bytes (run-bytes r c style text) out)
         (loop end))])))

;; 从 c 开始收集同一 style 的连续格点
(define (take-same-style sr c cols style)
  (let loop ([c c] [acc '()])
    (cond
      [(>= c cols) (values c (list->string (reverse acc)))]
      [else
       (define cl (vector-ref sr c))
       (if (equal? (cell-style cl) style)
           (loop (add1 c) (cons (cell-ch cl) acc))
           (values c (list->string (reverse acc))))])))

;; 从 c 开始收集"相对 prev 变化且同一 style"的连续格点
(define (take-changed-style sr pr c cols style)
  (let loop ([c c] [acc '()])
    (cond
      [(>= c cols) (values c (list->string (reverse acc)))]
      [else
       (define cl (vector-ref sr c))
       (if (and (not (cell=? cl (vector-ref pr c)))
                (equal? (cell-style cl) style))
           (loop (add1 c) (cons (cell-ch cl) acc))
           (values c (list->string (reverse acc))))])))

;; 样式字节缓存（样式名 → SGR bytes）。style->bytes 每次 call-with-output-bytes
;; 较贵，diff 里同一样式反复出现，缓存后大幅减少分配。
(define style-bytes-cache (make-hasheq))
(define (style-bytes-for style)
  (cond
    [(not style) format-reset]
    [else
     (or (hash-ref style-bytes-cache style #f)
         (let ([bs (style->bytes style)])
           (hash-set! style-bytes-cache style bs)
           bs))]))

;; 一个 run → 光标定位 + 样式 + 文本 + reset
;; style 为 #f 时先 reset，清掉该位置残留样式
(define (run-bytes r c style text)
  (bytes-append
   (format-cursor-move (add1 r) (add1 c))
   (style-bytes-for style)
   (string->bytes/utf-8 text)
   format-reset))
