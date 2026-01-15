#lang racket

(require "../lib.rkt"
         "../lib_extern.rkt"
         "../key.rkt"
         "../mouse.rkt")

;; 格式化鼠标事件为可读字符串
(define (format-mouse-event evt)
  (cond
    [(eq? evt 'mouse-get-failed)
     "mouse: failed to read"]

    [(list? evt)
     (define key (get-mouse-event-key evt))
     (define id  (get-mouse-event-id evt))
     (cond
       ;; 滚轮事件
       [(member key '(mouse-wheel-up mouse-wheel-down))
        (format "mouse: ~a (id=~a)" key id)]

       ;; 普通点击/移动事件
       [else
        (define x (get-mouse-event-x evt))
        (define y (get-mouse-event-y evt))
        (format "mouse: ~a at (x=~a, y=~a) [id=~a]" key x y id)])]

    [else
     (format "mouse: unknown event ~v" evt)]))

;; 主循环
(define (main-loop)
  (clear)
  (mvaddstr/xy 0 0 "Press keys or click mouse (q/ESC to quit):")
  (refresh)

  (let loop ()
    ;封装的getch会将字符以racket符号形式返回
    ;支持大小写 ‘a 'A
    ;支持鼠标 ’mouse
    ;不支持ctrl+ alt+ 修饰键,建议写成命令式像vim：那样
    (define k (get-key))

    (cond
      ;; 退出条件
      [(or (eq? k 'q) (eq? k 'esc))
       (void)]

      ;; 鼠标事件：特殊处理
      [(eq? k 'mouse)
       (define mevt (get-mouse-event))
       (move 1 0)
       (clrtoeol)
       (addstr (format-mouse-event mevt))
       (refresh)
       (loop)]

      ;; 普通按键
      [else
       (move 1 0)
       (clrtoeol)
       (when k
         (addstr (format "key: ~a" k)))
       (refresh)
       (loop)])))

;; 启动
(with-ncurses
    main-loop)