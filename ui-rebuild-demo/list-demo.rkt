#lang racket

;; list + scrollbar 交互 demo
;; 运行: racket ui-rebuild-demo/list-demo.rkt
;; ↑↓ 选择；鼠标滚轮/滚动条拖动 滚动；q 退出

(require "../ui-rebuild/main.rkt")

(struct model (selected) #:transparent)
(define items (for/list ([i (in-range 1 21)]) (format "item ~a" i)))

(define (update st msg)
  (match msg
    [(list 'select i) (struct-copy model st [selected i])]
    [_ st]))

(define (view st)
  (vstack
   (child (text (format " Selected: ~a " (model-selected st)) #:style 'heading)
          #:min 1 #:max 1)
   (child
    (list-box #:items items
              #:selected (model-selected st)
              #:on-select (λ (i) (list 'select i))
              #:key 'list)
    #:weight 6 #:min 5)
   (child (text " ↑↓=选择  wheel/scrollbar=滚动  q=quit " #:style 'dim)
          #:min 1 #:max 1)))

(run-app
 #:init   (model 0)
 #:update update
 #:view   view
 #:keymap (list (cons #\q      msg-quit)
                (cons 'tab     msg-focus-next)
                (cons 'backtab msg-focus-prev)))
