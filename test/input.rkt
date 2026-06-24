#lang racket
(require "../main.rkt"
         "../build-input.rkt")

(with-tui-nobuffer
    (screen-clear)
  (put-string "╔══════════════════════════════════════╗") (put-newline)
  (put-string "║   输入 API 测试 (build-input 简化版)   ║") (put-newline)
  (put-string "║   按 q 退出                           ║") (put-newline)
  (put-string "╚══════════════════════════════════════╝") (put-newline)
  (put-newline)
  (put-string "按下任意键、移动鼠标或粘贴内容查看事件...") (put-newline)
  (put-newline)
  (put-string "--- 鼠标状态 ---") (put-newline)
  (define mouse-status-line current-cursor-row)
  (put-string "等待鼠标事件...") (put-newline)
  (put-string "---------------") (put-newline)
  (put-newline)
  (put-string "--- 粘贴状态 ---") (put-newline)
  (define paste-status-line current-cursor-row)
  (put-string "等待粘贴事件...") (put-newline)
  (put-string "---------------") (put-newline)
  (put-newline)
  (define running? #t)
  (define mouse-count 1)
  (define paste-count 1)
  (define (update-status-line line . parts)
    (define saved-row current-cursor-row)
    (define saved-col current-cursor-col)
    (cursor-move line 1)
    (put-string "                                        ")
    (cursor-move line 1)
    (for ([p parts]) (put-string p))
    (cursor-move saved-row saved-col)
    (flush-output))
  (define (log-event . parts)
    (put-string "[")
    (for ([p parts]) (put-string p))
    (put-string "]")
    (put-newline))
  (define handler
    (build-input
      #:null (lambda () (void))
      #:resize (lambda (rows cols)
                 (log-event (format "resize: ~ax~a" rows cols)))
      #:paste (lambda (data)
                (set! paste-count (add1 paste-count))
                (define cnt (bytes-length data))
                (define preview (event->string data))
                (define short
                  (if (> (string-length preview) 30)
                      (format "\"~a...\"" (substring preview 0 30))
                      (format "\"~a\"" preview)))
                (update-status-line paste-status-line
                                    (format "粘贴 #~a: ~a 字节" paste-count cnt)
                                    (if (> (string-length preview) 0)
                                        (format " | ~a" short)
                                        ""))
                (log-event (format "paste: ~a 字节" cnt)
                           (if (> (string-length preview) 0)
                               (format " | ~a" short)
                               "")
                           (if (> cnt 0)
                               (let* ([hex-n (min cnt 8)]
                                      [hex-str
                                       (apply string-append
                                              (for/list ([i (in-range hex-n)])
                                                (format " ~x"
                                                        (bytes-ref data i))))])
                                 (format " | hex:~a~a" hex-str
                                         (if (> cnt 8) " ..." "")))
                               "")))
      #:mouse-press (lambda (btn x y mods)
                      (set! mouse-count (add1 mouse-count))
                      (update-status-line
                       mouse-status-line
                       (format "鼠标 #~a: 按下 ~a 位置:(~a,~a)"
                               mouse-count btn x y)
                       (if (> mods 0)
                           (format " 修饰键:~a" mods)
                           ""))
                      (log-event (format "mouse press ~a (~a,~a)" btn x y)
                                 (if (> mods 0)
                                     (format " mods:~a" mods)
                                     "")))
      #:mouse-release (lambda (btn x y mods)
                        (set! mouse-count (add1 mouse-count))
                        (update-status-line
                         mouse-status-line
                         (format "鼠标 #~a: 释放 ~a 位置:(~a,~a)"
                                 mouse-count btn x y)
                         (if (> mods 0)
                             (format " 修饰键:~a" mods)
                             ""))
                        (log-event (format "mouse release ~a (~a,~a)" btn x y)
                                   (if (> mods 0)
                                       (format " mods:~a" mods)
                                       "")))
      #:mouse-move (lambda (x y mods)
                     (set! mouse-count (add1 mouse-count))
                     (update-status-line
                      mouse-status-line
                      (format "鼠标 #~a: 移动 位置:(~a,~a)"
                              mouse-count x y)
                      (if (> mods 0)
                          (format " 修饰键:~a" mods)
                          ""))
                     (log-event (format "mouse move (~a,~a)" x y)
                                (if (> mods 0)
                                    (format " mods:~a" mods)
                                    "")))
      #:mouse-scroll (lambda (dir x y mods)
                       (set! mouse-count (add1 mouse-count))
                       (update-status-line
                        mouse-status-line
                        (format "鼠标 #~a: 滚轮 ~a 位置:(~a,~a)"
                                mouse-count dir x y)
                        (if (> mods 0)
                            (format " 修饰键:~a" mods)
                            ""))
                       (log-event (format "mouse scroll ~a (~a,~a)" dir x y)
                                  (if (> mods 0)
                                      (format " mods:~a" mods)
                                      "")))
      #:tab       (lambda () (log-event "Tab"))
      #:space     (lambda () (log-event "Space"))
      #:enter     (lambda () (log-event "Enter"))
      #:backspace (lambda () (log-event "Backspace"))
      #:escape    (lambda () (log-event "ESC"))
      #:up    (lambda () (log-event "Up"))
      #:down  (lambda () (log-event "Down"))
      #:left  (lambda () (log-event "Left"))
      #:right (lambda () (log-event "Right"))
      #:delete     (lambda () (log-event "Delete"))
      #:insert     (lambda () (log-event "Insert"))
      #:home       (lambda () (log-event "Home"))
      #:end        (lambda () (log-event "End"))
      #:pageup     (lambda () (log-event "PgUp"))
      #:pagedown   (lambda () (log-event "PgDn"))
      #:ctrl (lambda (ch) (log-event (format "Ctrl+~a" ch)))
      #:alt  (lambda (ch) (log-event (format "Alt+~a" ch)))
      #:mod  (lambda (ch ctrl? alt?)
               (log-event (format "~a~a~a"
                                  (if ctrl? "Ctrl+" "")
                                  (if alt? "Alt+" "")
                                  ch)))
      #:utf-char (lambda (str)
                   (log-event (format "utf8: ~a" str)))
      #:char (lambda (ch)
               (cond [(= ch (char->integer #\q))
                      (log-event (format "q → 退出"))
                      (set! running? #f)]
                     [(<= 32 ch 126)
                      (log-event (format "key '~a'" (integer->char ch)))]
                     [else
                      (log-event (format "key byte=~a" ch))]))
      #:any (lambda (type data mods)
              (match type
                [(quote seq)
                 (log-event
                  (apply string-append
                         "seq:"
                         (for/list ([b (in-bytes data)])
                           (format " ~a" b))))]
                [(quote mod-seq)
                 (define ch (mod-seq->char data))
                 (log-event
                  (format "mod-seq:~a~a ~a"
                          (if (car mods) " Ctrl" "")
                          (if (cdr mods) " Alt" "")
                          (if ch (integer->char ch) "?")))]
                [else
                 (log-event (format "~a" type))]))))
  ;; read-event 内部使用 select() 阻塞等待, 零 CPU 空转
  ;; 不需要 change-noblock / sleep 轮询
  (let loop ()
    (when running?
      (let-values ([(type data mods) (read-event)])
        (handler type data mods))
      (loop))))
