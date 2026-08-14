#lang racket

;; 全组件手动测试 demo
;; 运行: racket ui-demo/all-components-demo.rkt
;;
;; 包含: text / list-box / output(折叠) / input / text-area / bool-button / button
;; 交互:
;;   ↑↓/PageUp/PageDown 在列表选项目
;;   Tab/Shift-Tab 切焦点
;;   在 name 输入框打字 + Enter 提交
;;   在 Notes 多行框输入（Escape 换行）
;;   点击 Log 面板的 ▼/▶ 折叠头
;;   Submit/Clear 按钮、Enabled 开关
;;   q 退出

(require "../ui/main.rkt")

(struct model (items selected log folded name notes enabled? last-action)
  #:transparent)

(define initial-log
  (list "ready."
        (fold-block 'errors (cons "Errors" 'error) (list "e1" "e2"))
        (fold-block 'warn   (cons "Warnings" 'warning) (list "w1" "w2"))
        "type / click around"))

(define (update st msg)
  (match msg
    [(list 'select i)
     (struct-copy model st
       [selected i]
       [last-action (format "selected item ~a" i)])]
    [(list 'name t)
     (struct-copy model st [name t])]
    [(list 'submit t)
     (struct-copy model st
       [log (append (model-log st) (list (cons (format "> ~a" t) 'success)))]
       [last-action (format "submitted: ~a" t)])]
    [(list 'notes t)
     (struct-copy model st [notes t])]
    ['toggle
     (struct-copy model st
       [enabled? (not (model-enabled? st))]
       [last-action (format "enabled: ~a" (not (model-enabled? st)))])]
    ['clear
     (struct-copy model st [log '()] [last-action "log cleared"])]
    [(list 'toggle-fold id)
     (struct-copy model st
       [folded (if (member id (model-folded st))
                   (remove id (model-folded st))
                   (cons id (model-folded st)))]
       [last-action (format "fold ~a toggled" id)])]
    [_ st]))

(define (view st)
  (vstack
   ;; 标题
   (child (text " All Components Demo " #:style 'heading) #:min 1 #:max 1)

   ;; 左侧列表 + 右侧日志（含折叠）
   (child
    (hstack
     (child
      (panel
       (list-box #:items (model-items st)
                 #:selected (model-selected st)
                 #:on-select (λ (i) (list 'select i))
                 #:key 'list)
       #:title "Items")
      #:weight 1 #:min 6)
     (child
      (panel
       (output #:lines (model-log st)
               #:folded (model-folded st)
               #:on-toggle-fold (λ (id) (list 'toggle-fold id))
               #:key 'log)
       #:title "Log")
      #:weight 2 #:min 6))
    #:weight 6 #:min 6)

   ;; 输入 + 开关 + 按钮
   (child
    (hstack
     (child
      (input #:value (model-name st)
             #:on-change (λ (t) (list 'name t))
             #:on-submit (λ (t) (list 'submit t))
             #:placeholder "type name..."
             #:key 'name-input)
      #:weight 3)
     (child
      (bool-button (format " Enabled: ~a " (model-enabled? st))
                   #:value (model-enabled? st)
                   #:on-toggle 'toggle
                   #:key 'toggle)
      #:weight 2)
     (child
      (button "Submit" #:on-activate (list 'submit (model-name st)) #:key 'submit-btn)
      #:weight 1)
     (child
      (button "Clear" #:on-activate 'clear #:key 'clear-btn)
      #:weight 1))
    #:min 1 #:max 1)

   ;; 多行输入
   (child
    (text-area #:value (model-notes st)
               #:on-change (λ (t) (list 'notes t))
               #:placeholder "notes (Escape = newline)..."
               #:key 'notes)
    #:weight 3 #:min 3)

   ;; 状态栏
   (child (text (format " ~a " (model-last-action st)) #:style 'dim)
          #:min 1 #:max 1)))

(run-app
 #:init   (model (for/list ([i (in-range 1 11)]) (format "item ~a" i))
                 0 initial-log '() "" "" #f "welcome")
 #:update update
 #:view   view
 #:keymap (list (cons #\q      msg-quit)
                (cons 'tab     msg-focus-next)
                (cons 'backtab msg-focus-prev)))
