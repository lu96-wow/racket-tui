#lang racket

;; ═══════════════════════════════════════════════════════════════════════════
;; layout.rkt
;;
;;   space   = '---  空白占位
;;
;;   (layout-row (thing w) ...)  → layout   垂直
;;   (layout-col (thing w) ...)  → layout   水平
;;   (border inner ...) → layout   套边框，内缩 (1,1,-2,-2)
;;   (screen (thing w) ...) → spec-list   填终端
;;
;;   算法: max(1, floor(span × w / sum))  当 w > 0
;;         保证 weight>0 的组件至少分到 1 行/列
;; ═══════════════════════════════════════════════════════════════════════════

(require "widgets/border.rkt")

(provide space screen layout-row layout-col border layout? layout-resolve)

(define space '---)

(struct layout (resolve) #:transparent)

;; ═══════════════════════════════════════════════════════════════════════════
;; distribute
;; ═══════════════════════════════════════════════════════════════════════════

(define (distribute dir x y tw th items)
  (define vertical? (eq? dir 'v))
  (define span (if vertical? th tw))
  (define total-weight (apply + (map cdr items)))

  (if (or (zero? total-weight) (null? items))
      '()
      (let loop ([remaining items]
                 [offset (if vertical? y x)]
                 [acc '()])
        (match remaining
          ['() acc]
          [(cons (cons thing weight) rest)
           (define base (quotient (* span weight) total-weight))
           (define size (if (and (zero? base) (> weight 0)) 1 base))
           (define child-specs
             (cond [(layout? thing)
                    (if vertical?
                        ((layout-resolve thing) x offset tw size)
                        ((layout-resolve thing) offset y size th))]
                   [(eq? thing space) '()]
                   [else
                    (list (list thing
                                (if vertical? x offset)
                                (if vertical? offset y)
                                (if vertical? tw size)
                                (if vertical? size th)))]))
           (loop rest
                 (+ offset size)
                 (append acc child-specs))]))))

;; ═══════════════════════════════════════════════════════════════════════════
;; h / v
;; ═══════════════════════════════════════════════════════════════════════════

(define-syntax layout-row
  (syntax-rules ()
    [(_ (thing w) ...)
     (layout (lambda (x y tw th)
            (distribute 'v x y tw th (list (cons thing w) ...))))]))

(define-syntax layout-col
  (syntax-rules ()
    [(_ (thing w) ...)
     (layout (lambda (x y tw th)
            (distribute 'h x y tw th (list (cons thing w) ...))))]))

;; ═══════════════════════════════════════════════════════════════════════════
;; border
;; ═══════════════════════════════════════════════════════════════════════════

(define (border inner
                #:title       [title       #f]
                #:up?         [up?         #t]
                #:down?       [down?       #t]
                #:left?       [left?       #t]
                #:right?      [right?      #t]
                #:up-style    [up-style    'info]
                #:down-style  [down-style  'info]
                #:left-style  [left-style  'info]
                #:right-style [right-style 'info])
  (layout (lambda (x y w h)
         (define iw (max 0 (- w 2)))
         (define ih (max 0 (- h 2)))
         (append
          ((layout-resolve inner) (add1 x) (add1 y) iw ih)
          (list (list (make-border
                       #:title title
                       #:up? up? #:down? down?
                       #:left? left? #:right? right?
                       #:up-style up-style
                       #:down-style down-style
                       #:left-style left-style
                       #:right-style right-style)
                      x y w h))))))

;; ═══════════════════════════════════════════════════════════════════════════
;; screen — 语法上等同于 layout-row; 语义上表示填满终端
;; ═══════════════════════════════════════════════════════════════════════════

(define-syntax screen
  (syntax-rules ()
    [(_ (thing wt) ...)
     (layout-row (thing wt) ...)]))
