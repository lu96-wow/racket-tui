#lang racket
;; 渲染引擎 — screen-clear + 增量绘制 + 缓存回放
;;
;; 职责:
;;   - 预扫描组件 bounds/可见性 是否稳定
;;   - 稳定时跳过 screen-clear，只重绘脏/焦点变化组件
;;   - 不稳定时全量清屏 + 缓存回放

(require "../base/main.rkt"
         "component.rkt")

(provide make-renderer)

(define (make-renderer specs unbox* focus last-bounds render-cache last-focused)
  (define (render-all)
    (define-values (cur-rows cur-cols) (get-window-size))

    (define (fits? x y w h)
      (and (< x cur-cols) (< y cur-rows)
           (>= (+ x w) 0) (>= (+ y h) 0)))

    ;; 预扫描：所有组件 bounds/可见性 都没变 → 跳过 screen-clear
    (define all-bounds-stable?
      (for/and ([s specs])
        (match-let ([(list comp xb yb wb hb) s])
          (define x (unbox* xb))
          (define y (unbox* yb))
          (define w (let ([v (unbox* wb)]) (if (zero? v) (component-w comp) v)))
          (define h (let ([v (unbox* hb)]) (if (zero? v) (component-h comp) v)))
          (define visible? (and (component-show? comp) (fits? x y w h)))
          (define last (hash-ref last-bounds comp #f))
          (cond [(and last visible?)
                 (and (= x (first last)) (= y (second last))
                      (= w (third last))  (= h (fourth last)))]
                [(or last visible?) #f]
                [else #t]))))

    (unless all-bounds-stable?
      (screen-clear))

    (for ([s specs])
      (match-let ([(list comp xb yb wb hb) s])
        (define x (unbox* xb))
        (define y (unbox* yb))
        (define w (unbox* wb))
        (define h (unbox* hb))

        (define visible? (and (component-show? comp) (fits? x y w h)))
        (define last (hash-ref last-bounds comp #f))
        (define focused-now? (eq? comp (unbox focus)))

        (define bounds-changed?
          (and last
               (or (not (= x (first last)))
                   (not (= y (second last)))
                   (not (= w (third last)))
                   (not (= h (fourth last))))))

        (define needs-redraw?
          (or (not last)
              bounds-changed?
              (not (eq? focused-now? (hash-ref last-focused comp #f)))
              (unbox (component-dirty comp))))

        (cond
          [(not visible?)
           (hash-set! last-bounds comp #f)
           (hash-remove! render-cache comp)]

          [needs-redraw?
           (define saved-row current-cursor-row)
           (define saved-col current-cursor-col)
           (define out (open-output-bytes))
           (parameterize ([current-output-port out])
             ((component-render comp) focused-now? x y w h))
           (define bs (get-output-bytes out))
           (set-cursor! saved-row saved-col)
           (write-bytes bs)
           (hash-set! render-cache comp bs)
           (hash-set! last-bounds comp (list x y w h))
           (hash-set! last-focused comp focused-now?)
           (set-box! (component-dirty comp) #f)]

          [(not all-bounds-stable?)
           (define bs (hash-ref render-cache comp #""))
           (write-bytes bs)]

          [else
           (void)])))
    (flush-output))

  render-all)
