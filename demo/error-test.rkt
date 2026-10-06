#lang racket

;; 故意报错示例：观察 with-tui 中抛出异常时的行为。
;;
;; with-tui 保证：body 抛出的异常，一定是在【终端已完全恢复】之后才向外传播。
;; 它会在 dynamic-wind 内部先接住异常、走完清理（buffer-alt-disable 切回主屏、
;; exit-raw-mode! 恢复 termios），再把异常原样重新抛出。
;;
;; 为什么需要这样？Racket 的默认错误处理器是原地打印、不退栈的，会在
;; dynamic-wind 的 after-thunk **之前**运行。若让异常直接冒出去：
;;   1. body 抛错 → 错误先被打印到【仍在 alt 缓冲 + raw 模式】的终端。
;;   2. 之后才跑 with-tui 的清理 → buffer-alt-disable 发 ESC[?1049l
;;      切回主屏，把刚打印的错误连同 alt 屏内容一起丢弃。
;; 结果：你看不到任何报错。
;;
;; 现在无需手动 catch/re-raise，直接 (error ...) 即可 —— 报错会打印在
;; 恢复后的主屏上。
;;
;; 运行： racket demo/error-test.rkt
;; 按任意键触发错误。

(require "../main.rkt")

(with-tui
 (λ ()
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
   ;; with-tui 会先完成清理（切回主屏、退出 raw 模式），再把它重新抛出，
   ;; 因此下面的错误信息会落在这块已恢复的主屏上。
   (error "demo/error-test.rkt: 这是 with-tui 内故意抛出的错误"
          'irritant-1
          'irritant-2)))
