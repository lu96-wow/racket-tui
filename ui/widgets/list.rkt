#lang racket

;; list — 声明式可滚动列表（带滚动条）
;;
;; (list-box #:items '("a" "b" "c")
;;           #:selected 0
;;           #:on-select (λ (i) (list 'select i))
;;           #:style 'info
;;           #:selected-style 'selection
;;           #:key #f)
;;
;; - 选中索引在 app state（#:selected + #:on-select 消息）
;; - 滚动偏移是 keyed local state（需 #:key，否则跨帧丢失）
;; - 滚动条拖拽依赖框架的鼠标捕获（press→move→release）

(require "../widget.rkt"
         "../surface.rkt"
         "./scrollbar.rkt"
         "../../base/io/input.rkt")

(provide list-box)

(define (list-box #:items [items '()]
                  #:selected [selected #f]
                  #:on-select [on-select (λ (i) #f)]
                  #:style [style 'info]
                  #:selected-style [selected-style 'selection]
                  #:scrollbar-width [bar-w 1]
                  #:key [key #f])
  (leaf #:key key
        #:local (λ () (list 0 #f))   ; (scroll dragging?)
        #:focusable? #t
        #:render
        (λ (w rect ctx surf)
          (render-list items selected style selected-style bar-w rect ctx surf))
        #:on-event
        (λ (w type data rect ctx)
          (list-event items selected on-select style selected-style bar-w rect ctx type data))))

;; ── 局部状态访问 ──

(define (local-scroll ctx)
  (let ([l (hash-ref ctx 'local #f)])
    (if (and (pair? l) (number? (car l))) (car l) 0)))

(define (local-dragging? ctx)
  (let ([l (hash-ref ctx 'local #f)])
    (and (pair? l) (cadr l))))

(define (set-local! ctx scroll dragging?)
  ((hash-ref ctx 'set-local!) (list scroll dragging?)))

(define (clamp v lo hi) (max lo (min v hi)))

(define (truncate s w)
  (if (> (string-length s) w) (substring s 0 w) s))

;; 保证 index 可见，返回新 scroll
(define (scroll-to-show scroll index h)
  (cond [(< index scroll) index]
        [(>= index (+ scroll h)) (add1 (- index h))]
        [else scroll]))

;; ── 渲染 ──

(define (render-list items selected style selected-style bar-w rect ctx surf)
  (match-let ([(list x y w h) rect])
    (when (and (> w 0) (> h 0))
      (define total (length items))
      (define cw (max 1 (- w bar-w)))
      (define sy (clamp (local-scroll ctx) 0 (max 0 (- total h))))

      ;; 背景
      (for ([r (in-range h)])
        (surface-put-string! surf (+ y r) x (make-string w #\space) style))

      ;; 可见项（选中行整行高亮）
      (for ([r (in-range h)])
        (define i (+ sy r))
        (when (< i total)
          (define st (if (equal? i selected) selected-style style))
          (when (equal? i selected)
            (surface-put-string! surf (+ y r) x (make-string cw #\space) st))
          (define item (list-ref items i))
          (surface-put-string! surf (+ y r) x
            (truncate (if (string? item) item (~a item)) cw) st)))

      ;; 滚动条
      (when (> total h)
        (scrollbar-render surf (+ x cw) y bar-w h total sy)))))

;; ── 事件 ──

(define (list-event items selected on-select style selected-style bar-w rect ctx type data)
  (match-let ([(list x y w h) rect])
    (define total (length items))
    (define cw (max 1 (- w bar-w)))
    (define scroll (local-scroll ctx))
    (define max-scroll (max 0 (- total h)))
    (cond
      ;; 键盘：移动选中项
      [(eq? type 'up)    (move-selection! items selected -1 h ctx on-select)]
      [(eq? type 'down)  (move-selection! items selected +1 h ctx on-select)]
      [(eq? type 'pageup)
       (move-selection! items selected (- (max 1 h)) h ctx on-select)]
      [(eq? type 'pagedown)
       (move-selection! items selected (max 1 h) h ctx on-select)]
      [(eq? type 'home)  (when (positive? total) (select! 0 h ctx on-select))]
      [(eq? type 'end)   (when (positive? total) (select! (sub1 total) h ctx on-select))]

      [(eq? type 'mouse)
       (list-mouse items selected on-select bar-w rect ctx type data)]

      [else #f])))

(define (select! idx h ctx on-select)
  (set-local! ctx (scroll-to-show (local-scroll ctx) idx h) #f)
  (on-select idx))

(define (move-selection! items selected delta h ctx on-select)
  (define total (length items))
  (when (positive? total)
    (define new-idx (clamp (+ (or selected 0) delta) 0 (sub1 total)))
    (select! new-idx h ctx on-select)))

(define (list-mouse items selected on-select bar-w rect ctx type data)
  (match-let ([(list x y w h) rect])
    (define total (length items))
    (define cw (max 1 (- w bar-w)))
    (define bar-col (+ x cw))
    (cond
      [(mouse-press? data)
       (define mx (mouse-x data)) (define my (mouse-y data))
       (cond
         [(and (>= mx bar-col) (< mx (+ x w)))
          ;; 滚动条拖拽开始
          (define new-scroll (scrollbar-scroll-from-y my y h total))
          (set-local! ctx new-scroll #t)
          #f]
         [else
          ;; 点击列表项 → 选中
          (define idx (+ (local-scroll ctx) (- my y)))
          (when (and (>= idx 0) (< idx total))
            (set-local! ctx (local-scroll ctx) #f)
            (on-select idx))])]

      [(mouse-move? data)
       (when (local-dragging? ctx)
         (define new-scroll (scrollbar-scroll-from-y (mouse-y data) y h total))
         (set-local! ctx new-scroll #t)
         #f)]

      [(mouse-release? data)
       (set-local! ctx (local-scroll ctx) #f)
       #f]

      [(mouse-scroll? data)
       (define dir (caddr data))
       (define delta (if (eq? dir 'up) -3 3))
       (define new-scroll (clamp (+ (local-scroll ctx) delta) 0 (max 0 (- total h))))
       (set-local! ctx new-scroll #f)
       #f]

      [else #f])))
