#lang racket
;; =============================================================================
;; build-input — 输入事件分发器（简化 API）
;;
;; 提供 build-input 函数，用户无需关心 input.rkt 的底层事件判断细节。
;; 只需声明"当 X 事件发生时调用什么函数"即可。
;;
;; 用法:
;;
;;   (require "build-input.rkt")
;;
;;   (define handler
;;     (build-input
;;       #:char      (lambda (ch) (printf "按键: ~a~n" (integer->char ch)))
;;       #:up        (lambda ()  (cursor-up 1))
;;       #:resize    (lambda (rows cols) (redraw rows cols))
;;       #:any       (lambda (type data mods) (printf "未处理: ~a~n" type))))
;;
;;   (loop-input handler)
;;
;; 所有关键字参数均为可选。handler 签名:
;;
;;   #:char       (lambda (ch) ...)               ch: integer (ascii byte值)
;;   #:utf-char   (lambda (str) ...)              str: string
;;   #:ctrl       (lambda (ch) ...)               ch: char (#\A-#\Z)
;;   #:alt        (lambda (ch) ...)               ch: char
;;   #:mod        (lambda (ch ctrl? alt?) ...)    Ctrl+Alt+char
;;   #:tab/space/enter/backspace/escape  (lambda () ...)
;;   #:up/down/left/right               (lambda () ...)
;;   #:delete/insert/home/end/pageup/pagedown  (lambda () ...)
;;   #:mouse-press   (lambda (button x y modifiers) ...)
;;   #:mouse-release (lambda (button x y modifiers) ...)   button: 'left/'middle/'right
;;   #:mouse-move    (lambda (x y modifiers) ...)
;;   #:mouse-scroll  (lambda (dir x y modifiers) ...)      dir: 'up/'down
;;   #:paste      (lambda (data) ...)             data: bytes
;;   #:resize     (lambda (rows cols) ...)
;;   #:null       (lambda () ...)                 无输入事件
;;   #:any        (lambda (type data mods) ...)   兜底（未匹配的事件）
;;
;; 优先级顺序（内置保证，用户无需关心）:
;;   null > resize > paste > mouse
;;   > tab/space/enter/backspace/escape
;;   > up/down/left/right > del/insert/home/end/pageup/pagedown
;;   > ctrl > alt > mod > utf8 > char
;;   > any
;; =============================================================================
(require "input.rkt" "../ansi/ansi-var.rkt" "../ansi/input-var.rkt")

(provide build-input loop-input loop-input-noblock)

(define (build-input
          #:char [on-char #f]
          #:utf-char [on-utf-char #f]
          #:ctrl [on-ctrl #f]
          #:alt [on-alt #f]
          #:mod [on-mod #f]
          #:tab [on-tab #f]
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
          #:pagedown [on-pagedown #f]
          #:mouse-press [on-mouse-press #f]
          #:mouse-release [on-mouse-release #f]
          #:mouse-move [on-mouse-move #f]
          #:mouse-scroll [on-mouse-scroll #f]
          #:paste [on-paste #f]
          #:resize [on-resize #f]
          #:any [on-any #f]
          #:null [on-null #f])

  ;; 辅助：处理 EVENT-KEY 类型的子分发（特殊键 vs 普通字符）
  (define (dispatch-key b)
    (cond [(and on-tab (= b TAB)) (on-tab)]
          [(and on-space (= b SPACE)) (on-space)]
          [(and on-enter (memv b (list LF CR))) (on-enter)]
          [(and on-backspace (memv b (list BACKSPACE DELETE))) (on-backspace)]
          [(and on-escape (= b ESC)) (on-escape)]
          [on-char
           (on-char b)]
          [on-any
           (on-any EVENT-KEY (bytes b) #f)]
          [else (void)]))

  ;; 辅助：处理 'mouse 类型的子分发
  ;; 注意：match 的裸符号是变量绑定，需用 ' 引用的字面符号
  (define (dispatch-mouse detail)
    (match (car detail)
      ['press
       (if on-mouse-press
           (on-mouse-press (cadr detail) (caddr detail)
                           (cadddr detail) (last detail))
           (on-any-and-null EVENT-MOUSE detail #f))]
      ['release
       (if on-mouse-release
           (on-mouse-release (cadr detail) (caddr detail)
                             (cadddr detail) (last detail))
           (on-any-and-null EVENT-MOUSE detail #f))]
      ['move
       (if on-mouse-move
           (on-mouse-move (caddr detail) (cadddr detail) (last detail))
           (on-any-and-null EVENT-MOUSE detail #f))]
      ['scroll
       (if on-mouse-scroll
           (on-mouse-scroll (caddr detail) (cadddr detail)
                            (car (cddddr detail)) (last detail))
           (on-any-and-null EVENT-MOUSE detail #f))]
      [_ (on-any-and-null EVENT-MOUSE detail #f)]))

  ;; 兜底：any 或静默
  (define (on-any-and-null t d m)
    (when on-any (on-any t d m)))

  ;; ─── 主分发：case 做 O(1) type → handler 映射 ───
  ;; 注意：case 需用裸符号，不可用变量（case 不 evaluate 分支值）
  (lambda (type data mods)
    (case type
      [(null) (if on-null (on-null) (on-any-and-null type data mods))]
      [(resize) (if on-resize (on-resize (car data) (cdr data))
                    (on-any-and-null type data mods))]
      [(paste) (if on-paste (on-paste data)
                   (on-any-and-null type data mods))]
      [(mouse) (dispatch-mouse data)]
      [(key)
       (if (and (bytes? data) (= (bytes-length data) 1))
           (dispatch-key (bytes-ref data 0))
           (on-any-and-null EVENT-KEY data #f))]
      [(up) (if on-up (on-up) (on-any-and-null type data mods))]
      [(down) (if on-down (on-down) (on-any-and-null type data mods))]
      [(left) (if on-left (on-left) (on-any-and-null type data mods))]
      [(right) (if on-right (on-right) (on-any-and-null type data mods))]
      [(del) (if on-delete (on-delete) (on-any-and-null type data mods))]
      [(insert) (if on-insert (on-insert) (on-any-and-null type data mods))]
      [(home) (if on-home (on-home) (on-any-and-null type data mods))]
      [(end) (if on-end (on-end) (on-any-and-null type data mods))]
      [(pageup) (if on-pageup (on-pageup) (on-any-and-null type data mods))]
      [(pagedown) (if on-pagedown (on-pagedown) (on-any-and-null type data mods))]
      [(ctrl)
       (let ([ch (ctrl->char data)])
         (if ch
             (if on-ctrl (on-ctrl ch) (on-any-and-null type data mods))
             (on-any-and-null EVENT-CTRL data #f)))]
      [(alt)
       (let ([b (alt->char data)])
         (if b
             (if on-alt (on-alt (integer->char b)) (on-any-and-null type data mods))
             (on-any-and-null EVENT-ALT data #f)))]
      [(mod-seq)
       (let ([ch (mod-seq->char data)])
         (if ch
             (if on-mod (on-mod (integer->char ch) (car mods) (cdr mods))
                 (on-any-and-null type data mods))
             (on-any-and-null EVENT-MOD data mods)))]
      [(utf8)
       (let ([str (event->string data)])
         (if (positive? (string-length str))
             (if on-utf-char (on-utf-char str) (on-any-and-null type data mods))
             (on-any-and-null EVENT-UTF8 data #f)))]
      [else (on-any-and-null type data mods)])))

;; ─── 事件循环（宏：编译时展开，事件广播给所有 handler）───
(define-syntax loop-input
  (syntax-rules ()
    [(_ handler ...)
     (let event-loop ()
       (let-values ([(type data mods) (read-event)])
         (handler type data mods) ...
         (event-loop)))]))

(define-syntax loop-input-noblock
  (syntax-rules ()
    [(_ handler ...)
     (let event-loop ()
       (let-values ([(type data mods) (read-event-noblock)])
         (handler type data mods) ...
         (event-loop)))]))

