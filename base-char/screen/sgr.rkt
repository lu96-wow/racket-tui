#lang racket

;; SGR 参数 → grid 属性（供 ansi 解析器与 op 路径共用，避免两份实现漂移）

(require "grid.rkt")

(provide apply-sgr! read-extended-color)

(define (apply-sgr! g ps)
  (let loop ([ps ps])
    (cond
      [(null? ps) (void)]
      [else
       (define v (or (car ps) 0))
       (define rest (cdr ps))
       (cond
         [(= v 0) (set-grid-fg! g #f) (set-grid-bg! g #f) (set-grid-attrs! g '()) (loop rest)]
         [(= v 1) (grid-add-attr! g 'bold) (loop rest)]
         [(= v 2) (grid-add-attr! g 'dim) (loop rest)]
         [(= v 3) (grid-add-attr! g 'italic) (loop rest)]
         [(= v 4) (grid-add-attr! g 'underline) (loop rest)]
         [(= v 5) (grid-add-attr! g 'blink) (loop rest)]
         [(= v 7) (grid-add-attr! g 'reverse) (loop rest)]
         [(= v 22) (grid-remove-attr! g 'bold) (grid-remove-attr! g 'dim) (loop rest)]
         [(= v 23) (grid-remove-attr! g 'italic) (loop rest)]
         [(= v 24) (grid-remove-attr! g 'underline) (loop rest)]
         [(= v 25) (grid-remove-attr! g 'blink) (loop rest)]
         [(= v 27) (grid-remove-attr! g 'reverse) (loop rest)]
         [(= v 39) (set-grid-fg! g #f) (loop rest)]
         [(= v 49) (set-grid-bg! g #f) (loop rest)]
         [(and (>= v 30) (<= v 37)) (set-grid-fg! g (list 'idx (- v 30))) (loop rest)]
         [(and (>= v 90) (<= v 97)) (set-grid-fg! g (list 'idx (+ 8 (- v 90)))) (loop rest)]
         [(and (>= v 40) (<= v 47)) (set-grid-bg! g (list 'idx (- v 40))) (loop rest)]
         [(and (>= v 100) (<= v 107)) (set-grid-bg! g (list 'idx (+ 8 (- v 100)))) (loop rest)]
         [(= v 38)
          (define-values (color rest*) (read-extended-color rest))
          (when color (set-grid-fg! g color))
          (loop rest*)]
         [(= v 48)
          (define-values (color rest*) (read-extended-color rest))
          (when color (set-grid-bg! g color))
          (loop rest*)]
         [else (loop rest)])])))

;; 38/48 之后的扩展色：5;n（256 色）或 2;r;g;b（真彩）
(define (read-extended-color ps)
  (cond
    [(and (pair? ps) (eqv? (car ps) 5) (pair? (cdr ps)))
     (values (list 'idx (or (cadr ps) 0)) (cddr ps))]
    [(and (pair? ps) (eqv? (car ps) 2) (>= (length ps) 4))
     (values (list 'rgb (or (cadr ps) 0) (or (caddr ps) 0) (or (cadddr ps) 0))
             (cddddr ps))]
    [else (values #f (if (pair? ps) (cdr ps) '()))]))
