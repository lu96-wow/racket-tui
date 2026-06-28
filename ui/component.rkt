#lang racket

(require "../base/io/build-input.rkt"
         "../base/io/output-styles.rkt"
         "../base/io/output-color.rkt"
         "../base/io/output.rkt")

(provide component component?
         component-render component-handler
         component-focusable? component-show?
         component-w component-h
         make-button make-panel)

;; ─── component struct ───
;; render    : (λ (focused? x y w h) → void)   x,y,w,h 0-based, 调度器传入
;; handler   : (λ (type data mods) → void)     build-input 构造
;; focusable?: bool
;; show?     : bool
;; w, h      : natural  组件期望宽高
(struct component (render handler focusable? show? w h) #:transparent)

;; ─── make-button ───
(define (make-button #:text text #:on-activate on-activate)
  (define label (string-append " " text " "))
  (component
   (λ (focused? x y w h)
     (put-styled-at! (+ y 1) (+ x 1)
                     (if focused? 'button-hover 'button)
                     label))
   (build-input #:enter on-activate #:space on-activate)
   #t #t
   (string-length label)
   1))

;; ─── make-panel — 鼠标拖动边缘改变宽度 / 位置 ───
;; xb, yb, wb, hb 都是 box, handler 和 render 共享同一份
(define (make-panel xb yb wb hb #:color [clr 'selection])
  (define drag-edge (box #f))       ;; #f | 'left | 'right
  (define drag-base-right (box 0))  ;; 左边缘拖拽时记录原始右边界

  (define (edge mx x w)
    (cond [(<= (abs (- mx x)) 1)          'left]
          [(<= (abs (- mx (+ x w -1))) 1) 'right]
          [else #f]))

  (component
   (λ (focused? x y w h)
     (for ([i (in-range h)])
       (put-styled-at! (+ y 1 i) (+ x 1) clr (make-string w #\space))))

   (build-input
    #:mouse-press (λ (btn mx my mods)
                    (when (eq? btn 'left)
                      (define x (unbox xb))
                      (define w (unbox wb))
                      (set-box! drag-edge (edge mx x w))
                      (set-box! drag-base-right (+ x w -1))))
    #:mouse-release (λ (btn mx my mods)
                      (set-box! drag-edge #f))
    #:mouse-move (λ (mx my mods)
                   (case (unbox drag-edge)
                     [(left)
                      (define r (unbox drag-base-right))
                      (define new-x (min mx (- r 2)))
                      (set-box! xb new-x)
                      (set-box! wb (+ r 1 (- new-x)))]
                     [(right)
                      (set-box! wb (max 3 (+ mx 1 (- (unbox xb)))))]
                     [else (void)])))
   #t #t
   wb
   hb))
