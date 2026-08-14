#lang racket

;; text + button 组件交互 demo
;; 运行: racket ui-rebuild-demo/button-demo.rkt
;; 按键: Enter/Space/点击 = 激活按钮; Tab/Shift-Tab = 切焦点; q = 退出

(require "../ui-rebuild/main.rkt")

(struct model (count last) #:transparent)

(define (update st msg)
  (match msg
    ['inc (struct-copy model st [count (add1 (model-count st))] [last "inc"])]
    ['dec (struct-copy model st [count (sub1 (model-count st))] [last "dec"])]
    [_ st]))

(define (view st)
  (vstack
   (child (text (format " count: ~a " (model-count st)) #:style 'heading)
          #:min 1 #:max 1)
   (child (text (format " last: ~a " (model-last st)) #:style 'info)
          #:min 1 #:max 1)
   (child
    (hstack
     (child (button "Inc" #:on-activate 'inc #:key 'inc-btn) #:weight 1)
     (child (button "Dec" #:on-activate 'dec #:key 'dec-btn) #:weight 1))
    #:min 3)
   (child (text " q=quit  tab=focus  enter/space/click=activate " #:style 'dim)
          #:min 1 #:max 1)))

(run-app
 #:init   (model 0 "none")
 #:update update
 #:view   view
 #:keymap (list (cons #\q      msg-quit)
                (cons 'tab     msg-focus-next)
                (cons 'backtab msg-focus-prev)))
