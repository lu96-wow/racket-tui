;; test-input.rkt - 输入API测试与教程
#lang racket
(require "../main.rkt")

;; ┌─────────────────────────────────────────────┐
;; │ 输入 API 概览                               │
;; │ (read-event) → type data modifiers          │
;; │                                             │
;; │ 事件类型: key ctrl alt utf8                 │
;; │ 方向键: up down left right                  │
;; │ 编辑键: del insert home end pageup pagedown │
;; │ 鼠标: mouse (统一为 touch 事件)             │
;; │ 粘贴: paste (括号粘贴模式)                  │
;; │ 其他: seq mod-seq resize null               │
;; │                                             │
;; │ 判断: (event-key? type) 等                  │
;; │ 提取: (ctrl->char data) 等                 │
;; │ 鼠标: (event-touch? type) 统一接口          │
;; │ 粘贴: (event-paste? type)                   │
;;└─────────────────────────────────────────────┘

(with-tui-nobuffer
    (screen-clear)
  (put-string "╔══════════════════════════════════════╗") (put-newline)
  (put-string "║     输入 API 测试 (含鼠标+粘贴)         ║") (put-newline)
  (put-string "║   按 q 退出                           ║") (put-newline)
  (put-string "╚══════════════════════════════════════╝") (put-newline)
  (put-newline)
  (put-string "按下任意键、移动鼠标或粘贴内容查看事件...") (put-newline)
  (put-newline)
  (put-string "备注: 粘贴会被识别为单个事件，不会逐字符输出") (put-newline)
  (put-newline)

  ;; 显示鼠标状态区域 - 使用 current-cursor-row 获取当前行
  (put-string "--- 鼠标状态 ---") (put-newline)
  (define mouse-status-line current-cursor-row)
  (put-string "等待鼠标事件...") (put-newline)
  (put-string "---------------") (put-newline)
  (put-newline)

  ;; 粘贴状态显示
  (put-string "--- 粘贴状态 ---") (put-newline)
  (define paste-status-line current-cursor-row)
  (put-string "等待粘贴事件...") (put-newline)
  (put-string "---------------") (put-newline)
  (put-newline)

  (define running? #t)
  (define mouse-events-count 1)
  (define paste-events-count 1)
  ;; 保存主日志区域的起始行
  (define log-start-line current-cursor-row)

  (let loop ()
    (when running?
      (change-noblock)
      (let-values ([(type data mods) (read-event)])
        (unless (event-null? type)

          ;; 如果是鼠标事件，更新状态显示
          (when (event-touch? type)
            (set! mouse-events-count (add1 mouse-events-count))
            (let-values ([(x y) (get-mouse-pos data)])
              ;; 保存当前光标位置
              (define saved-row current-cursor-row)
              (define saved-col current-cursor-col)

              ;; 更新鼠标状态行
              (cursor-move mouse-status-line 1)
              (put-string "                                        ")  ; 清除旧内容
              (cursor-move mouse-status-line 1)
              (put-string (format "鼠标事件 #~a: " mouse-events-count))
              (cond [(mouse-press? data)
                     (put-string "按下 ")]
                    [(mouse-release? data)
                     (put-string "释放 ")]
                    [(mouse-move? data)
                     (put-string "移动 ")]
                    [(mouse-scroll? data)
                     (put-string "滚轮 ")])
              (cond [(mouse-left? data) (put-string "左键")]
                    [(mouse-middle? data) (put-string "中键")]
                    [(mouse-right? data) (put-string "右键")])
              (when (mouse-scroll? data)
                (cond [(scroll-up? data) (put-string "向上")]
                      [(scroll-down? data) (put-string "向下")]))
              (put-string (format " 位置:(~a,~a)" x y))
              (when (> (mouse-modifiers data) 0)
                (put-string (format " 修饰键:~a" (mouse-modifiers data))))

              ;; 恢复光标位置
              (cursor-move saved-row saved-col)
              (flush-output)))

          ;; 如果是粘贴事件，更新粘贴状态显示
          (when (event-paste? type)
            (set! paste-events-count (add1 paste-events-count))
            (define saved-row current-cursor-row)
            (define saved-col current-cursor-col)

            ;; 更新粘贴状态行
            (cursor-move paste-status-line 1)
            (put-string "                                        ")  ; 清除旧内容
            (cursor-move paste-status-line 1)
            (define content (bytes-length data))
            (define preview (event->string data))
            (put-string (format "粘贴事件 #~a: " paste-events-count))
            (put-string (format "~a 字节" content))
            (when (> (string-length preview) 0)
              (put-string " | 内容: ")
              ;; 截断显示，避免太长
              (if (> (string-length preview) 30)
                  (put-string (format "\"~a...\"" (substring preview 0 30)))
                  (put-string (format "\"~a\"" preview))))

            ;; 恢复光标位置
            (cursor-move saved-row saved-col)
            (flush-output))

          ;; 主事件日志区域 - 保存当前位置
          (define log-row current-cursor-row)
          (define log-col current-cursor-col)

          (put-string (format "[~a]" type))

          (cond
            ;; === 粘贴事件 ===
            [(event-paste? type)
             (define content-length (bytes-length data))
             (define preview (event->string data))
             (put-string (format " → ~a 字节" content-length))
             (when (> (string-length preview) 0)
               (put-string " | 内容: ")
               ;; 截断显示，避免太长影响阅读
               (if (> (string-length preview) 40)
                   (put-string (format "\"~a...\"" (substring preview 0 40)))
                   (put-string (format "\"~a\"" preview))))
             ;; 显示十六进制前几个字节
             (when (> content-length 0)
               (put-string " | hex:")
               (define hex-preview (min content-length 8))
               (for ([i (in-range hex-preview)])
                 (put-string (format " ~x" (bytes-ref data i))))
               (when (> content-length 8)
                 (put-string " ...")))]

            ;; === 鼠标事件 (统一通过 event-touch? 处理) ===
            [(event-touch? type)
             (let-values ([(x y) (get-mouse-pos data)])
               (put-string (format " → "))
               ;; 事件类型
               (cond [(mouse-press? data) (put-string "按下")]
                     [(mouse-release? data) (put-string "释放")]
                     [(mouse-move? data) (put-string "移动")]
                     [(mouse-scroll? data) (put-string "滚轮")])
               ;; 按钮类型
               (cond [(mouse-left? data) (put-string " 左键")]
                     [(mouse-middle? data) (put-string " 中键")]
                     [(mouse-right? data) (put-string " 右键")])
               ;; 滚轮方向
               (when (mouse-scroll? data)
                 (cond [(scroll-up? data) (put-string " ↑")]
                       [(scroll-down? data) (put-string " ↓")]))
               ;; 坐标
               (put-string (format " 坐标:(~a,~a)" x y))
               ;; 修饰键
               (when (> (mouse-modifiers data) 0)
                 (put-string (format " 修饰键: ~a" (mouse-modifiers data)))))]

            ;; === 键盘事件 ===
            [(event-key? type)
             (define b (event->byte data))
             (put-string (format " byte=~a" b))
             (cond [(event-tab? type data)       (put-string " → Tab")]
                   [(event-backspace? type data) (put-string " → Backspace")]
                   [(= b 13)                     (put-string " → Enter")]
                   [(= b 27)                     (put-string " → ESC")]
                   [(= b 32)                     (put-string " → Space")]
                   [(= b (char->integer #\q))    (put-string " → q退出") (set! running? #f)]
                   [(<= 32 b 126)                (put-string (format " → '~a'" (integer->char b)))]
                   [else (void)])]

            [(event-ctrl? type)
             (put-string (format " → Ctrl+~a" (ctrl->char data)))]

            [(event-alt? type)
             (put-string (format " → Alt+~a" (integer->char (alt->char data))))]

            [(event-up? type)    (put-string " ↑")]
            [(event-down? type)  (put-string " ↓")]
            [(event-left? type)  (put-string " ←")]
            [(event-right? type) (put-string " →")]

            [(event-del? type)    (put-string " → Delete")]
            [(event-insert? type) (put-string " → Insert")]
            [(event-home? type)   (put-string " → Home")]
            [(event-end? type)    (put-string " → End")]
            [(event-pageup? type) (put-string " → PgUp")]
            [(event-pagedown? type) (put-string " → PgDn")]

            [(event-utf8? type)
             (put-string (format " → \"~a\"" (event->string data)))]

            [(event-resize? type)
             (put-string (format " → ~ax~a" (get-resize-rows data) (get-resize-cols data)))]

            [(event-seq? type)
             (put-string " bytes:")
             (for ([b (in-bytes data)]) (put-string (format " ~a" b)))]

            [(event-mod-seq? type)
             (when (car mods) (put-string " Ctrl"))
             (when (cdr mods) (put-string " Alt"))
             (define ch (mod-seq->char data))
             (when ch (put-string (format " +~a" (integer->char ch))))])

          (put-newline)))

      (sleep 0.01)
      (loop))))