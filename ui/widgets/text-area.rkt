#lang racket

;; text-area — 声明式多行文本输入框
;;
;; (text-area #:value "line1\nline2"
;;            #:on-change (λ (t) (list 'input t))
;;            #:on-submit (λ (t) (list 'submit t))
;;            #:style 'input-focus
;;            #:nofocus-style 'input-normal
;;            #:placeholder "..."
;;            #:key #f)
;;
;; - 文本在 app state；光标 + pref-col 是 keyed local state（需 #:key）
;; - 编辑用纯字符串操作；Escape 插入换行；↑↓ 含 pref-col 列记忆
;; - 垂直 + 水平滚动保证光标可见

(require "../widget.rkt"
         "../surface.rkt"
         "../../base/io/input.rkt")

(provide text-area)

(define (text-area #:value [value ""]
                   #:on-change [on-change (λ (t) #f)]
                   #:on-submit [on-submit (λ (t) #f)]
                   #:style [style 'input-focus]
                   #:nofocus-style [nofocus-style 'input-normal]
                   #:placeholder [placeholder ""]
                   #:key [key #f])
  (leaf #:key key
        #:local (λ () (cons (string-length value) #f))  ; (cursor . pref-col)
        #:focusable? #t
        #:render
        (λ (w rect ctx surf)
          (render-ta value (cursor ctx value) (pref ctx)
                     (focused? ctx w) style nofocus-style placeholder rect surf))
        #:on-event
        (λ (w type data rect ctx)
          (ta-event value on-change on-submit rect ctx type data))))

;; ── 局部状态 ──

(define (cursor ctx value)
  (let ([l (hash-ref ctx 'local #f)])
    (min (if (pair? l) (car l) 0) (string-length value))))

(define (pref ctx)
  (let ([l (hash-ref ctx 'local #f)])
    (and (pair? l) (cdr l))))

(define (set-local! ctx pos pref)
  ((hash-ref ctx 'set-local!) (cons pos pref)))

(define (focused? ctx w)
  (equal? (hash-ref ctx 'focus-key #f) (widget-key w)))

(define (clamp v lo hi) (max lo (min v hi)))

;; ── 行查询（纯字符串）──

(define (line-starts s)
  (let loop ([p 0] [acc '(0)])
    (if (>= p (string-length s))
        (reverse acc)
        (if (char=? (string-ref s p) #\newline)
            (loop (add1 p) (cons (add1 p) acc))
            (loop (add1 p) acc)))))

(define (pos->line-index starts pos)
  (define n (length starts))
  (let loop ([i 0])
    (if (>= i (sub1 n)) i
        (if (< pos (list-ref starts (add1 i))) i (loop (add1 i))))))

(define (line-of s pos)
  (for/sum ([i (in-range (min pos (string-length s)))]
            #:when (char=? (string-ref s i) #\newline))
    1))

(define (line-start s pos)
  (let loop ([p (sub1 pos)])
    (if (or (< p 0) (char=? (string-ref s p) #\newline))
        (add1 p)
        (loop (sub1 p)))))

(define (line-end s pos)
  (let loop ([p pos])
    (cond [(>= p (string-length s)) (string-length s)]
          [(char=? (string-ref s p) #\newline) p]
          [else (loop (add1 p))])))

(define (line-col s pos) (- pos (line-start s pos)))

;; 上下移动（含 pref-col 记忆）
(define (move-vertical s pos pref-col dir)
  (define starts (line-starts s))
  (define li (pos->line-index starts pos))
  (define ti (+ li dir))
  (cond
    [(or (< ti 0) (>= ti (length starts))) pos]
    [else
     (define cur-col (or pref-col (- pos (list-ref starts li))))
     (define tstart (list-ref starts ti))
     (define tend (if (< (add1 ti) (length starts))
                      (list-ref starts (add1 ti))
                      (string-length s)))
     (define raw-len (- tend tstart))
     (define tlen (if (and (> raw-len 0)
                           (< tend (string-length s))
                           (char=? (string-ref s (sub1 tend)) #\newline))
                      (sub1 raw-len)
                      raw-len))
     (+ tstart (min cur-col tlen))]))

;; ── 编辑 ──

(define (insert! value cur ctx on-change s)
  (define new (string-append (substring value 0 cur) s (substring value cur)))
  (set-local! ctx (+ cur (string-length s)) (line-col new (+ cur (string-length s))))
  (on-change new))

(define (backspace! value cur ctx on-change)
  (when (> cur 0)
    (define new (string-append (substring value 0 (sub1 cur)) (substring value cur)))
    (set-local! ctx (sub1 cur) (line-col new (sub1 cur)))
    (on-change new)))

(define (delete! value cur ctx on-change)
  (when (< cur (string-length value))
    (define new (string-append (substring value 0 cur) (substring value (add1 cur))))
    (set-local! ctx cur (line-col new cur))
    (on-change new)))

;; ── 事件 ──

(define (ta-event value on-change on-submit rect ctx type data)
  (match-let ([(list x y w h) rect])
    (define cur (cursor ctx value))
    (define len (string-length value))
    (cond
      [(eq? type 'enter) (on-submit value)]
      [(memq type '(escape alt-enter)) (insert! value cur ctx on-change "\n")]
      [(eq? type 'backspace) (backspace! value cur ctx on-change)]
      [(eq? type 'delete) (delete! value cur ctx on-change)]
      [(eq? type 'space) (insert! value cur ctx on-change " ")]
      [(char? type) (insert! value cur ctx on-change (string type))]
      [(eq? type 'left)  (move-h! value cur ctx (max 0 (sub1 cur))) #f]
      [(eq? type 'right) (move-h! value cur ctx (min len (add1 cur))) #f]
      [(eq? type 'home)  (move-h! value cur ctx (line-start value cur)) #f]
      [(eq? type 'end)   (move-h! value cur ctx (line-end value cur)) #f]
      [(eq? type 'up)   (vertical! value cur ctx -1)]
      [(eq? type 'down) (vertical! value cur ctx +1)]
      [(eq? type 'mouse)
       (and (mouse-press? data) (mouse-set value rect (mouse-x data) (mouse-y data) ctx))]
      [else #f])))

(define (move-h! value cur ctx new-pos)
  (set-local! ctx new-pos (line-col value new-pos)))

(define (vertical! value cur ctx dir)
  (define target-col (or (pref ctx) (line-col value cur)))
  (set-local! ctx (move-vertical value cur target-col dir) target-col)
  #f)

(define (mouse-set value rect mx my ctx)
  (match-let ([(list x y w h) rect])
    (define len (string-length value))
    (define cur (cursor ctx value))
    (define starts (line-starts value))
    (define li (clamp (+ (pos->line-index starts cur) (- my y)) 0 (sub1 (length starts))))
    (define tstart (list-ref starts li))
    (define tend (if (< (add1 li) (length starts)) (list-ref starts (add1 li)) len))
    (define tlen (if (and (> (- tend tstart) 0)
                          (< tend len)
                          (char=? (string-ref value (sub1 tend)) #\newline))
                     (sub1 (- tend tstart))
                     (- tend tstart)))
    (define col (clamp (- mx x) 0 tlen))
    (set-local! ctx (+ tstart col) col)
    #f))

;; ── 渲染 ──

(define (render-ta value cursor pref focused? style nofocus-style placeholder rect surf)
  (match-let ([(list x y w h) rect])
    (when (and (> w 0) (> h 0))
      (define st (if focused? style nofocus-style))
      (for ([r (in-range h)])
        (surface-put-string! surf (+ y r) x (make-string w #\space) st))

      (define len (string-length value))
      (define cur (min cursor len))
      (define lines (regexp-split #rx"\n" value))
      (define cur-line (line-of value cur))
      (define cur-col (line-col value cur))

      ;; 滚动（垂直 + 水平，光标驱动）
      (define max-sy (max 0 (- (length lines) h)))
      (define sy (if (< cur-line h) 0 (min (- cur-line (sub1 h)) max-sy)))
      (define sx (if (< cur-col w) 0 (- cur-col (sub1 w))))

      ;; 可见行
      (for ([r (in-range h)])
        (define li (+ sy r))
        (when (< li (length lines))
          (define line (list-ref lines li))
          (define clip (substring line sx (min (string-length line) (+ sx w))))
          (surface-put-string! surf (+ y r) x clip st)))

      ;; 空 + 未聚焦 → placeholder
      (when (and (zero? len) (positive? (string-length placeholder)) (not focused?))
        (surface-put-string! surf y x
          (if (> (string-length placeholder) w) (substring placeholder 0 w) placeholder)
          st))

      ;; 光标
      (when (and focused? (>= cur-line sy) (< cur-line (+ sy h)))
        (define ccol (+ x (- cur-col sx)))
        (when (and (>= ccol x) (< ccol (+ x w)))
          (define cch (if (and (< cur len) (not (char=? (string-ref value cur) #\newline)))
                          (string-ref value cur)
                          #\space))
          (surface-put! surf (+ y (- cur-line sy)) ccol cch 'cursor))))))
