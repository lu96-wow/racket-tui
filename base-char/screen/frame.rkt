#lang racket

;; 帧工具：把每帧渲染成纯字符图，可落盘给 AI / CI 读。
;; 帧边界由 flush! 触发（见 io/output.rkt）。

(require "grid.rkt"
         "render.rkt"
         "session.rkt")

(provide current-frame-hook frame-end!
         char-frame
         screen-frame-log-enable! screen-frame-log-disable!
         screen-frame-count)

(define last-frame (box #f))
(define frame-count (box 0))

;; 当前整屏字符图
(define (char-frame #:trim-right? [trim? #t])
  (grid->text (the-screen) #:trim-right? trim?))

;; 开启逐帧落盘。dedup? 为真时跳过与上一帧完全相同的帧。
(define (screen-frame-log-enable! path
                                  #:trim-right? [trim? #t]
                                  #:dedup? [dedup? #t])
  (set-box! last-frame #f)
  (set-box! frame-count 0)
  (current-frame-hook
   (λ (g)
     (define txt (grid->text g #:trim-right? trim?))
     (unless (and dedup? (equal? txt (unbox last-frame)))
       (set-box! last-frame txt)
       (set-box! frame-count (add1 (unbox frame-count)))
       (call-with-output-file path
         #:exists 'append
         (λ (out)
           (fprintf out "── frame ~a ──\n~a\n" (unbox frame-count) txt)))))))

(define (screen-frame-log-disable!)
  (current-frame-hook #f))

(define (screen-frame-count) (unbox frame-count))
