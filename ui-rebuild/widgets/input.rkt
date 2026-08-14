#lang racket

;; input — 声明式单行文本输入框
;;
;; (input #:value "hello"                       ; 当前文本（来自 app state）
;;        #:on-change (λ (t) (list 'input t))   ; 编辑时产生消息（新文本）
;;        #:on-submit (λ (t) (list 'submit t))  ; Enter 时产生消息
;;        #:style 'input-focus
;;        #:nofocus-style 'input-normal
;;        #:placeholder "..."
;;        #:key #f)
;;
;; 文本在 app state（单一数据源）；光标位置是 keyed local state（需 #:key）。
;; 编辑用纯字符串操作计算新文本，不持有可变 buffer。

(require "../widget.rkt"
         "../surface.rkt"
         "../../base/io/input.rkt")

(provide input)

(define (input #:value      [value ""]
               #:on-change  [on-change (λ (t) #f)]
               #:on-submit  [on-submit (λ (t) #f)]
               #:style      [style 'input-focus]
               #:nofocus-style [nofocus-style 'input-normal]
               #:placeholder [placeholder ""]
               #:key        [key #f])
  (leaf #:key key
        #:local (λ () (string-length value))
        #:focusable? #t
        #:render
        (λ (w rect ctx surf)
          (render-input value
                        (cursor-value ctx value)
                        (focused? ctx w)
                        style nofocus-style placeholder rect surf))
        #:on-event
        (λ (w type data rect ctx)
          (define cur (cursor-value ctx value))
          (cond
            [(eq? type 'enter) (on-submit value)]
            [(eq? type 'backspace) (edit-backspace value cur ctx on-change)]
            [(eq? type 'delete)    (edit-delete value cur ctx on-change)]
            [(eq? type 'left)  (move! ctx (max 0 (sub1 cur))) #f]
            [(eq? type 'right) (move! ctx (min (string-length value) (add1 cur))) #f]
            [(eq? type 'home)  (move! ctx 0) #f]
            [(eq? type 'end)   (move! ctx (string-length value)) #f]
            [(eq? type 'space) (insert! value cur " " ctx on-change)]
            [(char? type)      (insert! value cur (string type) ctx on-change)]
            [(eq? type 'mouse)
             (and (mouse-press? data)
                  (mouse-set-cursor value rect (mouse-x data) ctx))]
            [else #f]))))

;; ── 编辑（纯字符串操作 + 更新光标 local state）──

(define (cursor-value ctx value)
  (min (hash-ref ctx 'local 0) (string-length value)))

(define (move! ctx new-cur)
  ((hash-ref ctx 'set-local!) new-cur))

(define (insert! value cur s ctx on-change)
  (define new-text
    (string-append (substring value 0 cur) s (substring value cur)))
  ((hash-ref ctx 'set-local!) (+ cur (string-length s)))
  (on-change new-text))

(define (edit-backspace value cur ctx on-change)
  (when (> cur 0)
    (define new-text
      (string-append (substring value 0 (sub1 cur)) (substring value cur)))
    ((hash-ref ctx 'set-local!) (sub1 cur))
    (on-change new-text)))

(define (edit-delete value cur ctx on-change)
  (when (< cur (string-length value))
    (define new-text
      (string-append (substring value 0 cur) (substring value (add1 cur))))
    ((hash-ref ctx 'set-local!) cur)
    (on-change new-text)))

(define (mouse-set-cursor value rect mx ctx)
  (match-let ([(list x y w h) rect])
    (define cur (cursor-value ctx value))
    (define scroll (if (< cur w) 0 (- cur (sub1 w))))
    (define new-cur (min (string-length value) (+ scroll (- mx x))))
    ((hash-ref ctx 'set-local!) new-cur)
    #f))

(define (focused? ctx w)
  (equal? (hash-ref ctx 'focus-key #f) (widget-key w)))

;; ── 渲染 ──

(define (render-input value cursor focused? style nofocus-style placeholder rect surf)
  (match-let ([(list x y w h) rect])
    (when (and (> w 0) (> h 0))
      (define st (if focused? style nofocus-style))
      (for ([r (in-range h)])
        (surface-put-string! surf (+ y r) x (make-string w #\space) st))

      (define len (string-length value))
      (define cur (min cursor len))
      ;; 水平滚动：保证光标可见
      (define scroll (if (< cur w) 0 (- cur (sub1 w))))
      (define visible (substring value scroll (min len (+ scroll w))))
      (define display
        (cond
          [(and (zero? len) (positive? (string-length placeholder)) (not focused?))
           (let ([p placeholder])
             (if (> (string-length p) w) (substring p 0 w) p))]
          [else visible]))

      (surface-put-string! surf y x display st)

      ;; 光标（高亮光标处字符；末尾则高亮空格）
      (when (and focused? (>= (- cur scroll) 0) (< (- cur scroll) w))
        (define ccol (+ x (- cur scroll)))
        (define cch (if (< cur len) (string-ref value cur) #\space))
        (surface-put! surf y ccol cch 'cursor)))))
