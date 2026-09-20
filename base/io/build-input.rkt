#lang racket
;; =============================================================================
;; build-input — 事件分发器（基于规范化事件结构体）
;;
;; build-input 返回一个 (-> event? any) 的分发函数；read-event 返回 event?。
;; 每个事件按语义匹配到对应的关键字回调，未匹配的落到 #:any。
;;
;; 用法:
;;
;;   (define handler
;;     (build-input
;;       #:text    (lambda (s) (insert-text s))
;;       #:key     (lambda (key mods) (when (mods-ctrl? mods) ...))
;;       #:up      (lambda () (cursor-up 1))
;;       #:enter   (lambda () (newline))
;;       #:mouse   (lambda (action button x y mods) ...)
;;       #:resize  (lambda (rows cols) (redraw rows cols))
;;       #:any     (lambda (ev) (log-event ev))))
;;
;;   (loop-input handler)
;;
;; 回调签名:
;;
;;   #:key      (lambda (key mods) ...)          key: char? | symbol?（'up 'tab ...）
;;   #:text     (lambda (str) ...)               str: string（可打印字符 + 粘贴）
;;   #:paste    (lambda (bytes) ...)             原始粘贴字节
;;   #:mouse    (lambda (action button x y mods) ...)
;;   #:resize   (lambda (rows cols) ...)
;;   #:null     (lambda () ...)
;;   #:any      (lambda (ev) ...)                兜底：event? 结构体
;;
;;   命名键快捷回调（无修饰时）:
;;   #:tab #:backtab #:space #:enter #:backspace #:escape
;;   #:up #:down #:left #:right
;;   #:delete #:insert #:home #:end #:pageup #:pagedown
;;
;; 优先级（同一事件只投递一次）:
;;   null > resize > paste > mouse > key
;;   key: 命名快捷回调 > #:text > #:key > #:any
;;   paste: #:paste > #:text > #:any
;; =============================================================================
(require "event.rkt")

(provide build-input loop-input loop-input-noblock
         loop-input/stop loop-input-noblock/stop)

(define (build-input
          #:key [on-key #f]
          #:text [on-text #f]
          #:paste [on-paste #f]
          #:mouse [on-mouse #f]
          #:resize [on-resize #f]
          #:null [on-null #f]
          #:any [on-any #f]
          #:tab [on-tab #f]
          #:backtab [on-backtab #f]
          #:space [on-space #f]
          #:enter [on-enter #f]
          #:backspace [on-backspace #f]
          #:escape [on-escape #f]
          #:up [on-up #f]
          #:down [on-down #f]
          #:left [on-left #f]
          #:right [on-right #f]
          #:delete [on-delete #f]
          #:insert [on-insert #f]
          #:home [on-home #f]
          #:end [on-end #f]
          #:pageup [on-pageup #f]
          #:pagedown [on-pagedown #f])

  (define (any ev) (when on-any (on-any ev)))

  ;; 无修饰命名键 → 快捷回调（无则 #f）
  (define (shortcut-handler key)
    (cond [(eqv? key #\space) on-space]
          [(symbol? key)
           (case key
             [(tab) on-tab] [(backtab) on-backtab] [(enter) on-enter]
             [(escape) on-escape] [(up) on-up] [(down) on-down]
             [(left) on-left] [(right) on-right] [(del) on-delete]
             [(insert) on-insert] [(home) on-home] [(end) on-end]
             [(pageup) on-pageup] [(pagedown) on-pagedown]
             [else #f])]
          [else #f]))

  ;; 可打印字符（无 Ctrl/Alt）视为文本
  (define (text-key? key mods)
    (and (char? key) (not (mods-ctrl? mods)) (not (mods-alt? mods))))

  (lambda (ev)
    (match ev
      [(null-event)
       (if on-null (on-null) (any ev))]

      [(resize-event rows cols)
       (if on-resize (on-resize rows cols) (any ev))]

      [(paste-event bytes text)
       (cond [on-paste (on-paste bytes)]
             [on-text (on-text text)]
             [else (any ev)])]

      [(mouse-event action button x y mods)
       (if on-mouse
           (on-mouse action button x y mods)
           (any ev))]

      [(key-event key mods)
       (define shortcut (and (no-mods? mods) (shortcut-handler key)))
       (cond [shortcut (shortcut)]
             [(and (text-key? key mods) on-text) (on-text (string key))]
             [on-key (on-key key mods)]
             [else (any ev)])]

      [(other-event _ _ _) (any ev)]
      [_ (any ev)])))

;; ─── 事件循环（宏：编译时展开，事件广播给所有 handler）───
;; handler 是 (-> event? any) 函数，如 (build-input ...) 的返回值。
(define-syntax loop-input
  (syntax-rules ()
    [(_ handler ...)
     (let event-loop ()
       (define ev (read-event))
       (handler ev) ...
       (event-loop))]))

(define-syntax loop-input-noblock
  (syntax-rules ()
    [(_ handler ...)
     (let event-loop ()
       (define ev (read-event-noblock))
       (handler ev) ...
       (event-loop))]))

;; ─── 带停止条件的事件循环 ───
;; stop? 是一个表达式，每次循环后求值，为 #t 时退出
(define-syntax loop-input/stop
  (syntax-rules ()
    [(_ stop? handler ...)
     (let event-loop ()
       (define ev (read-event))
       (handler ev) ...
       (unless stop? (event-loop)))]))

(define-syntax loop-input-noblock/stop
  (syntax-rules ()
    [(_ stop? handler ...)
     (let event-loop ()
       (define ev (read-event-noblock))
       (handler ev) ...
       (unless stop? (event-loop)))]))
