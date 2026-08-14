#lang racket

;; ASCII 调试快照 demo — 不进入 raw 模式，纯离线渲染 + 打印
;; 运行: racket ui-demo/ascii-demo.rkt

(require "../ui/main.rkt")

;; ── 小工具：一个文本 leaf ──
(define (fill! surf x y w h style)
  (for ([r (in-range y (+ y h))])
    (surface-put-string! surf r x (make-string w #\space) style)))

(define (text-leaf key str style)
  (leaf #:key key
        #:render (λ (w rect ctx surf)
                   (match-let ([(list x y w h) rect])
                     (fill! surf x y w h style)
                     (surface-put-string! surf y x str style)))))

(define (lines-leaf key lines style)
  (leaf #:key key
        #:render (λ (w rect ctx surf)
                   (match-let ([(list x y w h) rect])
                     (for ([r (in-range h)])
                       (fill! surf x (+ y r) w 1 style))
                     (for ([line (in-list lines)] [r (in-naturals)])
                       (when (< r h)
                         (surface-put-string! surf (+ y r) x line style)))))))

;; ── 渲染辅助 ──
(define (render-widget w rows cols #:focus-key [focus-key #f])
  (define e (resolve w 0 0 cols rows))
  (define rctx (make-render-ctx #:focus-key focus-key
                                #:local-table (make-hasheq)))
  (define surf (make-surface rows cols))
  (render-element! e surf rctx)
  surf)

;; ── 一个典型应用布局 ──
(define app
  (vstack
   (child (text-leaf 'title " Demo App " 'heading) #:min 1 #:max 1)
   (child
    (hstack
     (child (panel (lines-leaf 'files '(" file1.rkt" " file2.rkt" " file3.rkt") 'info)
                   #:title "Files")
            #:weight 1)
     (child (panel (lines-leaf 'log '(" [ok] ready" " [..] waiting") 'info)
                   #:title "Log")
            #:weight 1))
    #:weight 6 #:min 4)
   (child (text-leaf 'input " > command " 'input-focus) #:min 1 #:max 1)
   (child (text-leaf 'footer " q=quit " 'dim) #:min 1 #:max 1)))

(printf "========== 完整布局 (grid) ==========\n")
(display-surface (render-widget app 12 44) #:space-char #\·)

(printf "\n========== plain 模式（只内容） ==========\n")
(display-surface (render-widget app 12 44)
                 #:mode 'plain #:space-char #\·)

(printf "\n========== compact 模式（单行） ==========\n")
(display-surface (render-widget app 12 44)
                 #:mode 'compact #:space-char #\·)

(printf "\n========== min/max 布局尺寸 ==========\n")
(define m
  (vstack
   (child (text-leaf 'a "A" 'info) #:min 1 #:max 1)
   (child (text-leaf 'b "B" 'info) #:weight 2 #:min 3)
   (child (text-leaf 'c "C" 'info) #:weight 1 #:max 2)))
(for ([c (in-list (element-children (resolve m 0 0 20 10)))]
      [k '("a" "b" "c")])
  (printf "  ~a: h=~a\n" k (fourth (element-rect c))))
