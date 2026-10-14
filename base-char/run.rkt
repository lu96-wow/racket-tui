#lang racket

;; 有界脚本运行器 —— AI 调试的推荐入口。
;;
;; 给定一串事件，按序处理，每个事件后渲染一次并抓一帧字符图，
;; 脚本跑完即结束。输出帧数有界（≤ 事件数+1），天然不会因为
;; 非阻塞循环而无限输出。

(require "tui.rkt"
         "io/event.rkt"
         "screen/grid.rkt"
         "screen/frame.rkt"
         "screen/history.rkt"
         "screen/session.rkt"
         "screen/render.rkt")

(provide char-run)

;; events : (listof spec)  见 char-input-push!
;; #:handle   : (-> event? any)      处理单个事件（通常更新外部 state）
;; #:render   : (-> any)             绘制到当前网格
;; #:snapshot : (-> string)          抓帧（默认 char-frame）
;; #:stop     : (-> boolean?)        额外提前停止条件
;; #:dedup?   : boolean?             跳过视觉（文本+颜色+属性）与上一帧相同的帧（默认 #t）
;; #:diff?    : boolean?             返回 (首帧 diff ...) 而非全部整帧（默认 #f）
;; #:styles?  : boolean?             #:diff? 时把样式（颜色/属性）变化也写进 diff（默认 #f）
(define (char-run events
                  #:handle [handle void]
                  #:render [render void]
                  #:snapshot [snapshot char-frame]
                  #:stop [stop (λ () #f)]
                  #:dedup? [dedup? #t]
                  #:diff? [diff? #f]
                  #:styles? [styles? #f]
                  #:rows [rows 24]
                  #:cols [cols 80])
  (parameterize ([current-screen-size (cons rows cols)])
   (with-tui
    (λ ()
     (char-input-clear!)
     (apply char-input-push! events)
     (char-input-close!)
     (define frames '())                 ; 文本，新→旧
     (define grids '())                  ; 与 frames 对齐的 grid 快照，新→旧
     (define (snap!)
       (define g (the-screen))
       (define txt (snapshot))
       ;; 去重看整块视觉状态：只有颜色变化也算变化
       (unless (and dedup? (pair? grids) (grid-equal? (car grids) g))
         (set! frames (cons txt frames))
         (set! grids (cons (grid-copy g) grids))
         ;; 同步进历史，char-run 结束后 char-history 也能用
         (history-push! g)))
     (render)
     (snap!)
     (let loop ()
       (unless (char-input-exhausted?)
         (define ev (read-event))
         (handle ev)
         (render)
         (snap!)
         (unless (stop) (loop))))
       (define fs (reverse frames))
       (define gs (reverse grids))
       (cond
         [(not diff?) fs]
         [(null? fs) '()]
         [styles?
          (cons (car fs)
                (for/list ([pa (in-list gs)] [pb (in-list (cdr gs))])
                  (grid-diff pa pb)))]
         [else
          (cons (car fs)
                (for/list ([pa (in-list fs)] [pb (in-list (cdr fs))])
                  (frame-diff pa pb)))])))))
