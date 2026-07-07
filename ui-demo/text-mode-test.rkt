#lang racket

(require "../ui/main.rkt")

;; ── 三种 text 方案的状态 ──

;; 方案 1: box — 外部修改 box 内容
(define box-text (box "box: waiting..."))

;; 方案 2: lambda — 每帧动态计算
(define counter (box 0))
(define lambda-ticks (box 0))

;; 方案 3: 静态 — 编译期确定，永不变
(define static-label "static: never changes")

;; ── 按钮：触发三种 text 更新 ──

(define (update-box)
  (set-box! box-text (format "box: updated at ~a" (current-milliseconds))))

(define (increment)
  (set-box! counter (add1 (unbox counter))))

(define reset-btn
  (make-button #:text "Reset"
               #:on-activate (λ ()
                               (set-box! counter 0)
                               (set-box! box-text "box: reset"))))

;; ── specs ──

(run-app
 ;; 标题
 ((make-text #:text "┌────┤ Text Mode Test ├──────────┐" #:style 'title)
  1 1 32 1)

 ;; 方案 1: box
 ((make-text #:text "│ box:                          │" #:style 'info)
  1 2 32 1)
 ((make-text #:text box-text #:style 'success)
  1 3 32 1)
 ((make-text #:text "│ press [Update Box] to change  │" #:style 'info)
  1 4 32 1)

 ;; 方案 2: lambda
 ((make-text #:text "│ lambda:                       │" #:style 'info)
  1 5 32 1)
 ((make-text #:text (λ () (set-box! lambda-ticks (add1 (unbox lambda-ticks)))
                        (format "lambda: counter=~a ticks=~a"
                                (unbox counter) (unbox lambda-ticks)))
            #:style 'warning)
  1 6 32 1)
 ((make-text #:text "│ press [Inc] to bump counter   │" #:style 'info)
  1 7 32 1)

 ;; 方案 3: 静态
 ((make-text #:text "│ static:                       │" #:style 'info)
  1 8 32 1)
 ((make-text #:text static-label #:style 'white)
  1 9 32 1)
 ((make-text #:text "│ never changes, zero overhead  │" #:style 'info)
  1 10 32 1)

 ;; 底部线
 ((make-text #:text "└───────────────────────────────┘" #:style 'title)
  1 11 32 1)

 ;; 按钮
 ((make-button #:text "Update Box"
              #:on-activate update-box)
  2 13 0 0)

 ((make-button #:text "Inc"
              #:on-activate increment)
  16 13 0 0)

 (reset-btn 22 13 0 0))
