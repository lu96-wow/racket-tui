#lang racket

(require "../tui.rkt" "../input.rkt")

;; 测试程序1：event-tab? 在前
(define (test-tab-before)
  (printf "=== 测试：event-tab? 在前，event-key? 在后 ===\n")
  (printf "按 Tab 键测试，按 q 退出\n\n")

  (let loop ()
    (define-values (type data mod) (read-event))

    (cond
      ;; event-tab? 先检查
      [(event-tab? type data)
       (printf "✓ event-tab? 匹配成功: type=~s, data=~s\n" type data)
       (loop)]

      ;; event-key? 后检查
      [(event-key? type)
       (printf "✗ event-key? 匹配: type=~s, data=~s (应该是 Tab 但被 event-tab? 捕获了)\n" type data)
       (loop)]

      [(and (event-key? type) (event->byte data) (= (event->byte data) 113))  ; 'q' 退出
       (printf "退出程序\n")]

      [else
       (printf "其他事件: type=~s, data=~s\n" type data)
       (loop)])))

;; 测试程序2：event-key? 在前
(define (test-key-before)
  (printf "=== 测试：event-key? 在前，event-tab? 在后 ===\n")
  (printf "按 Tab 键测试，按 q 退出\n\n")

  (let loop ()
    (define-values (type data mod) (read-event))

    (cond
      ;; event-key? 先检查
      [(event-key? type)
       (printf "✗ event-key? 匹配: type=~s, data=~s (Tab 键到这里了)\n" type data)
       (when (and (bytes? data)
                  (= (bytes-length data) 1)
                  (= (bytes-ref data 0) 9))
         (printf "   → 检测到 Tab 键，但通过 event-key? 捕获的\n"))
       (loop)]

      ;; event-tab? 后检查（实际上不会被触发，因为上面的 event-key? 已经匹配了）
      [(event-tab? type data)
       (printf "✓ event-tab? 匹配成功（永远不会到这里，因为被 event-key? 拦截了）\n")
       (loop)]

      [(and (event-key? type) (event->byte data) (= (event->byte data) 113))
       (printf "退出程序\n")]

      [else
       (printf "其他事件: type=~s, data=~s\n" type data)
       (loop)])))

;; 测试程序3：同时展示两种检测方式的对比
(define (test-comparison)
  (printf "=== 综合测试：同时检测两种方式 ===\n")
  (printf "按 Tab 键，会显示两种检测方式的结果\n")
  (printf "按 q 退出\n\n")

  (let loop ()
    (define-values (type data mod) (read-event))

    (cond
      [(event-tab? type data)
       (printf "【event-tab?】 返回 #t\n")
       (printf "【event-key?】 返回 #t (因为 type='key)\n")
       (printf "→ 结论：Tab 键同时满足两个条件\n")
       (printf "   但 event-tab? 提供了更明确的语义\n\n")
       (loop)]

      [(event-key? type)
       (printf "【event-key?】 返回 #t, 但 event-tab? 返回 #f\n")
       (printf "数据: ~s, 字节值: ~s\n\n" data (if (bytes? data) (bytes-ref data 0) 'N/A))
       (loop)]

      [(and (event-key? type) (event->byte data) (= (event->byte data) 113))
       (printf "退出程序\n")]

      [else
       (printf "其他事件: type=~s, data=~s\n" type data)
       (loop)])))

;; 主菜单
(define (main)
  (printf "\n")
  (printf "╔════════════════════════════════════════╗\n")
  (printf "║   Tab 键检测顺序测试程序                ║\n")
  (printf "╠════════════════════════════════════════╣\n")
  (printf "║ 1. 测试 event-tab? 在前                ║\n")
  (printf "║ 2. 测试 event-key? 在前                ║\n")
  (printf "║ 3. 综合测试（同时显示两种检测）         ║\n")
  (printf "║ q. 退出                                ║\n")
  (printf "╚════════════════════════════════════════╝\n")
  (printf "\n选择测试 (1/2/3/q): ")
  (flush-output)

  (let ([line (read-line)])
    (cond
      [(equal? line "1")
       (with-tui
           (test-tab-before))]
      [(equal? line "2")
       (with-tui
           (test-key-before))]
      [(equal? line "3")
       (with-tui
           (test-comparison))]
      [(or (equal? line "q") (equal? line "Q"))
       (printf "退出\n")]
      [else
       (printf "无效选择\n")
       (main)])))

;; 运行测试
(main)