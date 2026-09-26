#lang racket

;; 有界脚本运行器 —— AI 调试的推荐入口。
;;
;; 给定一串事件，按序处理，每个事件后渲染一次并抓一帧字符图，
;; 脚本跑完即结束。输出帧数有界（≤ 事件数+1），天然不会因为
;; 非阻塞循环而无限输出。

(require "tui.rkt"
         "io/event.rkt"
         "screen/frame.rkt"
         "screen/session.rkt"
         "screen/render.rkt")

(provide char-run)

;; events : (listof spec)  见 char-input-push!
;; #:handle   : (-> event? any)      处理单个事件（通常更新外部 state）
;; #:render   : (-> any)             绘制到当前网格
;; #:snapshot : (-> string)          抓帧（默认 char-frame）
;; #:stop     : (-> boolean?)        额外提前停止条件
;; #:dedup?   : boolean?             跳过与上一帧相同的帧（默认 #t）
(define (char-run events
                  #:handle [handle void]
                  #:render [render void]
                  #:snapshot [snapshot char-frame]
                  #:stop [stop (λ () #f)]
                  #:dedup? [dedup? #t]
                  #:rows [rows 24]
                  #:cols [cols 80])
  (parameterize ([current-screen-size (cons rows cols)])
   (with-tui
    (λ ()
     (char-input-clear!)
     (apply char-input-push! events)
     (char-input-close!)
     (define frames '())
     (define (snap!)
       (define txt (snapshot))
       (unless (and dedup? (pair? frames) (equal? txt (car frames)))
         (set! frames (cons txt frames))))
     (render)
     (snap!)
     (let loop ()
       (unless (char-input-exhausted?)
         (define ev (read-event))
         (handle ev)
         (render)
         (snap!)
         (unless (stop) (loop))))
       (reverse frames)))))
