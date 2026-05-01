;; test-output.rkt
#lang racket

(require "../main.rkt")

(with-tui
    (screen-clear) (cursor-show)
  (let-values ([(rows cols) (get-window-size)])
    (define sr (- rows 1))
    (define (ss) (put-at sr (- cols 20) (format "光标:(~a,~a)" current-cursor-row current-cursor-col)))

    ;; ====== 基础输出 ======
    (put-at 1 2 "=== 基础 put ===")
    (put-at! 3 4 "str|") (put-at! 3 10 #"bytes|") (put-at! 3 18 #\X) (put-at! 3 20 "|") (put-at! 3 22 42) (ss)

    (cursor-move 5 4) (put "put-newline →") (put-newline) (put "← 新行") (ss)

    ;; ====== put-at: 不影响光标 ======
    (put-at 8 2 "=== put-at: 不影响光标 ===")

    ;; 先把光标移到左侧
    (cursor-move 10 4) (put "← 光标先放这里") (ss)
    (sleep 1)

    ;; 在最右侧用 put-at 输出，观察光标是否跳回来
    (put-at 10 (- cols 15) "右侧输出") (ss)
    (sleep 1)
    (put-at 11 4 "↑ 光标还在左侧吗？是→正确 否→Bug") (ss)

    ;; ====== put-at!: 影响光标 ======
    (put-at 13 2 "=== put-at!: 影响光标 ===")

    ;; 光标放左侧
    (cursor-move 15 4) (put "← 光标起始位") (ss)
    (sleep 1)

    ;; 在最右侧用 put-at! 输出，光标应跟随
    (put-at! 15 (- cols 15) "右侧输出") (put " ← 光标跟过来了吗？") (ss)
    (sleep 1)
    (put-at 16 4 "↑ 光标应该在最右侧") (ss)

    ;; ====== line-clear ======
    (put-at 18 2 "=== line-clear ===")
    (cursor-move 19 4) (put "3秒后清除...") (ss) (sleep 3)
    (cursor-move 19 4) (line-clear) (put "已清除") (ss)))