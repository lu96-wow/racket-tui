#lang racket
;; 鼠标路由 — 空间分发 + capture

(require "../component.rkt")

(provide make-mouse-router)

(define (make-mouse-router specs-box unbox* mouse-focus)
  (define (find-component-at mx my)
    (for/or ([s (reverse (unbox specs-box))])
      (match-let ([(list comp xb yb wb hb) s])
        (define cx (unbox* xb))
        (define cy (unbox* yb))
        (define cw (let ([v (unbox* wb)]) (if (zero? v) (component-w comp) v)))
        (define ch (let ([v (unbox* hb)]) (if (zero? v) (component-h comp) v)))
        (and (component-visible? comp)
             (<= cx mx (+ cx cw -1))
             (<= cy my (+ cy ch -1))
             comp))))

  (define (send comp type data)
    ((component-handler comp) type data #f))

  (λ (type data mods)
    (case (and (pair? data) (car data))
      [(press)
       (let ([comp (find-component-at (caddr data) (cadddr data))])
         (when comp
           (set-box! mouse-focus comp)
           (send comp 'mouse data)))]
      [(release)
       (let ([mf (unbox mouse-focus)])
         (if mf
             (begin
               (set-box! mouse-focus #f)
               (send mf 'mouse data))
             (let ([comp (find-component-at (caddr data) (cadddr data))])
               (when comp
                 (send comp 'mouse data)))))]
      [(move)
       (let ([comp (or (unbox mouse-focus)
                       (find-component-at (caddr data) (cadddr data)))])
         (when comp
           (send comp 'mouse data)))]
      [(scroll)
       (let ([comp (or (unbox mouse-focus)
                       (find-component-at (cadddr data)
                                          (car (cddddr data))))])
         (when comp
           (send comp 'mouse data)))]
      [else (void)])))
