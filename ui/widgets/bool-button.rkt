#lang racket

(require "../component.rkt"
         "../../base/io/build-input.rkt"
         "../../base/io/output-styles.rkt"
         "../../base/io/output-color.rkt"
         "../../base/io/output.rkt")

(provide make-bool-button)

;; ═══════════════════════════════════════════════════════════════════════════
;; make-bool-button — 布尔开关
;;
;; (make-bool-button
;;   #:text       "Label"     ;; 显示文字
;;   #:initial?   #f          ;; 初始状态
;;   #:on-change  (λ (v) ..)  ;; 状态变化回调
;;   #:on-style   'success    ;; 开样式
;;   #:off-style  'info       ;; 关样式)
;; ═══════════════════════════════════════════════════════════════════════════

(define (make-bool-button
         #:text       [text ""]
         #:initial?   [initial? #f]
         #:on-change  [on-change void]
         #:on-style   [on-style 'success]
         #:off-style  [off-style 'info])

  (define state  (box initial?))
  (define dirty  (box #t))
  (define label  (string-append " " text " "))

  (define (render focused? x y w h)
    (define v (unbox state))
    (define style (if v on-style off-style))
    (define mark  (if v "[x]" "[ ]"))
    (define line  (if ((string-length label) . > . w)
                      (substring label 0 w)
                      label))
    (for ([i (in-range h)])
      (write-bytes (format-styled-at (+ y i) x style (make-string w #\space))))
    (define mark-str (string-append mark line))
    (define visible
      (if ((string-length mark-str) . > . w)
          (substring mark-str 0 w)
          mark-str))
    (write-bytes (format-styled-at y x style visible)))

  (define (toggle!)
    (set-box! state (not (unbox state)))
    (set-box! dirty #t)
    (on-change (unbox state)))

  (define handler
    (build-input
     #:enter     toggle!
     #:space     toggle!
     #:mouse-press (λ (btn mx my mods)
                     (when (eq? btn 'left)
                       (toggle!)))))

  (component render handler #t (box #t)
             (+ 3 (string-length text)) 1 dirty #f))
