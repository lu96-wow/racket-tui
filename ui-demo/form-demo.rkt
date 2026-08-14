#lang racket

;; input + bool-button + button 组合 demo
;; 运行: racket ui-demo/form-demo.rkt
;; 在输入框打字（初始聚焦）、Enter 提交、Tab 切到开关/按钮、q 退出

(require "../ui/main.rkt")

(struct model (name toggle log) #:transparent)

(define (update st msg)
  (match msg
    [(list 'name t)   (struct-copy model st [name t])]
    [(list 'submit t) (struct-copy model st [log (format "submitted: ~a" t)])]
    ['toggle          (struct-copy model st [toggle (not (model-toggle st))])]
    [_ st]))

(define (view st)
  (vstack
   (child (text " Form Demo " #:style 'heading) #:min 1 #:max 1)

   (child (text " name: " #:style 'info) #:min 1 #:max 1)
   (child
    (input #:value (model-name st)
           #:on-change (λ (t) (list 'name t))
           #:on-submit (λ (t) (list 'submit t))
           #:placeholder "type name..."
           #:key 'name-input)
    #:min 1 #:max 1)

   (child
    (bool-button (format " Enabled: ~a " (model-toggle st))
                 #:value (model-toggle st)
                 #:on-toggle 'toggle
                 #:key 'toggle)
    #:min 1 #:max 1)

   (child
    (button "Submit" #:on-activate (list 'submit (model-name st)) #:key 'submit-btn)
    #:min 1 #:max 1)

   (child (text (format " log: ~a " (model-log st)) #:style 'info)
          #:weight 2 #:min 3)

   (child (text " q=quit " #:style 'dim) #:min 1 #:max 1)))

(run-app
 #:init   (model "" #f "none")
 #:update update
 #:view   view
 #:keymap (list (cons #\q      msg-quit)
                (cons 'tab     msg-focus-next)
                (cons 'backtab msg-focus-prev)))
