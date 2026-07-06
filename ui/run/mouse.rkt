#lang racket
;; 鼠标路由 — 空间分发 + capture

(require "../component.rkt")

(provide make-mouse-router)

(define (make-mouse-router specs-box maybe-unbox resolve-size mouse-focus)
  (define (find-component-at mx my)
    (for/or ([spec (reverse (unbox specs-box))])
      (match-let ([(list comp xb yb wb hb) spec])
        (define cx (maybe-unbox xb))
        (define cy (maybe-unbox yb))
        (define cw (resolve-size wb component-w comp))
        (define ch (resolve-size hb component-h comp))
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
