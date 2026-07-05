#lang racket

(require "../component.rkt"
         "../../base/io/build-input.rkt"
         "../../base/io/output-styles.rkt"
         "../../base/io/output-color.rkt"
         "../../base/io/output.rkt")

(provide make-border)

(define (make-border
         #:up?         [up?         #t]
         #:down?       [down?       #t]
         #:left?       [left?       #t]
         #:right?      [right?      #t]
         #:up-style    [up-style    'info]
         #:down-style  [down-style  'info]
         #:left-style  [left-style  'info]
         #:right-style [right-style 'info]
         #:title       [title       #f])

  (define title-str
    (and title
         (let ([s (if (string? title) title (format "~a" title))])
           (and (positive? (string-length s)) s))))

  (define (render focused? x y w h)
    (when (and (> w 0) (> h 0))
      (define L x) (define R (+ x w -1))
      (define T y) (define B (+ y h -1))
      (render-top    T L R w up? left? right? up-style title-str)
      (render-bottom B L R w down? left? right? down-style)
      (render-side   L (+ T 1) (- B 1) left? left-style)
      (render-side   R (+ T 1) (- B 1) right? right-style)))

  (component render (build-input) #f (box #t) 0 0 (box #t) #f))

;; ── 上边 ──
(define (render-top row L R w up? left? right? style title)
  (unless (or (and (not up?) (not left?) (not right?)) (<= w 0))
    (define lch (cond [(and up? left?) "┌"] [up? "─"] [left? "│"] [else ""]))
    (when (positive? (string-length lch)) (put row L style lch))
    (when (and up? (> w 2))
      (define mid (if title (fit-title title (- w 2)) (make-string (- w 2) #\─)))
      (put row (add1 L) style mid))
    (when (> w 1)
      (define rch (cond [(and up? right?) "┐"] [up? "─"] [right? "│"] [else ""]))
      (when (positive? (string-length rch)) (put row R style rch)))))

;; ── 下边 ──
(define (render-bottom row L R w down? left? right? style)
  (unless (or (and (not down?) (not left?) (not right?)) (<= w 0))
    (define lch (cond [(and down? left?) "└"] [down? "─"] [left? "│"] [else ""]))
    (when (positive? (string-length lch)) (put row L style lch))
    (when (and down? (> w 2)) (put row (add1 L) style (make-string (- w 2) #\─)))
    (when (> w 1)
      (define rch (cond [(and down? right?) "┘"] [down? "─"] [right? "│"] [else ""]))
      (when (positive? (string-length rch)) (put row R style rch)))))

;; ── 侧边 ──
(define (render-side col r0 r1 visible? style)
  (when (and visible? (<= r0 r1))
    (for ([row (in-range r0 (add1 r1))])
      (write-bytes (format-styled-at! row col style "│")))))

;; ── title ──
(define (fit-title title max-w)
  (cond [(< max-w 5) (if (>= max-w 1) (pad "…" max-w #\─) "")]
        [else
         (define inner (- max-w 4))
         (define dt (if ((string-length title) . > . inner)
                        (string-append (substring title 0 (max 0 (- inner 1))) "…")
                        title))
         (define lp (quotient (- inner (string-length dt)) 2))
         (string-append "──" (make-string lp #\─) dt
                        (make-string (- inner (string-length dt) lp) #\─) "──")]))

(define (pad s w ch)
  (if (>= (string-length s) w) (substring s 0 w)
      (let* ([lp (quotient (- w (string-length s)) 2)])
        (string-append (make-string lp ch) s (make-string (- w (string-length s) lp) ch)))))

(define (put row col style str)
  (unless (equal? str "")
    (write-bytes (format-styled-at! row col style str))))
