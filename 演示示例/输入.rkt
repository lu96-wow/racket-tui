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
       [(member key '(mouse-wheel-up mouse-wheel-down))
        (format "mouse: ~a (id=~a)" key id)]
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
    (define k (get-key))

    (cond
      ;; 退出条件
      [(or (eq? k 'q) (eq? k 'esc))
       (void)]

      ;; 鼠标事件
      [(eq? k 'mouse)
       (define mevt (get-mouse-event))
       (move 1 0)
       (clrtoeol)
       (addstr (format-mouse-event mevt))
       (refresh)
       (loop)]

      ;; 新增：Unicode 字符输入
      [(eq? k 'unicode)
       (define ustr (get-last-unicode))
       (move 1 0)
       (clrtoeol)
       (if ustr
           (addstr (format "unicode: ~a" ustr))   ; ← 显示实际字符！
           (addstr "unicode: (decode failed)"))
       (refresh)
       (loop)]

      ;; 其他普通按键（ASCII、功能键等）
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