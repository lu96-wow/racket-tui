#lang racket

(require "gap-buffer.rkt")

(provide output-line output-model
         make-output-model
         output-model-lines output-model-count
         output-line-block-header? output-line-block-id output-line-style
         output-line-text output-line-folded output-line-wrap-cache
         output-model-block-folded
         output-model-put-char!
         output-model-put-string!
         output-model-put-styled-char!
         output-model-put-styled-string!
         output-model-put-string-in-block!
         output-model-put-styled-string-in-block!
         output-model-clear!
         output-model-line-count
         output-model-toggle-fold!
         output-model-begin-block!
         output-model-end-block!
         output-model-toggle-block!
         output-model-block-folded?
         output-model-render-slots
         compute-prefix-sum extract-visible-slots prefix-find
         wrap-text string-display-width)

;; ═══════════════════════════════════════════════════════
;; 数据模型
;;
;;   output-line:  text     — 行文本（block header 包含 ▼/▶ 前缀）
;;                 style    — #f = 面板默认, 否则为 style name
;;                 wrap-cache / wrap-w — 换行缓存
;;                 folded   — 单行折叠（旧 API）
;;                 block-id — #f = 无块,  非负整数 = 块 id
;;                 block-header? — 是否为块的标题行
;;
;;   output-model: lines[]  — output-line 动态数组
;;                 count / cap / max-lines
;;                 block-folded — hash: block-id → box<boolean>
;;                 next-block-id — 自增计数器
;; ═══════════════════════════════════════════════════════

(struct output-line (text style wrap-cache wrap-w folded block-id block-header?)
  #:mutable #:transparent)

(struct output-model (lines count cap max-lines block-folded block-parent next-block-id)
  #:mutable #:transparent)

(define (make-output-line [text ""] [style #f])
  (output-line text style #f 0 #f #f #f))

(define (make-output-model #:max-lines [max #f])
  (define c 256)
  (define v (make-vector c))
  (vector-set! v 0 (make-output-line))
  (output-model v 1 c max (make-hash) (make-hash) 1))

;; ═══════════════════════════════════════════════════════
;; 内部 — 容量 & 上限
;; ═══════════════════════════════════════════════════════

(define (grow! m)
  (define old-c (output-model-cap m))
  (define new-c (* 2 old-c))
  (define old-ls (output-model-lines m))
  (define cnt (output-model-count m))
  (define new-ls (make-vector new-c))
  (vector-copy! new-ls 0 old-ls 0 cnt)
  (set-output-model-lines! m new-ls)
  (set-output-model-cap! m new-c))

(define (enforce-max! m)
  (define max (output-model-max-lines m))
  (when max
    (define cnt (output-model-count m))
    (when (> cnt max)
      (define excess (- cnt max))
      (define ls (output-model-lines m))
      (vector-copy! ls 0 ls excess cnt)
      (for ([i (in-range (- cnt excess) cnt)])
        (vector-set! ls i (make-output-line)))
      (set-output-model-count! m (- cnt excess)))))

(define (output-model-line-count m) (output-model-count m))

;; ═══════════════════════════════════════════════════════
;; 换行 & 显示宽度
;; ═══════════════════════════════════════════════════════

(define (wrap-text text w)
  (define chars (string->list text))
  (let loop ([chars chars] [lw 0] [cur '()] [acc '()])
    (cond
      [(null? chars)
       (reverse (if (null? cur) acc
                    (cons (list->string (reverse cur)) acc)))]
      [else
       (define ch (car chars))
       (define cw (char-display-width ch))
       (cond [(and (null? cur) (> cw w))
              (loop (cdr chars) 0 '() (cons (string ch) acc))]
             [(> (+ lw cw) w)
              (loop chars 0 '() (cons (list->string (reverse cur)) acc))]
             [else
              (loop (cdr chars) (+ lw cw) (cons ch cur) acc)])])))

(define (string-display-width s)
  (for/sum ([ch (in-string s)]) (char-display-width ch)))

(define (ensure-wrap! line w)
  (unless (and (output-line-wrap-cache line)
               (= (output-line-wrap-w line) w))
    (set-output-line-wrap-cache! line (wrap-text (output-line-text line) w))
    (set-output-line-wrap-w! line w)))

;; ═══════════════════════════════════════════════════════
;; 折叠块可见性 — 递归检查祖先链
;; ═══════════════════════════════════════════════════════

(define (block-folded? model bid)
  (if (not bid) #f
      (let ([b (hash-ref (output-model-block-folded model) bid #f)])
        (or (and b (unbox b))
            (block-folded? model (hash-ref (output-model-block-parent model) bid #f))))))

;; ═══════════════════════════════════════════════════════
;; slot 计算 — 一行占几个 display-slot
;;   折叠块 body 行 → 0
;;   折叠块 header → 正常（显示 ▶ 缩略）
;;   单行折叠      → 0
;; ═══════════════════════════════════════════════════════

(define (line-slots model i w)
  (define line (vector-ref (output-model-lines model) i))
  (cond
    ;; 单行折叠（旧 API）
    [(output-line-folded line) 0]
    ;; 折叠块 body — 看 block 是否折叠
    [(and (output-line-block-id line)
          (not (output-line-block-header? line))
          (block-folded? model (output-line-block-id line)))
     0]
    [else
     (ensure-wrap! line w)
     (length (output-line-wrap-cache line))]))

;; ═══════════════════════════════════════════════════════
;; 前缀和 — 行号 → 累计 slot 索引 的映射
;; ═══════════════════════════════════════════════════════

(define (compute-prefix-sum model w)
  (define ls (output-model-lines model))
  (define n (output-model-count model))
  (define p (make-vector (add1 n) 0))
  (for ([i (in-range n)])
    (vector-set! p (add1 i) (+ (vector-ref p i)
                               (line-slots model i w))))
  p)

(define (prefix-find prefix slot-index)
  (define n (sub1 (vector-length prefix)))
  (let loop ([lo 0] [hi n])
    (if (>= lo hi)
        lo
        (let ([mid (quotient (+ lo hi 1) 2)])
          (if (<= (vector-ref prefix mid) slot-index)
              (loop mid hi)
              (loop lo (sub1 mid)))))))

;; ═══════════════════════════════════════════════════════
;; 可视 slot 提取
;; ═══════════════════════════════════════════════════════

(define (extract-visible-slots model prefix sy h)
  (define ls (output-model-lines model))
  (define n (output-model-count model))
  (define start-li (prefix-find prefix sy))
  (define off (- sy (vector-ref prefix start-li)))
  (let iter ([li start-li] [rem h] [acc '()])
    (cond [(or (zero? rem) (>= li n)) (values (reverse acc) li)]
          [else
           (define line (vector-ref ls li))
           (define skip?
             (or (output-line-folded line)
                 (and (output-line-block-id line)
                      (not (output-line-block-header? line))
                      (block-folded? model (output-line-block-id line)))))
           (if skip?
               (iter (add1 li) rem acc)
               (let* ([wrapped (output-line-wrap-cache line)]
                      [start (if (= li start-li) off 0)]
                      [take (min rem (- (length wrapped) start))])
                 (let collect ([j start] [end (+ start take)] [a acc])
                   (if (>= j end)
                       (iter (add1 li) (- rem take) a)
                       (collect (add1 j) end
                                (cons (list-ref wrapped j) a))))))])))

(define (output-model-render-slots model w scroll-y h)
  (define p (compute-prefix-sum model w))
  (define n (output-model-count model))
  (define total (vector-ref p n))
  (define sy (max 0 (min scroll-y (max 0 (- total h)))))
  (define-values (slots li) (extract-visible-slots model p sy h))
  (values slots total sy))

;; ═══════════════════════════════════════════════════════
;; 追加文本
;; ═══════════════════════════════════════════════════════

(define (put-char! m ch style active-block-id)
  (define cnt (output-model-count m))
  (define ls (output-model-lines m))
  (define last (vector-ref ls (sub1 cnt)))
  (set-output-line-wrap-cache! last #f)
  (if (char=? ch #\newline)
      (begin
        (when (>= cnt (output-model-cap m))
          (grow! m) (set! ls (output-model-lines m)))
        ;; 新行继承当前 block-id（如果在块内）
        (let ([new-line (output-line "" style #f 0 #f active-block-id #f)])
          (vector-set! ls cnt new-line))
        (set-output-model-count! m (add1 cnt))
        (enforce-max! m))
      (begin
        (set-output-line-text! last
          (string-append (output-line-text last) (string ch)))
        (when style
          (set-output-line-style! last style))
        (when active-block-id
          (set-output-line-block-id! last active-block-id)))))

(define (output-model-put-char! m ch)        (put-char! m ch #f #f))
(define (output-model-put-string! m str)     (for ([ch (in-string str)]) (put-char! m ch #f #f)))
(define (output-model-put-styled-char! m ch style)       (put-char! m ch style #f))
(define (output-model-put-styled-string! m str style)    (for ([ch (in-string str)]) (put-char! m ch style #f)))
(define (output-model-put-string-in-block! m str style block-id)          (for ([ch (in-string str)]) (put-char! m ch style block-id)))
(define (output-model-put-styled-string-in-block! m str style block-id)   (for ([ch (in-string str)]) (put-char! m ch style block-id)))

;; ═══════════════════════════════════════════════════════
;; 折叠块
;; ═══════════════════════════════════════════════════════

(define (output-model-begin-block! m parent-bid)
  (define cnt (output-model-count m))
  (define ls (output-model-lines m))
  (define bid (output-model-next-block-id m))
  (set-output-model-next-block-id! m (add1 bid))
  (hash-set! (output-model-block-folded m) bid (box #f))
  (when parent-bid
    (hash-set! (output-model-block-parent m) bid parent-bid))
  ;; find last non-empty line → mark as block header
  ;; also mark trailing empty lines with this block-id
  (let loop ([i (sub1 cnt)])
    (when (>= i 0)
      (define line (vector-ref ls i))
      (set-output-line-block-id! line bid)
      (if (positive? (string-length (output-line-text line)))
          (set-output-line-block-header?! line #t)
          (loop (sub1 i)))))
  bid)

(define (output-model-end-block! m bid)
  ;; 关闭块 — 后续 put 不再继承此 block-id
  ;; 这里不需要特别操作，因为 put-char! 使用 active-block-id 参数
  ;; end-block! 的作用是让 widget 层知道不再往这个块里写
  (void))

(define (output-model-toggle-block! m bid)
  (define folded-box (hash-ref (output-model-block-folded m) bid #f))
  (when folded-box
    (define was-folded (unbox folded-box))
    (set-box! folded-box (not was-folded))
    ;; 更新 header 文本: ▼ ↔ ▶
    (define ls (output-model-lines m))
    (define cnt (output-model-count m))
    (let loop ([i 0])
      (when (< i cnt)
        (define line (vector-ref ls i))
        (if (and (output-line-block-header? line)
                 (= (output-line-block-id line) bid))
            (let ([txt (output-line-text line)]
                  [prefix (if was-folded "▼ " "▶ ")]
                  [old-prefix (if was-folded "▶ " "▼ ")])
              (define new-txt
                (string-append prefix
                  (if (string-prefix? txt old-prefix)
                      (substring txt 2)
                      txt)))
              (set-output-line-text! line new-txt)
              (set-output-line-wrap-cache! line #f))
            (loop (add1 i)))))))

(define (output-model-block-folded? m bid)
  (define b (hash-ref (output-model-block-folded m) bid #f))
  (and b (unbox b)))

;; ═══════════════════════════════════════════════════════
;; 旧 API 兼容
;; ═══════════════════════════════════════════════════════

(define (output-model-clear! m)
  (define ls (output-model-lines m))
  (for ([i (in-range (output-model-count m))])
    (vector-set! ls i (make-output-line)))
  (set-output-model-block-folded! m (make-hash))
  (set-output-model-block-parent! m (make-hash))
  (set-output-model-next-block-id! m 1)
  (set-output-model-count! m 1))

(define (output-model-toggle-fold! m idx)
  (when (< idx (output-model-count m))
    (define l (vector-ref (output-model-lines m) idx))
    (set-output-line-folded! l (not (output-line-folded l)))))
