#lang racket
(require "../main.rkt"
         "../build-input.rkt")

(with-tui-nobuffer
    ;; 清屏并显示初始信息
    (screen-clear)
  (put-string "=== Simple Cursor Test ===") (put-newline)
  (put-string "Arrow keys: move cursor") (put-newline)
  (put-string "q: quit") (put-newline)
  (put-string "Any other key: print at cursor") (put-newline)
  (put-string "=========================") (put-newline)
  (put-newline)

  ;; 光标初始位置（从 row=5 开始）
  (define start-row 5)
  (define start-col 1)
  (cursor-move start-row start-col)

  ;; 终端尺寸
  (define-values (term-rows term-cols) (get-window-size))

  ;; 在右下角固定显示光标位置
  (define (show-cursor-pos)
    (define saved-row current-cursor-row)
    (define saved-col current-cursor-col)
    ;; 状态行放在倒数第1行（最后一行），靠右
    (define status-row (sub1 term-rows))
    (define status-msg (format " row=~a col=~a " current-cursor-row current-cursor-col))
    (define status-col (max 0 (- term-cols (string-length status-msg))))
    ;; 移动到状态行，清空该行，打印信息，恢复光标
    (cursor-move status-row 0)
    (line-clear)
    (cursor-move status-row status-col)
    (put-string status-msg)
    (cursor-move saved-row saved-col))

  (show-cursor-pos)

  (define running? #t)

  (define handler
    (build-input
      #:null (lambda () (void))
      #:resize (lambda (rows cols)
                 (set! term-rows rows)
                 (set! term-cols cols))
      ;; 方向键 —— 移动光标
      #:up    (lambda () (cursor-up 1) (show-cursor-pos))
      #:down  (lambda () (cursor-down 1) (show-cursor-pos))
      #:left  (lambda () (cursor-left 1) (show-cursor-pos))
      #:right (lambda () (cursor-right 1) (show-cursor-pos))
      ;; backspace —— 左移并覆盖空格
      #:backspace (lambda ()
                    (cursor-left 1)
                    (put-char #\space)
                    (cursor-left 1)
                    (show-cursor-pos))
      ;; enter —— 换行
      #:enter (lambda ()
                (put-newline)
                (show-cursor-pos))
      ;; 普通字符 —— 在光标处打印
      #:char (lambda (ch)
               (cond [(= ch (char->integer #\q))
                      (set! running? #f)]
                     [(<= 32 ch 126)
                      (put-char (integer->char ch))
                      (show-cursor-pos)]
                     [else (void)]))
      ;; utf-8 字符
      #:utf-char (lambda (str)
                   (put-string str)
                   (show-cursor-pos))
      ;; ESC 退出
      #:escape (lambda () (set! running? #f))
      ;; 兜底
      #:any (lambda (type data mods) (void))))

  (let loop ()
    (when running?
      (change-noblock)
      (let-values ([(type data mods) (read-event)])
        (handler type data mods))
      (sleep 0.01)
      (loop))))
