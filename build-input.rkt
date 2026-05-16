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
;;   (let loop ()
;;     (let-values ([(type data mods) (read-event)])
;;       (handler type data mods)
;;       (loop)))
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
(require "input.rkt")

(provide build-input)

(define (build-input
         #:char       [on-char       #f]
         #:utf-char   [on-utf-char   #f]
         #:ctrl       [on-ctrl       #f]
         #:alt        [on-alt        #f]
         #:mod        [on-mod        #f]
         #:tab        [on-tab        #f]
         #:space      [on-space      #f]
         #:enter      [on-enter      #f]
         #:backspace  [on-backspace  #f]
         #:escape     [on-escape     #f]
         #:up         [on-up         #f]
         #:down       [on-down       #f]
         #:left       [on-left       #f]
         #:right      [on-right      #f]
         #:delete     [on-delete     #f]
         #:insert     [on-insert     #f]
         #:home       [on-home       #f]
         #:end        [on-end        #f]
         #:pageup     [on-pageup     #f]
         #:pagedown   [on-pagedown   #f]
         #:mouse-press   [on-mouse-press   #f]
         #:mouse-release [on-mouse-release #f]
         #:mouse-move    [on-mouse-move    #f]
         #:mouse-scroll  [on-mouse-scroll  #f]
         #:paste      [on-paste      #f]
         #:resize     [on-resize     #f]
         #:any        [on-any        #f]
         #:null       [on-null       #f])

  (lambda (type data mods)
    (cond
      [(and on-null (eq? type 'null))
       (on-null)]

      [(and on-resize (eq? type 'resize))
       (on-resize (car data) (cdr data))]

      [(and on-paste (eq? type 'paste))
       (on-paste data)]

      [(and (or on-mouse-press on-mouse-release on-mouse-move on-mouse-scroll)
            (eq? type 'mouse))
       (let* ([detail data]
              [action (car detail)])
         (match action
           ['press
            (when on-mouse-press
              (on-mouse-press (cadr detail)
                              (caddr detail)
                              (cadddr detail)
                              (last detail)))]
           ['release
            (when on-mouse-release
              (on-mouse-release (cadr detail)
                                (caddr detail)
                                (cadddr detail)
                                (last detail)))]
           ['move
            (when on-mouse-move
              (on-mouse-move (caddr detail)
                             (cadddr detail)
                             (last detail)))]
           ['scroll
            (when on-mouse-scroll
              (on-mouse-scroll (caddr detail)
                               (cadddr detail)
                               (car (cddddr detail))
                               (last detail)))]
           [_ (void)]))]

      [(and on-tab (eq? type 'key) (bytes? data)
            (= (bytes-length data) 1) (= (bytes-ref data 0) 9))
       (on-tab)]

      [(and on-space (eq? type 'key) (bytes? data)
            (= (bytes-length data) 1) (= (bytes-ref data 0) 32))
       (on-space)]

      [(and on-enter (eq? type 'key) (bytes? data)
            (= (bytes-length data) 1)
            (memv (bytes-ref data 0) (list 10 13)))
       (on-enter)]

      [(and on-backspace (eq? type 'key) (bytes? data)
            (= (bytes-length data) 1)
            (memv (bytes-ref data 0) (list 8 127)))
       (on-backspace)]

      [(and on-escape (eq? type 'key) (bytes? data)
            (= (bytes-length data) 1) (= (bytes-ref data 0) 27))
       (on-escape)]

      [(and on-up    (eq? type 'up))    (on-up)]
      [(and on-down  (eq? type 'down))  (on-down)]
      [(and on-left  (eq? type 'left))  (on-left)]
      [(and on-right (eq? type 'right)) (on-right)]

      [(and on-delete   (eq? type 'del))     (on-delete)]
      [(and on-insert   (eq? type 'insert))  (on-insert)]
      [(and on-home     (eq? type 'home))    (on-home)]
      [(and on-end      (eq? type 'end))     (on-end)]
      [(and on-pageup   (eq? type 'pageup))  (on-pageup)]
      [(and on-pagedown (eq? type 'pagedown)) (on-pagedown)]

      [(and on-ctrl (eq? type 'ctrl))
       (define ch (ctrl->char data))
       (when ch (on-ctrl ch))]

      [(and on-alt (eq? type 'alt))
       (define b (alt->char data))
       (when b (on-alt (integer->char b)))]

      [(and on-mod (eq? type 'mod-seq))
       (define ch (mod-seq->char data))
       (when ch
         (on-mod (integer->char ch) (car mods) (cdr mods)))]

      [(and on-utf-char (eq? type 'utf8))
       (define str (event->string data))
       (when (positive? (string-length str))
         (on-utf-char str))]

      [(and on-char (eq? type 'key) (bytes? data)
            (= (bytes-length data) 1))
       (define b (bytes-ref data 0))
       (unless (memv b (list 8 9 10 13 27 32 127))
         (on-char b))]

      [on-any (on-any type data mods)]

      [else (void)])))
