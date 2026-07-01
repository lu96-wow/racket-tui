#lang racket
;; ui-test/input-test.rkt — input + button + dirty flag 综合测试
;;
;; 验证:
;;   1. input 输入 / 光标移动 / 删除 / 提交
;;   2. button 激活回调
;;   3. dirty flag：只重绘变化的组件
;;   4. 焦点在 input/button 间点击切换
;;   5. resize 时部分可见组件依然渲染

(require "../main.rkt"
         "../ui/run.rkt"
         "../ui/component.rkt"
         "../ui/widgets/input.rkt"
         "../ui/widgets/button.rkt"
         "../base/io/build-input.rkt"
         "../base/io/output.rkt"
         "../base/io/output-styles.rkt")

;; ═══════════════════════════════════════════════
;; 状态栏 — 显示最后提交的内容
;; ═══════════════════════════════════════════════
(define submitted (box "(none)"))
(define status-dirty (box #t))

(define (make-status)
  (define dirty status-dirty)
  (component
   (λ (focused? x y w h)
     (for ([i (in-range h)])
       (cursor-move (+ y i) x)
       (put-string (make-string w #\space)))
     (put-styled-at! y x 'title
       "┌────┤ Input Widget Test ├────┐")
     (put-styled-at! (+ y 1) x 'info
       "│ Type in the input field       │")
     (put-styled-at! (+ y 2) x 'info
       "│ Enter = submit, Esc = clear   │")
     (put-styled-at! (+ y 3) x 'info
       (format "│ Last submit: ~a~a"
               (unbox submitted)
               (make-string (max 0 (- 26 (string-length (unbox submitted))))
                            #\space)))
     (put-styled-at! (+ y 4) x 'info
       "│ Press q to quit               │")
     (put-styled-at! (+ y 5) x 'title
       "└──────────────────────────────┘"))
   (build-input)
   #f #t 36 6 dirty))

;; ═══════════════════════════════════════════════
;; specs
;; ═══════════════════════════════════════════════
(define name-input
  (make-input #:placeholder "Enter your name..."
              #:on-submit (λ (t) (set-box! submitted t) (set-box! status-dirty #t))
              #:on-change void))

(define submit-btn
  (make-button #:text "Submit"
               #:on-activate (λ () (set-box! submitted "button clicked!") (set-box! status-dirty #t))))

(define specs
  (list (list (make-status) 0 0 36 6)
        (list name-input     2 8 20 1)
        (list submit-btn     2 10 0 0)))  ;; button w/h 由自身决定

(run-app specs)
