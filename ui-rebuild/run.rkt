#lang racket

;; ═══════════════════════════════════════════════════════════════════════════
;; run.rkt — 声明式事件循环（The Elm Architecture）
;;
;;   state  ──view──▶  widget  ──layout──▶  element  ──render──▶  surface
;;     ▲                                                           │
;;     └──── update ◀── message ◀── route-event ◀── read-event ◀──┘
;;
;;   run-app 返回最终 state（quit 时）。
;;
;; 保留消息（框架内置）：
;;   'ui-quit       退出事件循环，返回当前 state
;;   'ui-focus-next 焦点移到下一个 focusable 叶节点
;;   'ui-focus-prev 焦点移到上一个 focusable 叶节点
;;
;; keymap：'((key . message) ...)，key 可以是 char（如 #\q）或
;;          特殊键符号（'tab 'up 'down 'left 'right 'enter ...）。
;;          全局 keymap 优先于焦点组件的 on-event。
;; ═══════════════════════════════════════════════════════════════════════════

(require "../base/main.rkt"
         "widget.rkt"
         "layout.rkt"
         "render.rkt"
         "surface.rkt")

(provide run-app run-app-noblock
         msg-quit msg-focus-next msg-focus-prev
         mouse-data-0based)

(define msg-quit       'ui-quit)
(define msg-focus-next 'ui-focus-next)
(define msg-focus-prev 'ui-focus-prev)

(define (run-app #:init init #:update update #:view view
                 #:keymap [keymap '()])
  (run-app* init update view keymap #f))

(define (run-app-noblock #:init init #:update update #:view view
                         #:keymap [keymap '()])
  (run-app* init update view keymap #t))

(define (run-app* init update view keymap noblock?)
  (with-tui
   (cursor-hide)

   (define state init)
   (define elem #f)          ; 当前 element 树
   (define focusables '())   ; 焦点顺序
   (define focus #f)         ; 当前聚焦的 element（每帧由 focus-k 重算）
   (define focus-k #f)       ; 聚焦 leaf 的 widget key（跨帧稳定）
   (define prev-surf #f)     ; 上一帧 surface（用于 diff）
   (define local-table (make-hasheq))  ; keyed local state
   (define capture #f)       ; 鼠标拖拽捕获的 element
   (define dirty? (box #f))  ; 局部状态是否被写入（用于跳过无变化的重绘）
   (define (mark-dirty!) (set-box! dirty? #t))
   (define rctx (make-render-ctx #:local-table local-table #:mark-dirty! mark-dirty!))

   (define (elem-key e)
     (widget-key (element-widget e)))

   ;; 按 key 找回聚焦 element（element 每帧重建，不能用 eq?）
   (define (find-focused fs k)
     (cond
       [(null? fs) #f]
       [k (or (for/or ([x (in-list fs)]
                       #:when (equal? (elem-key x) k))
                x)
              (car fs))]
       [else (car fs)]))

   ;; 每帧：view → layout → render → diff → flush
   (define (frame!)
     (define-values (rows cols) (get-window-size))
     (define e (resolve (view state) 0 0 cols rows))
     (define fs (element-focusables e))
     (define f (find-focused fs focus-k))
     (set! elem e)
     (set! focusables fs)
     (set! focus f)
     (set! focus-k (and f (elem-key f)))
     ;; 清理已卸载 widget 的局部状态
     (define mounted (element-leaf-keys e))
     (for ([(k v) (in-hash local-table)])
       (unless (member k mounted)
         (hash-remove! local-table k)))
     (set! rctx (make-render-ctx #:focus-key focus-k
                                 #:local-table local-table
                                 #:mark-dirty! mark-dirty!))
     (define surf (make-surface rows cols))
     (render-element! e surf rctx)
     (write-bytes (surface-diff-bytes surf prev-surf))
     (flush-output)
     (set! prev-surf surf))

   ;; 事件 → 消息
   (define (route-event type data mods)
     (cond
       [(eq? type 'resize) #f]
       [(eq? type 'mouse)
        ;; 终端鼠标坐标是 1-based；内部 rect 是 0-based → 统一转成 0-based
        (define d0 (mouse-data-0based data))
        (define hit (element-hit elem (mouse-x d0) (mouse-y d0)))
        (cond
          [(mouse-press? d0)
           (set! capture hit)
           ;; 点击聚焦：点击 focusable 组件时把键盘焦点移过去
           (when (and hit (widget-focusable? (element-widget hit)))
             (set! focus-k (elem-key hit))
             (mark-dirty!))
           (and hit (call-on-event hit type d0))]
          [(mouse-release? d0)
           (define target (or capture hit))
           (set! capture #f)
           (and target (call-on-event target type d0))]
          [else  ; move / scroll：优先发给捕获目标
           (define target (or capture hit))
           (and target (call-on-event target type d0))])]
       [(eq? type 'null) #f]
       [else
        ;; 键盘事件归一化：把 'key + bytes 映射成语义 key
        ;; （'enter/'space/'up/#\a ...）再交给焦点组件；
        ;; 非键盘事件（如 paste）key 为 #f，保持原 type。
        (define key (event->key type data))
        (or (keymap-lookup keymap key)
            (and focus (call-on-event focus (or key type) data)))]))

   (define (call-on-event e type data)
     (define w (element-widget e))
     (define fn (and (eq? (widget-kind w) 'leaf)
                     (hash-ref (widget-props w) 'on-event #f)))
     (and fn (fn w type data (element-rect e) (widget-ctx w rctx))))

   (frame!)

   (let loop ()
     (let-values ([(type data mods)
                   (if noblock? (read-event-noblock) (read-event))])
       (set-box! dirty? #f)
       (define msg (route-event type data mods))
       (cond
         [(eq? msg msg-quit) state]
         [(eq? type 'resize) (frame!) (loop)]
         [(eq? msg msg-focus-next)
          (set! focus-k (elem-key (focus-step focusables focus-k +1)))
          (frame!) (loop)]
         [(eq? msg msg-focus-prev)
          (set! focus-k (elem-key (focus-step focusables focus-k -1)))
          (frame!) (loop)]
         [else
          (when msg (set! state (update state msg)))
          ;; 只有 state 变了或局部状态变了才重绘；
          ;; 鼠标无操作移动/未处理按键直接跳过，避免整屏重渲染
          (when (or msg (unbox dirty?)) (frame!))
          (loop)])))))

;; ── 工具 ──

;; 终端鼠标坐标 1-based → 内部 0-based
;; press/release/move: (action button x y mods)
;; scroll:             (action 'scroll dir x y mods)
(define (mouse-data-0based d)
  (if (mouse-scroll? d)
      (list (car d) (cadr d) (caddr d)
            (sub1 (cadddr d)) (sub1 (car (cddddr d))) (last d))
      (list (car d) (cadr d)
            (sub1 (caddr d)) (sub1 (cadddr d)) (last d))))

(define (keymap-lookup km key)
  (and key (cond [(assoc key km) => cdr] [else #f])))

;; 底层事件 → 可绑定的 key（char 或符号）
(define (event->key type data)
  (cond
    [(event-enter? type data) 'enter]
    [(event-tab? type data) 'tab]
    [(event-space? type data) 'space]
    [(event-backspace? type data) 'backspace]
    [(event-escape? type data) 'escape]
    [(alt-enter? type data) 'alt-enter]
    [(backtab? type data) 'backtab]
    [(memq type '(up down left right del insert home end pageup pagedown))
     type]
    [(and (eq? type 'key) (bytes? data) (= (bytes-length data) 1))
     (integer->char (bytes-ref data 0))]
    [else #f]))

;; Alt+Enter：ESC 后跟 CR/LF（部分终端）
(define (alt-enter? type data)
  (and (eq? type 'seq)
       (bytes? data)
       (or (equal? data #"\e\r")
           (equal? data #"\e\n"))))

;; shift-tab 通常发 CSI Z：ESC [ Z 或 ESC [ 1 ; 2 Z
(define (backtab? type data)
  (and (eq? type 'seq)
       (bytes? data)
       (let ([n (bytes-length data)])
         (and (>= n 3)
              (= (bytes-ref data 0) 27)   ; ESC
              (= (bytes-ref data 1) 91)   ; [
              (= (bytes-ref data (sub1 n)) 90)))))  ; 末尾 Z

(define (focus-step fs k dir)
  (cond
    [(null? fs) #f]
    [else
     (define idx (or (index-by-key fs k) 0))
     (list-ref fs (modulo (+ idx dir) (length fs)))]))

(define (index-by-key fs k)
  (for/first ([x (in-list fs)] [i (in-naturals)]
              #:when (equal? (widget-key (element-widget x)) k))
    i))

;; element 树中所有 leaf 的 key（用于清理已卸载的 keyed local state）
(define (element-leaf-keys e)
  (let walk ([e e])
    (define w (element-widget e))
    (if (eq? (widget-kind w) 'leaf)
        (let ([k (widget-key w)])
          (if k (list k) '()))
        (apply append (map walk (element-children e))))))
