#lang racket

(require "../ui/main.rkt")

;; ── 组件自己管可见性, 外部用 component-show!/hide!/toggle! 操作 ──

(define toggle-count (box 0))

;; 按钮 A: on-activate 里用 component-hide! 隐藏自己
(define btn-a
  (make-button #:text "Press me → I vanish"
               #:on-activate (λ () (component-hide! btn-a))))

;; 按钮 B: 切换按钮 A 的可见性
(define btn-b
  (make-button #:text "Toggle button A"
               #:on-activate (λ ()
                               (component-toggle! btn-a)
                               (set-box! toggle-count (add1 (unbox toggle-count))))))

;; 按钮 C: 显示按钮 A
(define btn-c
  (make-button #:text "Show A"
               #:on-activate (λ () (component-show! btn-a))))

(run-app
 ((make-text #:text "┌────┤ show? Toggle Test ├───────┐" #:style 'title)
  1 1 34 1)

 ((make-text #:text (λ () (format "│ A visible: ~a~a"
                                  (if (component-visible? btn-a) "yes " "no  ")
                                  (make-string (max 0 (- 17 (if (component-visible? btn-a) 4 3))) #\space)))
             #:style 'info)
  1 2 34 1)

 ((make-text #:text (λ () (format "│ Toggles:  ~a~a"
                                  (unbox toggle-count)
                                  (make-string (max 0 (- 18 (string-length (number->string (unbox toggle-count))))) #\space)))
             #:style 'info)
  1 3 34 1)

 ((make-text #:text "│ q = quit                       │" #:style 'info)
  1 4 34 1)

 ((make-text #:text "└────────────────────────────────┘" #:style 'title)
  1 5 34 1)

 (btn-a 2 7 0 0)
 (btn-b 2 9 0 0)
 (btn-c 18 9 0 0))
