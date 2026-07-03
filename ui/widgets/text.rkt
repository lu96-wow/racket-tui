#lang racket

(require "../component.rkt"
         "../../base/io/build-input.rkt"
         "../../base/io/output-styles.rkt"
         "../../base/io/output-color.rkt"
         "../../base/io/output.rkt")

(provide make-text)

;; ═══════════════════════════════════════════════════════
;; 宏：编译期按 #:text 类型分派
;; ═══════════════════════════════════════════════════════

(define-syntax (make-text stx)
  (syntax-case stx ()
    [(_ #:text str rest ...)
     (string? (syntax-e #'str))
     #'(make-text/static #:text str rest ...)]
    [(_ #:text (lambda () body ...) rest ...)
     #'(make-text/lambda #:text (lambda () body ...) rest ...)]
    [(_ #:text (λ () body ...) rest ...)
     #'(make-text/lambda #:text (λ () body ...) rest ...)]
    [(_ #:text expr rest ...)
     #'(make-text/dynamic #:text expr rest ...)]))

;; ═══════════════════════════════════════════════════════
;; 共享渲染 — format-* 一次性写 bytes
;; ═══════════════════════════════════════════════════════

(define (render-text s style h-align x y w h)
  (define visible
    (if ((string-length s) . > . w) (substring s 0 w) s))
  (define visible-w (string-length visible))
  (define x-off
    (case h-align
      [(center) (quotient (max 0 (- w visible-w)) 2)]
      [(right)  (max 0 (- w visible-w))]
      [else 0]))
  (for ([i (in-range h)])
    (write-bytes (format-styled-at! (+ y i) x style (make-string w #\space))))
  (write-bytes (format-styled-at! y (+ x x-off) style visible)))

;; ═══════════════════════════════════════════════════════
;; 路径 A: 静态字符串 — 零 per-frame 开销
;; ═══════════════════════════════════════════════════════

(define (make-text/static #:text str
                          #:style [style 'info]
                          #:h-align [h-align 'left]
                          #:show? [show? (box #t)])
  (define str-len (string-length str))
  (define show-box (if (boolean? show?) (box show?) show?))
  (component
   (λ (focused? x y w h)
     (render-text str style h-align x y w h))
   (build-input)
   #f show-box str-len 1 (box #t) #f))

;; ═══════════════════════════════════════════════════════
;; 路径 B: lambda — 每帧调用 proc，比对后标记 dirty
;; ═══════════════════════════════════════════════════════

(define (make-text/lambda #:text proc
                          #:style [style 'info]
                          #:h-align [h-align 'left]
                          #:show? [show? (box #t)])
  (define dirty (box #t))
  (define cache (box (proc)))
  (define show-box (if (boolean? show?) (box show?) show?))
  (component
   (λ (focused? x y w h)
     (render-text (unbox cache) style h-align x y w h))
   (build-input)
   #f show-box 0 1 dirty
   (λ (x y w h focused?)
     (define cur (proc))
     (unless (equal? cur (unbox cache))
       (set-box! cache cur)
       (set-box! dirty #t)))))

;; ═══════════════════════════════════════════════════════
;; 路径 C: 运行时 dispatch — string / box / procedure
;; ═══════════════════════════════════════════════════════

(define (make-text/dynamic #:text val
                           #:style [style 'info]
                           #:h-align [h-align 'left]
                           #:show? [show? (box #t)])
  (define show-box (if (boolean? show?) (box show?) show?))
  (cond
    [(string? val)
     (make-text/static #:text val #:style style #:h-align h-align #:show? show-box)]
    [(procedure? val)
     (make-text/lambda #:text val #:style style #:h-align h-align #:show? show-box)]
    [(box? val)
     (define dirty (box #t))
     (define cache (box (unbox val)))
     (component
      (λ (focused? x y w h)
        (render-text (unbox cache) style h-align x y w h))
      (build-input)
      #f show-box 0 1 dirty
      (λ (x y w h focused?)
        (define cur (unbox val))
        (unless (equal? cur (unbox cache))
          (set-box! cache cur)
          (set-box! dirty #t))))]
    [else
     (error 'make-text "unsupported #:text type: ~a" val)]))
