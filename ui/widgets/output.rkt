#lang racket

(require "../component.rkt"
         "../output-buffer.rkt"
         "../../base/io/build-input.rkt"
         "../../base/io/output-color.rkt"
         "../../base/io/output-styles.rkt"
         "../../base/io/output.rkt")

(provide make-output
         output-model-put-string! output-model-put-char!
         output-model-clear! output-model-toggle-fold!)

(define (make-output #:max-lines   [max-lines #f]
                     #:style       [style 'info]
                     #:show?       [show? (box #t)]
                     #:auto-scroll? [auto? #t])

  (define show-box (if (boolean? show?) (box show?) show?))
  (define model   (make-output-model #:max-lines max-lines))
  (define dirty   (box #t))
  (define scroll  (box 0))
  (define auto    (box auto?))
  (define vp-w (box 80)) (define vp-h (box 24))
  (define last-total (box 0))

  (define (append! str)
    (output-model-put-string! model str) (set-box! dirty #t))
  (define (clear!)
    (output-model-clear! model) (set-box! scroll 0)
    (set-box! last-total 0) (set-box! dirty #t))
  (define (fold! idx)
    (output-model-toggle-fold! model idx) (set-box! dirty #t))
  (define (scroll-end!)
    (set-box! auto #t) (set-box! scroll 0) (set-box! dirty #t))

  (define (render focused? x y w h)
    (set-box! vp-w w) (set-box! vp-h h)
    (when (and (> w 0) (> h 0))
      (define p (compute-prefix-sum model w))
      (define total (vector-ref p (output-model-line-count model)))
      (when (and (unbox auto) (> total (unbox last-total)))
        (set-box! scroll (max 0 (- total h))))
      (set-box! last-total total)
      (define sy (max 0 (min (unbox scroll) (max 0 (- total h)))))
      (define-values (slots _li) (extract-visible-slots model p sy h))
      ;; 每行一笔：文本 + 右补齐空格，保证整行同一样式
      (for ([row (in-range h)])
        (define txt (if (< row (length slots)) (list-ref slots row) ""))
        (define pad (- w (string-display-width txt)))
        (define line (if (> pad 0) (string-append txt (make-string pad #\space)) txt))
        (write-bytes (format-styled-at (+ y row) x style line)))))

  (define (scroll-by! delta)
    (define w (unbox vp-w))
    (define h (unbox vp-h))
    (when (and (> w 0) (> h 0))
      (define p (compute-prefix-sum model w))
      (define total (vector-ref p (output-model-line-count model)))
      (define cur (unbox scroll))
      (define max-sy (max 0 (- total h)))
      (define new-sy (max 0 (min (+ cur delta) max-sy)))
      (unless (= new-sy cur)
        (set-box! scroll new-sy) (set-box! dirty #t)
        (set-box! auto (>= new-sy max-sy)))))

  (define handler
    (build-input
     #:up           (λ () (scroll-by! -1))
     #:down         (λ () (scroll-by!  1))
     #:pageup       (λ () (scroll-by! (- (unbox vp-h))))
     #:pagedown     (λ () (scroll-by! (unbox vp-h)))
     #:home         (λ () (set-box! scroll 0) (set-box! auto #f)
                         (set-box! dirty #t))
     #:end          (λ () (set-box! scroll 0) (set-box! auto #t)
                         (set-box! dirty #t))
     #:mouse-scroll (λ (dir x y mods)
                      (scroll-by! (if (eq? dir 'up) -3 3)))
     #:mouse-press  (λ (btn mx my mods) (set-box! auto #f))))

  (values (component render handler #t show-box 0 1 dirty #f)
          append! clear! fold! scroll-end!))
