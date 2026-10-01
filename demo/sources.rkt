#lang racket

;; ════════════════════════════════════════════════════════════════
;; 多事件源手动测试 —— with-tui + on-source
;;
;;   racket demo/sources.rkt        （需要在真实终端里跑）
;;
;; 三个后台源各自一条 async-channel，全部经 on-source 注册：
;;   源 A  tick   每 500ms  +1
;;   源 B  ping   每 900ms  +1
;;   源 C  job    1.5s 后一次性置为“完成 ✓”
;; 键盘输入照常（最近按键一行会更新），Ctrl-Q 退出。
;;
;; 期望：三个计数各自按节奏跳动，打字实时回显，Ctrl-Q 干净退出、
;;       终端恢复原状。若键盘没反应，说明 event? 路由坏了。
;; ════════════════════════════════════════════════════════════════

(require "../main.rkt"
         racket/async-channel)

;; ── 共享状态（源处理器和键盘处理器都会改）────────────────────
(define ticks    (box 0))
(define pings    (box 0))
(define job      (box "进行中…"))
(define last-key (box "（无）"))

(define (redraw)
  (screen-clear)
  (cursor-move 2 3)
  (put-rgb-fg 255 255 0 "多事件源手动测试  (with-tui + on-source)")
  (cursor-move 4 3)
  (put-256-fg 46 (format "源 A  tick      每 500ms : ~a 次" (unbox ticks)))
  (cursor-move 5 3)
  (put-256-fg 46 (format "源 B  ping      每 900ms : ~a 次" (unbox pings)))
  (cursor-move 6 3)
  (put-256-fg 46 (format "源 C  后台计算  1.5s    : ~a" (unbox job)))
  (cursor-move 8 3)
  (put-256-fg 208 (format "键盘  最近按键          : ~a" (unbox last-key)))
  (cursor-move 10 3)
  (put-string "Ctrl-Q 退出 · 随便打字，上一行应实时更新")
  (flush-output))

;; ── 三个后台源（channel + 生产者线程）────────────────────────
(define tick-ch (make-async-channel))
(define ping-ch (make-async-channel))
(define job-ch  (make-async-channel))

(define (start-producers!)
  (thread (λ () (let loop () (sleep 0.5) (async-channel-put tick-ch #t) (loop))))
  (thread (λ () (let loop () (sleep 0.9) (async-channel-put ping-ch #t) (loop))))
  (thread (λ () (sleep 1.5) (async-channel-put job-ch "完成 ✓"))))

(with-tui
 (λ ()
   (define quit? #f)                      ; #f = 继续；#t = 退出（loop-input/stop 语义）

   (on-source tick-ch (λ (_) (set-box! ticks (add1 (unbox ticks))) (redraw)))
   (on-source ping-ch (λ (_) (set-box! pings (add1 (unbox pings))) (redraw)))
   (on-source job-ch  (λ (v) (set-box! job v) (redraw)))

   (start-producers!)
   (redraw)

   (loop-input/stop
    quit?
    (build-input
     #:text (λ (s) (set-box! last-key (format "字符 ~s" s)) (redraw))
     #:key  (λ (k m)
              (when (and (char? k) (char=? (char-downcase k) #\q)
                         (mods? m) (mods-ctrl? m))
                (set! quit? #t))
              (set-box! last-key (format "~s  mods=~a" k
                                         (if (mods? m) (mods->list m) m)))
              (redraw))
     #:mouse (λ (action button x y m)
               (set-box! last-key (format "鼠标 ~a ~a (~a,~a)" action button x y))
               (redraw))
     #:any  (λ (ev) (set-box! last-key (format "~a" ev)) (redraw))))))
