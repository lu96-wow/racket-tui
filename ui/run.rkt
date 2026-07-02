#lang racket
;; 调度器 — 焦点 / 事件分发 / 增量绘制 / 显示管理
;;
;; 调度器职责:
;;   1. 焦点管理（鼠标点击切换）
;;   2. 全局事件拦截（如 quit 键）
;;   3. 事件转发（普通事件→焦点组件, resize→广播所有组件）
;;   4. 增量绘制（screen-clear + render 缓存回放）
;;   5. 可见性管理（组件区域与窗口有交集才渲染）
;;
;; 调度器不负责:
;;   - 布局计算（组件自己通过 box 坐标控制）
;;   - resize 自适应（组件在 handler 里监听 #:resize 自己处理）
(require "../base/main.rkt"
         "../base/io/build-input.rkt"
         "component.rkt")

(provide run-app)

;; specs : (list (list component x y w h) ...)
;;         x, y, w, h 可以是 number 或 box?
;; #:noblock? : #t 时使用非阻塞事件循环
(define (run-app specs #:noblock? [noblock? #f])
  (with-tui
    (cursor-hide)
    (define (unbox* v) (if (box? v) (unbox v) v))

    (define focus (box (for/or ([s specs])
                         (define comp (car s))
                         (and (component-show? comp)
                              (component-focusable? comp)
                              comp))))
    (define quit? (box #f))

    ;; ─── 增量渲染状态 ───
    ;; last-bounds  : component → (list x y w h) | #f (上帧不可见)
    ;; render-cache : component → bytes  (上次 render 的终端输出)
    ;; last-focused : component → #t/#f  (上次 render 时的焦点状态)
    (define last-bounds  (make-hasheq))
    (define render-cache (make-hasheq))
    (define last-focused (make-hasheq))

    (define global
      (build-input
       #:char (λ (ch) (when (= ch (char->integer #\q))
                         (set-box! quit? #t)))
       #:mouse-press (λ (btn mx my mods)
                       (when (eq? btn 'left)
                         (for/or ([s specs])
                           (match-let ([(list comp xb yb wb hb) s])
                             (define cx (unbox* xb))
                             (define cy (unbox* yb))
                             (define cw (let ([v (unbox* wb)]) (if (zero? v) (component-w comp) v)))
                             (define ch (let ([v (unbox* hb)]) (if (zero? v) (component-h comp) v)))
                             (and (component-show? comp)
                                  (component-focusable? comp)
                                  (<= cx mx (+ cx cw -1))
                                  (<= cy my (+ cy ch -1))
                                  (begin (set-box! focus comp) #t))))))))

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

            ;; 组件没变但屏幕清过 → 从缓存恢复
            [(not all-bounds-stable?)
             (define bs (hash-ref render-cache comp #""))
             (write-bytes bs)]

            ;; 组件没变、屏幕也没清 → 跳过
            [else
             (void)])))
      (flush-output))

    ;; 首帧全量绘制
    (render-all)

    ;; 事件转发: resize → 广播所有组件, 其他 → 全局 + 焦点组件
    (define (dispatch-and-render type data mods)
      (cond
        [(eq? type 'resize)
         (for ([s specs])
           ((component-handler (car s)) type data mods))]
        [else
         (when (unbox focus)
           ((component-handler (unbox focus)) type data mods))])
      (render-all))

    (if noblock?
        (loop-input-noblock/stop (unbox quit?)
          global dispatch-and-render)
        (loop-input/stop (unbox quit?)
          global dispatch-and-render))))
