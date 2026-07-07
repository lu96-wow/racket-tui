#lang racket

(require "../main.rkt")

(with-tui
    (screen-clear)

  ;; 画边框参照
  (define w 70)
  (for ([i (in-range 1 w)])
    (put-at 0 i "-")
    (put-at 24 i "-"))
  (for ([i (in-range 1 24)])
    (put-at i 0 "|")
    (put-at i w "|"))

  ;; ====== 测试 format-fg-at（at: 不移动光标） ======
  (cursor-move 5 10)
  (put "BEFORE AT: cursor at (5,10)")
  (sleep 3)

  ;; 在屏幕中间输出红色文字，at 应该恢复光标
  (put-bytes (format-fg-at 12 25 1 "AT at (12,25) - cursor unchanged"))
  (sleep 3)
  (put "AFTER AT: still at (5,10) ~ correct!")
  (sleep 3)

  ;; ====== 测试 format-fg-at!（at!: 移动光标） ======
  (cursor-move 8 10)
  (put "BEFORE AT!: cursor at (8,10)")
  (sleep 3)

  ;; 在最右边输出绿色文字，at! 移动光标
  (put-bytes (format-fg-at! 15 (- w 30) 2 "AT! at right - cursor moved"))
  (sleep 3)
  (put "AFTER AT!: now at (15, right) ~ correct!")
  (sleep 3)

  (cursor-move 23 0)
  (put "Test done. Press any key...")
  (sleep 2))