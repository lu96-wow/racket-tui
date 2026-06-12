#lang racket
(require "../main.rkt" "../output-styles.rkt")

(with-tui-nobuffer
    (set-buffered-mode!)
  (cursor-hide)
  ;; 批量构建整个界面
  (define screen
    (bytes-append
     format-screen-clear

     ;; 标题
     (format-styled-at 0 0 'title "=== TUI Demo ===\n\n")

     ;; 错误信息
     (format-styled-at 2 0 'error "Error: Invalid input\n")

     ;; 成功信息
     (format-styled-at 3 0 'success "Success: File loaded\n")

     ;; 普通文本 + 强调
     (format-cursor-move 5 0)
     (format-content "Press ")
     (format-styled-bold "q")
     (format-content " to quit, ")
     (format-styled-bold "t")
     (format-content " to change theme\n")

     ;; 自定义颜色
     (format-cursor-move 7 0)
     (format-styled-underline "Status: ")
     (format-styled 'warning "Running\n")))

  ;; 一次性输出
  (put-bytes screen)
  (flush!)

  ;; 事件循环
  (let loop ()
    (define-values (type data mods) (read-event))
    (cond
      [(event-key? type)
       (define b (event->byte data))
       (cond [(= b (char->integer #\q)) (void)]
             [(= b (char->integer #\t))
              (screen-clear)
              (put-at 1 2 "Theme changed")
              (loop)]
             [else (loop)])]
      [else (loop)])))
