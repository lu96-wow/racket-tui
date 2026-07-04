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

(define specs
  (list
   ;; 标题
   (list (make-text #:text "┌────┤ Text Mode Test ├──────────┐" #:style 'title)
         0 0 32 1)

   ;; 方案 1: box
   (list (make-text #:text "│ box:                          │" #:style 'info)
         0 1 32 1)
   (list (make-text #:text box-text #:style 'success)
         0 2 32 1)
   (list (make-text #:text "│ press [Update Box] to change  │" #:style 'info)
         0 3 32 1)

   ;; 方案 2: lambda
   (list (make-text #:text "│ lambda:                       │" #:style 'info)
         0 4 32 1)
   (list (make-text #:text (λ () (set-box! lambda-ticks (add1 (unbox lambda-ticks)))
                                (format "lambda: counter=~a ticks=~a"
                                        (unbox counter) (unbox lambda-ticks)))
                    #:style 'warning)
         0 5 32 1)
   (list (make-text #:text "│ press [Inc] to bump counter   │" #:style 'info)
         0 6 32 1)

   ;; 方案 3: 静态
   (list (make-text #:text "│ static:                       │" #:style 'info)
         0 7 32 1)
   (list (make-text #:text static-label #:style 'white)
         0 8 32 1)
   (list (make-text #:text "│ never changes, zero overhead  │" #:style 'info)
         0 9 32 1)

   ;; 底部线
   (list (make-text #:text "└───────────────────────────────┘" #:style 'title)
         0 10 32 1)

   ;; 按钮
   (list (make-button #:text "Update Box"
                      #:on-activate update-box)
         1 12 0 0)

   (list (make-button #:text "Inc"
                      #:on-activate increment)
         15 12 0 0)

   (list reset-btn 21 12 0 0)))

(run-app specs)
