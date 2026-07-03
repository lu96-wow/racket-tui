#lang racket

;; ═══════════════════════════════════════════════════════
;; Output Buffer — 流式输出数据层
;;
;; logical-lines: \n 分隔，预分配 vector (O(1) 追加)
;; wrap-cache:    每行折行缓存，追加只失效最后一行
;; prefix-sum:    渲染时计算，二分定位 scroll-y
;; ═══════════════════════════════════════════════════════

(require "gap-buffer.rkt")  ;; char-display-width

(provide output-line output-model
         make-output-model
         output-model-put-char!
         output-model-put-string!
         output-model-clear!
         output-model-line-count
         output-model-toggle-fold!
         output-model-render-slots
         compute-prefix-sum extract-visible-slots
         wrap-text)

(struct output-line (text wrap-cache wrap-w folded)
  #:mutable #:transparent)

(struct output-model (lines count cap max-lines)
  #:mutable #:transparent)

(define (make-output-model #:max-lines [max #f])
  (define c 256)
  (define v (make-vector c))
  (vector-set! v 0 (output-line "" #f 0 #f))
  (output-model v 1 c max))

;; ── 扩容 ──
(define (grow! m)
  (define old-c (output-model-cap m))
  (define new-c (* 2 old-c))
  (define old-ls (output-model-lines m))
  (define cnt (output-model-count m))
  (define new-ls (make-vector new-c))
  (vector-copy! new-ls 0 old-ls 0 cnt)
  (set-output-model-lines! m new-ls)
  (set-output-model-cap! m new-c))

;; ── 查询 ──
(define (output-model-line-count m) (output-model-count m))

(define (line-slots line w)
  (if (output-line-folded line)
      0
      (begin (ensure-wrap! line w)
             (length (output-line-wrap-cache line)))))

;; ── 前缀和 ──
(define (compute-prefix-sum model w)
  (define ls (output-model-lines model))
  (define n (output-model-count model))
  (define p (make-vector (add1 n) 0))
  (for ([i (in-range n)])
    (vector-set! p (add1 i) (+ (vector-ref p i)
                               (line-slots (vector-ref ls i) w))))
  p)

;; 二分: 找最大的 i 使得 prefix[i] <= slot-index
(define (prefix-find prefix slot-index)
  (define n (sub1 (vector-length prefix)))
  (let loop ([lo 0] [hi n])
    (if (>= lo hi)
        lo
        (let ([mid (quotient (+ lo hi 1) 2)])
          (if (<= (vector-ref prefix mid) slot-index)
              (loop mid hi)
              (loop lo (sub1 mid)))))))

;; ── 折行 ──
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

(define (ensure-wrap! line w)
  (unless (and (output-line-wrap-cache line)
               (= (output-line-wrap-w line) w))
    (set-output-line-wrap-cache! line (wrap-text (output-line-text line) w))
    (set-output-line-wrap-w! line w)))

;; ── 追加 ──
(define (enforce-max! m)
  (define max (output-model-max-lines m))
  (when max
    (define cnt (output-model-count m))
    (when (> cnt max)
      (define excess (- cnt max))
      (define ls (output-model-lines m))
      (vector-copy! ls 0 ls excess cnt)
      (for ([i (in-range (- cnt excess) cnt)])
        (vector-set! ls i (output-line "" #f 0 #f)))
      (set-output-model-count! m (- cnt excess)))))

(define (output-model-put-char! m ch)
  (define cnt (output-model-count m))
  (define ls (output-model-lines m))
  (define last (vector-ref ls (sub1 cnt)))
  (set-output-line-wrap-cache! last #f)
  (if (char=? ch #\newline)
      (begin
        (when (>= cnt (output-model-cap m))
          (grow! m) (set! ls (output-model-lines m)))
        (vector-set! ls cnt (output-line "" #f 0 #f))
        (set-output-model-count! m (add1 cnt))
        (enforce-max! m))
      (set-output-line-text! last
        (string-append (output-line-text last) (string ch)))))

(define (output-model-put-string! m str)
  (for ([ch (in-string str)]) (output-model-put-char! m ch)))

(define (output-model-clear! m)
  (define ls (output-model-lines m))
  (for ([i (in-range (output-model-count m))])
    (vector-set! ls i (output-line "" #f 0 #f)))
  (vector-set! ls 0 (output-line "" #f 0 #f))
  (set-output-model-count! m 1))

;; ── 折叠 ──
(define (output-model-toggle-fold! m idx)
  (when (< idx (output-model-count m))
    (define l (vector-ref (output-model-lines m) idx))
    (set-output-line-folded! l (not (output-line-folded l)))))

;; ── 渲染辅助 ──
(define (output-model-render-slots model w scroll-y h)
  (define ls (output-model-lines model))
  (define n (output-model-count model))
  (define p (compute-prefix-sum model w))
  (define total (vector-ref p n))
  (define sy (max 0 (min scroll-y (max 0 (- total h)))))
  (define-values (slots li) (extract-visible-slots model p sy h))
  (values slots total sy))

(define (extract-visible-slots model prefix sy h)
  (define ls (output-model-lines model))
  (define n (output-model-count model))
  (define start-li (prefix-find prefix sy))
  (define off (- sy (vector-ref prefix start-li)))
  (let iter ([li start-li] [rem h] [acc '()])
    (cond [(or (zero? rem) (>= li n)) (values (reverse acc) li)]
          [else
           (define line (vector-ref ls li))
           (if (output-line-folded line)
               (iter (add1 li) rem acc)
               (let* ([wrapped (output-line-wrap-cache line)]
                      [start (if (= li start-li) off 0)]
                      [take (min rem (- (length wrapped) start))])
                 (let collect ([j start] [end (+ start take)] [a acc])
                   (if (>= j end)
                       (iter (add1 li) (- rem take) a)
                       (collect (add1 j) end
                                (cons (list-ref wrapped j) a))))))])))
