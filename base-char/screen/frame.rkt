#lang racket

;; 帧工具：把每帧渲染成纯字符图，可落盘给 AI / CI 读。
;; 帧边界由 flush! 触发（见 io/output.rkt）。

(require "grid.rkt"
         "render.rkt"
         "history.rkt"
         "session.rkt")

(provide current-frame-hook frame-end!
         char-frame
         char-log-enable! char-log-disable!
         screen-frame-log-enable! screen-frame-log-disable!
         screen-frame-count)

(define last-frame (box #f))
(define frame-count (box 0))

;; 当前整屏字符图
(define (char-frame #:trim-right? [trim? #t])
  (grid->text (the-screen) #:trim-right? trim?))

;; 逐帧打印到端口（默认 stdout）。diff? 为真时只打印与上一帧不同的行（文本+样式）。
;; 带序号，便于与 char-history / char-frame-at 对应。
(define (char-log-enable! #:to [out (current-output-port)]
                          #:diff? [diff? #t]
                          #:trim-right? [trim? #t])
  (define prev (box #f))
  (define n (box 0))
  (current-frame-hook
   (λ (g)
     (cond
       [(or (not diff?) (not (unbox prev)))
        (set-box! n (add1 (unbox n)))
        (fprintf out "── frame ~a ──\n~a\n" (unbox n)
                 (grid->text g #:trim-right? trim?))]
       [else
        (define d (grid-diff (unbox prev) g))
        (unless (string=? d "")
          (set-box! n (add1 (unbox n)))
          (fprintf out "── diff ~a ──\n~a" (unbox n) d))])
     (set-box! prev (grid-copy g))
     (flush-output out))))

(define (char-log-disable!)
  (current-frame-hook #f))

;; 逐帧落盘。dedup? 为真时跳过视觉（文本+颜色+属性）与上一帧相同的帧；
;; diff? 为真时只写差异（文本变化行 + 样式变化区间）。
(define (screen-frame-log-enable! path
                                  #:trim-right? [trim? #t]
                                  #:dedup? [dedup? #t]
                                  #:diff? [diff? #f])
  (set-box! last-frame #f)
  (set-box! frame-count 0)
  (current-frame-hook
   (λ (g)
     (define prev (unbox last-frame))
     (unless (and dedup? prev (grid-equal? prev g))
       (set-box! frame-count (add1 (unbox frame-count)))
       (call-with-output-file path
         #:exists 'append
         (λ (out)
           (if (and diff? prev)
               (fprintf out "── diff ~a ──\n~a" (unbox frame-count) (grid-diff prev g))
               (fprintf out "── frame ~a ──\n~a\n" (unbox frame-count)
                        (grid->text g #:trim-right? trim?)))))
       (set-box! last-frame (grid-copy g))))))

(define (screen-frame-log-disable!)
  (current-frame-hook #f))

(define (screen-frame-count) (unbox frame-count))
