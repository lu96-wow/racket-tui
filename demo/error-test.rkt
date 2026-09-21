#lang racket

;; 故意报错示例：观察 with-tui 中抛出异常时的行为。
;;
;; 为什么不能直接让 with-tui 里的异常往外冒？
;;
;; Racket 的默认错误处理器会在 dynamic-wind 的 after-thunk **之前**
;; 打印错误。也就是说：
;;   1. body 抛错 → 错误先被打印到【仍在 alt 缓冲 + raw 模式】的终端。
;;   2. 之后才跑 with-tui 的清理 → buffer-alt-disable 发 ESC[?1049l
;;      切回主屏，把刚打印的错误连同 alt 屏内容一起丢弃。
;; 结果：你看不到任何报错。
;;
;; 正确做法：在 with-tui 内部先把异常接住，等 with-tui 退出、
;; 终端完全恢复后，再重新抛出，让默认处理器在主屏上打印。
;;
;; 运行： racket demo/error-test.rkt
;; 按任意键触发错误。

(require "../main.rkt")

(define pending-error #f)

(with-tui
 (λ ()
   ;; 内层接住异常，但不打印，只暂存
   (with-handlers ([exn? (λ (e) (set! pending-error e))])
     (screen-clear)
     (put-at 2 2 "with-tui error demo")
     (put-at 4 2 "press any key to raise an error...")
     (flush!)

     ;; 等待一次按键，方便看清正常画面
     (let loop ()
       (define ev (read-event))
       (unless (event? ev) (loop)))

     (put-at 6 2 "raising error now...")
     (flush!)

     ;; ── 一定会报错 ─────────────────────────────────────────
     ;; 用 error 抛出 exn:fail，带消息和 irritants。
     (error "demo/error-test.rkt: 这是 with-tui 内故意抛出的错误"
            'irritant-1
            'irritant-2))))

;; 此时终端已恢复（离开 alt 缓冲、退出 raw 模式），再抛出即可被看到
(when pending-error
  (raise pending-error))
