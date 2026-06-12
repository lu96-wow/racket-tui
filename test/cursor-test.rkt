#lang racket

;; ============================================================
;; 光标管理完整测试
;; 使用 format-at / format-at! (以及 put-at / put-at!)
;; 验证光标位置状态管理是否正确
;;
;; 运行: racket test/cursor-test.rkt
;; 每次操作后等待 3 秒方便观察
;; ============================================================

(require "../main.rkt"
         "../cursor-state.rkt")

;; 辅助: 显示当前光标位置
(define (show-cursor label)
  (define-values (r c) (get-cursor))
  (put-string (format "  -> 当前光标: (row=~a, col=~a)" r c))
  (put-newline))

;; 辅助: 底栏状态区 (行 = 24+)
(define status-row 24)

(define (update-status msg)
  (define saved-row current-cursor-row)
  (define saved-col current-cursor-col)
  (cursor-move status-row 0)
  (line-clear)
  (put-string (format "[状态] ~a" msg))
  (cursor-move saved-row saved-col)
  (flush!))

(define (wait-and-update sec msg)
  (sleep sec)
  (update-status msg))

;; ============================================================
;; 主测试流程
;; ============================================================

(with-tui
    (screen-clear)
  (cursor-show)

  ;; -------- 标题 --------
  (put-string "========================================================")
  (put-newline)
  (put-string "      光标管理测试 (format-at / format-at!)")
  (put-newline)
  (put-string "  * put-at  (format-content-at)  输出后恢复光标")
  (put-newline)
  (put-string "  * put-at! (format-content-at!) 输出后移动光标")
  (put-newline)
  (put-string "========================================================")
  (put-newline)
  (put-newline)

  ;; ============================================================
  ;; 测试组 1: put-at (不带 !) - 应恢复光标到原始位置
  ;; ============================================================
  (put-string "--- 测试组 1: put-at (带光标恢复) ---")
  (put-newline)
  (put-newline)

  ;; 1a: 移动光标到 (5,10)，用 put-at 在 (10,20) 输出，观察光标是否回到 (5,10)
  (cursor-move 5 10)
  (put-string "BEFORE put-at")
  (show-cursor "1a")
  (update-status "1a: 光标在 (5,10)，即将 put-at (10,20) 输出")
  (wait-and-update 3 "1a: 执行 put-at (10,20) ...")
  (put-at 10 20 "-> put-at: 输出后应恢复光标 <-")
  (flush!)

  (wait-and-update 3 "1a: 观察光标位置(应回到 (5,10))")
  (show-cursor "1a after put-at")
  (put-string "  -> 正确行为: 光标回到 (5,10)")
  (put-newline)
  (put-newline)

  ;; 1b: 移动光标到 (6,10)，用 format-fg-at 输出颜色，观察光标恢复
  (cursor-move 6 10)
  (put-string "BEFORE format-fg-at (with color)")
  (show-cursor "1b")
  (update-status "1b: 即将 format-fg-at (10,50) 输出红色文字")
  (wait-and-update 3 "1b: 执行 format-fg-at (10,50) ...")
  (put-bytes (format-fg-at 10 50 1 "format-fg-at 彩色: 光标回位"))
  (flush!)

  (wait-and-update 3 "1b: 观察光标位置(应回到 (6,10))")
  (show-cursor "1b after format-fg-at")
  (put-string "  -> 正确行为: 光标回到 (6,10)")
  (put-newline)
  (put-newline)

  ;; ============================================================
  ;; 测试组 2: put-at! (带 !) - 光标应停留在目标位置
  ;; ============================================================
  (put-string "--- 测试组 2: put-at! (光标移动到目标位置) ---")
  (put-newline)
  (put-newline)

  ;; 2a: 移动光标到 (8,10)，用 put-at! 在 (15,30) 输出，观察光标停在 (15,30+len)
  (cursor-move 8 10)
  (put-string "BEFORE put-at!")
  (show-cursor "2a")
  (update-status "2a: 光标在 (8,10)，即将 put-at! (15,30) 输出")
  (wait-and-update 3 "2a: 执行 put-at! (15,30) ...")
  (put-at! 15 30 "-> put-at!: 输出后光标移动到这里 <-")
  (flush!)

  (wait-and-update 3 "2a: 观察光标位置(应停在 (15, 输出后))")
  (show-cursor "2a after put-at!")
  (put-string "  -> 正确行为: 光标停留在 (15,30+内容长度)")
  (put-newline)
  (put-newline)

  ;; 2b: 用 format-fg-at! 输出并检查光标
  (cursor-move 9 10)
  (put-string "BEFORE format-fg-at!")
  (show-cursor "2b")
  (update-status "2b: 即将 format-fg-at! (16,50) 输出")
  (wait-and-update 3 "2b: 执行 format-fg-at! (16,50) ...")
  (put-bytes (format-fg-at! 16 50 2 "-> format-fg-at! 彩色: 光标移动到这里 <-"))
  (flush!)

  (wait-and-update 3 "2b: 观察光标位置(应停在 (16,50+内容长度))")
  (show-cursor "2b after format-fg-at!")
  (put-string "  -> 正确行为: 光标停留在 (16,50+内容长度)")
  (put-newline)
  (put-newline)

  ;; ============================================================
  ;; 测试组 3: put-at 连续调用 - 每次都应恢复
  ;; ============================================================
  (put-string "--- 测试组 3: put-at 连续多次调用(每次恢复光标) ---")
  (put-newline)
  (put-newline)

  (cursor-move 12 10)
  (put-string "BEFORE multiple put-at calls")
  (show-cursor "3 start")
  (update-status "3: 连续 3 次 put-at, 观察光标始终保持")
  (wait-and-update 3 "3: put-at #1 (18,10)")
  (put-at 18 10 "[#1] put-at at (18,10)")
  (flush!)
  (wait-and-update 3 "3: put-at #2 (19,10)")
  (put-at 19 10 "[#2] put-at at (19,10)")
  (flush!)
  (wait-and-update 3 "3: put-at #3 (20,10)")
  (put-at 20 10 "[#3] put-at at (20,10)")
  (flush!)
  (wait-and-update 3 "3: 检查光标(应仍在 (12,10))")

  (show-cursor "3 after 3x put-at")
  (put-string "  -> 正确行为: 光标仍在 (12,10)")
  (put-newline)
  (put-newline)

  ;; ============================================================
  ;; 测试组 4: put-at! 连续调用 - 光标应随每次调用移动
  ;; ============================================================
  (put-string "--- 测试组 4: put-at! 连续多次调用(光标跟随移动) ---")
  (put-newline)
  (put-newline)

  (update-status "4: 连续 3 次 put-at!, 观察光标位置变化")
  (wait-and-update 3 "4: put-at! #1 (18,10)")
  (put-at! 18 10 "[#1] put-at! at (18,10)")
  (flush!)
  (show-cursor "4 after #1")
  (wait-and-update 3 "4: put-at! #2 (22,10)")

  (put-at! 22 10 "[#2] put-at! at (22,10)")
  (flush!)
  (show-cursor "4 after #2")
  (wait-and-update 3 "4: put-at! #3 (23,10)")

  (put-at! 23 10 "[#3] put-at! at (23,10)")
  (flush!)
  (show-cursor "4 after #3")
  (put-string "  -> 正确行为: 光标从 (18,10) -> (22,10) -> (23,10)")
  (put-newline)
  (put-newline)

  ;; ============================================================
  ;; 测试组 5: put-at 与 put-at! 混合使用
  ;; ============================================================
  (put-string "--- 测试组 5: put-at 与 put-at! 混合使用 ---")
  (put-newline)
  (put-newline)

  (cursor-move 14 10)
  (put-string "START at (14,10)")
  (put-newline)
  (show-cursor "5 start")

  (update-status "5: put-at! (25,5) -> 光标移动到 (25,5)")
  (wait-and-update 3 "5: put-at! 移动光标到 (25,5)")
  (put-at! 25 5 "[A] put-at! -> 光标停在 (25,5)")
  (flush!)
  (show-cursor "5 after put-at!")
  (put-newline)

  (update-status "5: put-at (26,5) -> 光标恢复到 (25,5+内容长度)")
  (wait-and-update 3 "5: put-at 输出(应回到 put-at! 所在位置)")
  (put-at 26 5 "[B] put-at  -> 光标回到上次位置")
  (flush!)
  (show-cursor "5 after put-at (restored)")
  (put-newline)

  (update-status "5: format-fg-at! (27,5) -> 光标移动到 (27,5)")
  (wait-and-update 3 "5: format-fg-at! (黄色) 移动光标")
  (put-bytes (format-fg-at! 27 5 3 "[C] format-fg-at! -> 光标到 (27,5)"))
  (flush!)
  (show-cursor "5 after format-fg-at!")
  (put-newline)

  (update-status "5: format-fg-at (28,5) -> 光标恢复到 (27,5)")
  (wait-and-update 3 "5: format-fg-at (蓝色) 恢复光标")
  (put-bytes (format-fg-at 28 5 4 "[D] format-fg-at -> 光标回 (27,5)"))
  (flush!)
  (show-cursor "5 after format-fg-at (restored)")
  (put-newline)

  ;; ============================================================
  ;; 测试组 6: 测试 RGB/256 色 at 变体
  ;; ============================================================
  (put-string "--- 测试组 6: RGB/256 色 at/at! 变体 ---")
  (put-newline)
  (put-newline)

  (cursor-move 16 10)
  (put-string "START at (16,10)")
  (put-newline)
  (show-cursor "6 start")

  (update-status "6: format-rgb-fg-at (恢复光标)")
  (wait-and-update 3 "6: RGB 前景 at (30,5) - 应恢复光标")
  (put-bytes (format-rgb-fg-at 30 5 255 128 0 "RGB-at: 橙色文字 (恢复光标)"))
  (flush!)
  (show-cursor "6 after RGB-at (restored)")
  (put-newline)

  (update-status "6: format-rgb-fg-at! (移动光标)")
  (wait-and-update 3 "6: RGB 前景 at! (31,5) - 应移动光标")
  (put-bytes (format-rgb-fg-at! 31 5 0 200 0 "RGB-at!: 绿色文字 (移动光标)"))
  (flush!)
  (show-cursor "6 after RGB-at! (moved)")
  (put-newline)

  (update-status "6: format-256-fg-at (恢复)")
  (wait-and-update 3 "6: 256 色 at (32,5) - 应恢复")
  (put-bytes (format-256-fg-at 32 5 196 "256-at: 亮红色 (恢复光标)"))
  (flush!)
  (show-cursor "6 after 256-at (restored)")
  (put-newline)

  (update-status "6: format-256-fg-at! (移动)")
  (wait-and-update 3 "6: 256 色 at! (33,5) - 应移动")
  (put-bytes (format-256-fg-at! 33 5 27 "256-at!: 蓝色 (移动光标)"))
  (flush!)
  (show-cursor "6 after 256-at! (moved)")
  (put-newline)

  ;; ============================================================
  ;; 测试组 7: format-styled-at / format-styled-at!
  ;; ============================================================
  (put-string "--- 测试组 7: format-styled-at 系列 ---")
  (put-newline)
  (put-newline)

  (style-define! 'test-warning (color-fg 3) attr-bold)
  (style-define! 'test-error   (color-fg 1) attr-bold attr-underline)
  (style-define! 'test-success (color-fg 2))

  (cursor-move 18 10)
  (put-string "START at (18,10)")
  (put-newline)
  (show-cursor "7 start")

  (update-status "7: format-styled-at (恢复)")
  (wait-and-update 3 "7: 样式 at (30,50) - 应恢复光标")
  (put-bytes (format-styled-at 30 50 'test-warning "样式-at: 黄色粗体 (恢复)"))
  (flush!)
  (show-cursor "7 after styled-at (restored)")
  (put-newline)

  (update-status "7: put-styled-at! (移动)")
  (wait-and-update 3 "7: 样式 at! (31,50) - 应移动光标")
  (put-styled-at! 31 50 'test-error "样式-at!: 红色粗体下划线 (移动)")
  (flush!)
  (show-cursor "7 after styled-at! (moved)")
  (put-newline)

  (update-status "7: put-styled-at (恢复)")
  (wait-and-update 3 "7: 样式 at (32,50) - 应恢复")
  (put-styled-at 32 50 'test-success "样式-at: 绿色 (恢复)")
  (flush!)
  (show-cursor "7 after styled-at (restored)")
  (put-newline)

  ;; ============================================================
  ;; 测试组 8: cursor-move/cursor-col 等光标移动状态同步
  ;; ============================================================
  (put-string "--- 测试组 8: cursor-move / cursor-col 状态同步 ---")
  (put-newline)
  (put-newline)

  (update-status "8: cursor-move 到 (20,10)")
  (cursor-move 20 10)
  (show-cursor "8 after cursor-move")
  (put-string "  -> 正确: (20,10)")
  (put-newline)
  (wait-and-update 3 "8: cursor-col 50")
  (cursor-col 50)
  (show-cursor "8 after cursor-col 50")
  (put-string "  -> 正确: (20,50)")
  (put-newline)
  (wait-and-update 3 "8: cursor-home")
  (cursor-home)
  (show-cursor "8 after cursor-home")
  (put-string "  -> 正确: (0,0)")
  (put-newline)
  (wait-and-update 3 "8: cursor-down 3")
  (cursor-down 3)
  (show-cursor "8 after cursor-down 3")
  (put-string "  -> 正确: (3,0)")
  (put-newline)
  (wait-and-update 3 "8: cursor-right 10")
  (cursor-right 10)
  (show-cursor "8 after cursor-right 10")
  (put-string "  -> 正确: (3,10)")
  (put-newline)
  (wait-and-update 3 "8: cursor-up 2")
  (cursor-up 2)
  (show-cursor "8 after cursor-up 2")
  (put-string "  -> 正确: (1,10)")
  (put-newline)
  (wait-and-update 3 "8: cursor-left 5")
  (cursor-left 5)
  (show-cursor "8 after cursor-left 5")
  (put-string "  -> 正确: (1,5)")
  (put-newline)

  ;; ============================================================
  ;; 测试完成
  ;; ============================================================
  (put-newline)
  (put-string "========================================================")
  (put-newline)
  (put-string "      所有光标管理测试完成!")
  (put-newline)
  (put-string "   如果所有位置显示正确，说明光标状态管理没问题")
  (put-newline)
  (put-string "         按任意键退出...")
  (put-newline)
  (put-string "========================================================")
  (put-newline)
  (flush!)
  (cursor-show)

  ;; 等待按键退出
  (let loop ()
    (define-values (type data mods) (read-event))
    (unless (or (event-key? type) (event-null? type)
                (and (event-ctrl? type) (= (bytes-ref data 0) 3)))
      (loop))))
