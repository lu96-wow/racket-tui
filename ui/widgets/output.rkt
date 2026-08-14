#lang racket

;; output — 声明式可滚动日志面板（支持折叠块 + 长行自动换行）
;;
;; (output #:lines (list "log1"
;;                       (fold-block 'errors (cons "Errors" 'error) (list "e1" "e2"))
;;                       "a very long line ...")
;;         #:folded '()
;;         #:on-toggle-fold (λ (id) msg)
;;         #:style 'info
;;         #:auto-scroll? #t
;;         #:scrollbar-width 1
;;         #:key #f)
;;
;; - 内容在 app state；折叠状态也是 app state
;; - 滚动偏移是 keyed local state（需 #:key）
;; - 长行按内容宽度自动换行（1 字符 = 1 格）
;; - 折叠头换行后只有第一行可点击

(require "../widget.rkt"
         "../surface.rkt"
         "./scrollbar.rkt"
         "../../base/io/input.rkt")

(provide output
         fold-block fold-block? fold-block-id fold-block-header fold-block-body)

(struct fold-block (id header body) #:transparent)

(define (output #:lines [lines '()]
                #:folded [folded '()]
                #:on-toggle-fold [on-toggle-fold (λ (id) #f)]
                #:style [style 'info]
                #:auto-scroll? [auto? #t]
                #:scrollbar-width [bar-w 1]
                #:key [key #f])
  (leaf #:key key
        #:local (λ () (list 0 0 #f))   ; (scroll last-total dragging?)
        #:focusable? #t
        #:render
        (λ (w rect ctx surf)
          (render-output lines folded style auto? bar-w rect ctx surf))
        #:on-event
        (λ (w type data rect ctx)
          (output-event lines folded on-toggle-fold bar-w rect ctx type data))))

;; ── 逻辑行（折叠展开后，未换行）──
(struct vrow (text style block-id header?) #:transparent)

;; ── 显示行（换行后）──
;; block-id 非 #f 表示这一显示行是折叠头（可点击）
(struct drow (text style block-id) #:transparent)

(define (line->text-style l)
  (cond
    [(string? l) (cons l #f)]
    [(and (pair? l) (string? (car l))) (cons (car l) (cdr l))]
    [else (cons (~a l) #f)]))

(define (flatten-lines lines folded)
  (apply append (map (λ (l) (flatten-line l folded)) lines)))

(define (flatten-line l folded)
  (cond
    [(fold-block? l)
     (define id (fold-block-id l))
     (define folded? (member id folded))
     (define hdr (line->text-style (fold-block-header l)))
     (define title (if folded?
                       (string-append "▶ " (car hdr))
                       (string-append "▼ " (car hdr))))
     (cons (vrow title (cdr hdr) id #t)
           (if folded? '() (flatten-lines (fold-block-body l) folded)))]
    [else
     (define ts (line->text-style l))
     (list (vrow (car ts) (cdr ts) #f #f))]))

;; 按字符换行（1 字符 = 1 格）
(define (wrap-line text cw)
  (define len (string-length text))
  (cond
    [(zero? len) (list "")]
    [else
     (let loop ([pos 0] [acc '()])
       (cond
         [(>= pos len) (reverse acc)]
         [else
          (define end (min (+ pos cw) len))
          (loop end (cons (substring text pos end) acc))]))]))

(define (display-rows lines folded cw)
  (apply append
         (map (λ (r) (wrap-vrow r cw))
              (flatten-lines lines folded))))

(define (wrap-vrow r cw)
  (define chunks (wrap-line (vrow-text r) cw))
  (for/list ([ch (in-list chunks)] [i (in-naturals)])
    (drow ch (vrow-style r) (and (= i 0) (vrow-block-id r)))))

;; ── 局部状态 ──

(define (out-scroll ctx)     (let ([l (hash-ref ctx 'local #f)]) (if (pair? l) (car l) 0)))
(define (out-last-total ctx) (let ([l (hash-ref ctx 'local #f)]) (if (and (pair? l) (pair? (cdr l))) (cadr l) 0)))
(define (out-dragging? ctx)  (let ([l (hash-ref ctx 'local #f)]) (and (pair? l) (pair? (cdr l)) (pair? (cddr l)) (caddr l))))

(define (out-set! ctx scroll last-total dragging?)
  ((hash-ref ctx 'set-local!) (list scroll last-total dragging?)))

(define (clamp v lo hi) (max lo (min v hi)))

;; ── 渲染 ──

(define (render-output lines folded style auto? bar-w rect ctx surf)
  (match-let ([(list x y w h) rect])
    (when (and (> w 0) (> h 0))
      (define cw (max 1 (- w bar-w)))
      (define rows (display-rows lines folded cw))
      (define total (length rows))
      (define last-total (out-last-total ctx))
      (define scroll (out-scroll ctx))
      (define sy
        (if (and auto? (not (= total last-total)))
            (max 0 (- total h))
            (clamp scroll 0 (max 0 (- total h)))))

      (for ([r (in-range h)])
        (surface-put-string! surf (+ y r) x (make-string w #\space) style))

      (for ([r (in-range h)])
        (define i (+ sy r))
        (when (< i total)
          (define row (list-ref rows i))
          (surface-put-string! surf (+ y r) x
            (drow-text row) (or (drow-style row) style))))

      (out-set! ctx sy total (out-dragging? ctx))

      (when (> total h)
        (scrollbar-render surf (+ x cw) y bar-w h total sy)))))

;; ── 事件 ──

(define (output-event lines folded on-toggle-fold bar-w rect ctx type data)
  (match-let ([(list x y w h) rect])
    (define cw (max 1 (- w bar-w)))
    (define rows (display-rows lines folded cw))
    (define total (length rows))
    (define max-scroll (max 0 (- total h)))
    (define scroll (out-scroll ctx))
    (cond
      [(eq? type 'up)       (out-set! ctx (clamp (sub1 scroll) 0 max-scroll) total #f) #f]
      [(eq? type 'down)     (out-set! ctx (clamp (add1 scroll) 0 max-scroll) total #f) #f]
      [(eq? type 'pageup)   (out-set! ctx (clamp (- scroll h) 0 max-scroll) total #f) #f]
      [(eq? type 'pagedown) (out-set! ctx (clamp (+ scroll h) 0 max-scroll) total #f) #f]
      [(eq? type 'home)     (out-set! ctx 0 total #f) #f]
      [(eq? type 'end)      (out-set! ctx max-scroll total #f) #f]
      [(eq? type 'mouse)    (output-mouse rows on-toggle-fold bar-w rect ctx type data)]
      [else #f])))

(define (output-mouse rows on-toggle-fold bar-w rect ctx type data)
  (match-let ([(list x y w h) rect])
    (define total (length rows))
    (define max-scroll (max 0 (- total h)))
    (define cw (max 1 (- w bar-w)))
    (define bar-col (+ x cw))
    (cond
      [(mouse-press? data)
       (define mx (mouse-x data)) (define my (mouse-y data))
       (cond
         [(and (>= mx bar-col) (< mx (+ x w)))
          (out-set! ctx (scrollbar-scroll-from-y my y h total) total #t)
          #f]
         [else
          (define i (+ (out-scroll ctx) (- my y)))
          (when (and (>= i 0) (< i total))
            (define row (list-ref rows i))
            (define bid (drow-block-id row))
            (when bid (on-toggle-fold bid)))])]

      [(mouse-move? data)
       (when (out-dragging? ctx)
         (out-set! ctx (scrollbar-scroll-from-y (mouse-y data) y h total) total #t)
         #f)]

      [(mouse-release? data)
       (out-set! ctx (out-scroll ctx) total #f)
       #f]

      [(mouse-scroll? data)
       (define dir (caddr data))
       (define delta (if (eq? dir 'up) -3 3))
       (out-set! ctx (clamp (+ (out-scroll ctx) delta) 0 max-scroll) total #f)
       #f]

      [else #f])))
