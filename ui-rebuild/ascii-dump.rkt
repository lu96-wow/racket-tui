#lang racket

;; ═══════════════════════════════════════════════════════════════════════════
;; ascii-dump.rkt — 把 surface（格点缓冲）渲染成可读、可 diff 的 ASCII 描述
;;
;; 用途：调试布局/渲染、单元测试断言（无需真实终端）、帧间 diff。
;;
;; 输出示例（#:mode 'grid）：
;;
;;   Legend (2 styles + default):
;;     . default
;;     A info
;;     B selection
;;
;;   style: AAAAA.....
;;   text : HELLO.....
;;   style: BBBBB.....
;;   text : world.....
;;
;; 说明：
;;   - 每个样式分配一个单字符标签；#f（默认）永远用 '.'
;;   - 'grid 模式每行输出两行（style: / text :），等宽、可对齐 diff
;;   - 'plain 模式只输出字符行；'compact 模式每行合并为 "text ║ style"
;;
;; 限制：当前按"1 格 = 1 字符"处理；宽字符（CJK）会使 text 行视觉变宽。
;; ═══════════════════════════════════════════════════════════════════════════

(require "surface.rkt"
         "../base/io/output-color.rkt")

(provide surface->ascii display-surface)

(define tag-chars
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")

(define (tag-at i)
  (if (< i (string-length tag-chars))
      (string-ref tag-chars i)
      #\?))

;; ── 样式收集 & 标签映射 ──

(define (collect-styles surf)
  (define seen (make-hasheq))
  (define styles '())
  (for* ([r (in-range (surface-rows surf))]
         [c (in-range (surface-cols surf))])
    (define st (cell-style (surface-ref surf r c)))
    (when (and st (not (hash-ref seen st #f)))
      (hash-set! seen st #t)
      (set! styles (cons st styles))))
  (reverse styles))

(define (order-styles styles legend-order)
  (case legend-order
    [(sorted)    (sort styles (λ (a b) (string<? (~a a) (~a b))))]
    [(first-use) styles]
    [else (error 'surface->ascii "bad #:legend-order: ~a" legend-order)]))

(define (make-tag-map ordered)
  (define m (make-hasheq))
  (for ([st (in-list ordered)] [i (in-naturals)])
    (hash-set! m st (tag-at i)))
  m)

;; ── 行渲染 ──

(define (dump-char ch space-char)
  (cond
    [(char=? ch #\space) space-char]
    [(or (< (char->integer ch) 32) (= (char->integer ch) 127)) #\·]
    [else ch]))

(define (style-row surf tag-map r)
  (list->string
   (for/list ([c (in-range (surface-cols surf))])
     (hash-ref tag-map (cell-style (surface-ref surf r c)) #\.))))

(define (text-row surf r space-char)
  (list->string
   (for/list ([c (in-range (surface-cols surf))])
     (dump-char (cell-ch (surface-ref surf r c)) space-char))))

;; ── 图例 ──

(define (style-count surf st)
  (for*/sum ([r (in-range (surface-rows surf))]
             [c (in-range (surface-cols surf))]
             #:when (equal? (cell-style (surface-ref surf r c)) st))
    1))

(define (sgr-string st)
  (define bs (style->bytes st))
  (if (zero? (bytes-length bs)) "" (format " ~v" bs)))

(define (legend-lines surf tag-map styles stats? show-sgr?)
  (define header (format "Legend (~a styles + default):" (length styles)))
  (define default-entry
    (format "  . default~a"
            (if stats? (format " (~a cells)" (style-count surf #f)) "")))
  (define style-entries
    (for/list ([st (in-list styles)])
      (format "  ~a ~a~a~a"
              (hash-ref tag-map st)
              (~a st)
              (if stats? (format " (~a cells)" (style-count surf st)) "")
              (if show-sgr? (sgr-string st) ""))))
  (cons header (cons default-entry style-entries)))

;; ── 主入口 ──

(define (surface->ascii surf
                        #:mode        [mode 'grid]
                        #:legend-order [legend-order 'sorted]
                        #:space-char  [space-char #\space]
                        #:show-sgr?   [show-sgr? #f]
                        #:stats?      [stats? #f])
  (define styles (collect-styles surf))
  (define ordered (order-styles styles legend-order))
  (define tag-map (make-tag-map ordered))

  (define legend
    (if (eq? mode 'plain)
        '()
        (legend-lines surf tag-map ordered stats? show-sgr?)))

  (define rows
    (case mode
      [(plain)
       (for/list ([r (in-range (surface-rows surf))])
         (text-row surf r space-char))]
      [(grid)
       (append-map
        (λ (r) (list (string-append "style: " (style-row surf tag-map r))
                     (string-append "text : " (text-row surf r space-char))))
        (range (surface-rows surf)))]
      [(compact)
       (for/list ([r (in-range (surface-rows surf))])
         (string-append (text-row surf r space-char)
                        " ║ "
                        (style-row surf tag-map r)))]
      [else (error 'surface->ascii "bad #:mode: ~a" mode)]))

  (string-join (append legend rows) "\n"))

(define (display-surface surf
                         #:mode         [mode 'grid]
                         #:legend-order [legend-order 'sorted]
                         #:space-char   [space-char #\space]
                         #:show-sgr?    [show-sgr? #f]
                         #:stats?       [stats? #f])
  (displayln (surface->ascii surf
                             #:mode mode
                             #:legend-order legend-order
                             #:space-char space-char
                             #:show-sgr? show-sgr?
                             #:stats? stats?)))
