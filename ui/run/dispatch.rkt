#lang racket
;; 事件分发 — 按类型路由到对应处理器
;;
;; 职责:
;;   - resize → 广播所有组件
;;   - mouse  → mouse-router 处理 (dispatch-and-render 跳过)
;;   - 其他   → 键盘焦点组件

(require "../component.rkt")

(provide make-dispatcher)

(define (make-dispatcher specs focus render-all)
  (define (dispatch-and-render type data mods)
    (cond
      [(eq? type 'resize)
       (for ([s specs])
         ((component-handler (car s)) type data mods))]
      [(eq? type 'mouse)
       (void)]
      [else
       (when (unbox focus)
         ((component-handler (unbox focus)) type data mods))])
    (render-all))

  dispatch-and-render)
