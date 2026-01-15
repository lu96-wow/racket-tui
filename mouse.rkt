#lang racket
(require "lib_help.rkt")

;; 原始事件获取（保持不变）
(define (get-mouse-event)
  (define s (help_get_mouse_event_string))
  (define parts (string-split s))
  (define event-type (car parts))

  (cond
    [(string=? event-type "mouse-get-failed")
     'mouse-get-failed]

    ;; 滚轮：mouse-wheel-up 0
    [(member event-type '("mouse-wheel-up" "mouse-wheel-down"))
     (list (string->symbol event-type) (cons 'id (string->number (cadr parts))))]

    ;; 普通事件：mouse-left-click 0 10 5
    [else
     (let ([id (string->number (cadr parts))]
           [x  (string->number (caddr parts))]
           [y  (string->number (cadddr parts))])
       (list (string->symbol event-type)
             (cons 'id id)
             (cons 'x x)
             (cons 'y y)))]))

;; 提取事件类型（key）
(define (get-mouse-event-key evt)
  (cond
    [(eq? evt 'mouse-get-failed) evt]
    [(and (list? evt) (not (null? evt)))
     (car evt)]
    [else
     (error 'get-mouse-event-key "invalid mouse event: ~v" evt)]))

;; 提取设备 ID
(define (get-mouse-event-id evt)
  (cond
    [(eq? evt 'mouse-get-failed)
     (error 'get-mouse-event-id "cannot get id from failed event")]
    [(and (list? evt) (>= (length evt) 2))
     (let ([id-pair (cadr evt)])
       (if (and (pair? id-pair) (eq? (car id-pair) 'id))
           (cdr id-pair)
           (error 'get-mouse-event-id "malformed event: missing (id . ...) pair")))]
    [else
     (error 'get-mouse-event-id "invalid mouse event structure: ~v" evt)]))

;; 可选：提取 x/y（未来扩展用）
(define (get-mouse-event-x evt)
  (if (member (get-mouse-event-key evt)
              '(mouse-wheel-up mouse-wheel-down))
      (error 'get-mouse-event-x "wheel events have no x coordinate")
      (let ([x-pair (caddr evt)])
        (if (and (pair? x-pair) (eq? (car x-pair) 'x))
            (cdr x-pair)
            (error 'get-mouse-event-x "missing (x . ...) pair")))))

(define (get-mouse-event-y evt)
  (if (member (get-mouse-event-key evt)
              '(mouse-wheel-up mouse-wheel-down))
      (error 'get-mouse-event-y "wheel events have no y coordinate")
      (let ([y-pair (cadddr evt)])
        (if (and (pair? y-pair) (eq? (car y-pair) 'y))
            (cdr y-pair)
            (error 'get-mouse-event-y "missing (y . ...) pair")))))

;; 导出
(provide get-mouse-event
         get-mouse-event-key
         get-mouse-event-id
         get-mouse-event-x
         get-mouse-event-y
         )