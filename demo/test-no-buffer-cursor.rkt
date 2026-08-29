#lang racket

(require "../main.rkt"
         "../base/io/build-input.rkt")

(with-tui-nobuffer
 (λ ()
   (screen-clear)

   (define running? #t)

  (define handler
    (build-input
      ;; ── 空格：在当前光标位置打印 row,col ──
      #:space (lambda ()
                (put-string (format "(~a,~a)" current-cursor-row current-cursor-col)))

      ;; ── 方向键：移动光标 ──
      #:up    (lambda () (cursor-up 1))
      #:down  (lambda () (cursor-down 1))
      #:left  (lambda () (cursor-left 1))
      #:right (lambda () (cursor-right 1))

      ;; ── 回车：换行 ──
      #:enter (lambda () (put-newline))

      ;; ── q 退出 ──
      #:char  (lambda (ch)
                (when (= ch (char->integer #\q))
                  (set! running? #f)))

      ;; ── 其他键忽略 ──
      #:any   (lambda (type data mods) (void))))

  (let loop ()
    (when running?
      (let-values ([(type data mods) (read-event)])
        (handler type data mods))
      (loop)))))
