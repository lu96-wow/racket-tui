#lang racket

;; ============================================================
;; 演示：不进入 raw mode，只使用 tui 库的颜色输出功能
;; 运行: racket test/a.rkt
;; ============================================================

(require tui)

(displayln "=== 不进入 raw mode，直接使用 tui 颜色功能 ===\n")

;; --- 方式1: output.rkt 的 put-* 直接输出 ---
(displayln "--- 方式1: put-fg / put-bg / put-rgb-fg / put-256-fg ---")
(put-fg 1 "前景色 1 (红)")    (newline)
(put-fg 2 "前景色 2 (绿)")    (newline)
(put-fg 4 "前景色 4 (蓝)")    (newline)
(put-bg 3 "背景色 3 (黄)")    (newline)
(put-bg 5 "背景色 5 (品红)")  (newline)
(put-rgb-fg 255 128 0 "RGB 前景 (255,128,0) 橙色") (newline)
(put-rgb-bg 0 200 200 "RGB 背景 (0,200,200) 青色") (newline)
(put-256-fg 196 "256色前景 #196 (亮红)")           (newline)
(put-256-bg 27  "256色背景 #27 (蓝)")              (newline)
(newline)

;; --- 方式2: ansi-format.rkt 纯函数生成字节串 ---
(displayln "--- 方式2: format-* 纯函数 + display ---")
(display (bytes->string/utf-8
          (bytes-append format-bold
                        (format-fg 3)
                        (format-content "加粗 + 前景色3 (黄)")
                        format-reset)))
(newline)
(display (bytes->string/utf-8
          (bytes-append format-underline
                        (format-fg 6)
                        (format-content "下划线 + 前景色6 (青)")
                        format-reset)))
(newline)
(display (bytes->string/utf-8
          (bytes-append format-dim
                        format-italic
                        (format-content "暗淡 + 斜体")
                        format-reset)))
(newline)
(display (bytes->string/utf-8
          (bytes-append (format-rgb-fg 255 0 255)
                        (format-content "RGB 品红")
                        format-reset)))
(newline)
(newline)

;; --- 方式3: output-color.rkt 的 format-styled-* ---
(displayln "--- 方式3: format-styled-bold / format-styled-underline 等 ---")
(display (bytes->string/utf-8 (format-styled-bold "粗体文本")))
(newline)
(display (bytes->string/utf-8 (format-styled-italic "斜体文本")))
(newline)
(display (bytes->string/utf-8 (format-styled-underline "下划线文本")))
(newline)
(display (bytes->string/utf-8 (format-styled-dim "暗淡文本")))
(newline)
(display (bytes->string/utf-8 (format-styled-blink "闪烁文本")))
(newline)
(display (bytes->string/utf-8 (format-styled-reverse "反色文本")))
(newline)
(newline)

;; --- 方式4: style-define! + format-styled (颜色 + 属性组合) ---
(displayln "--- 方式4: style-define! 自定义样式 ---")
(style-define! 'warning (color-fg 3) attr-bold)          ; 黄色粗体
(style-define! 'error   (color-fg 1) attr-bold attr-underline) ; 红色粗体下划线
(style-define! 'info    (color-rgb-fg 100 200 255))    ; RGB 浅蓝

(display (bytes->string/utf-8 (format-styled 'warning "警告信息")))
(newline)
(display (bytes->string/utf-8 (format-styled 'error "错误信息")))
(newline)
(display (bytes->string/utf-8 (format-styled 'info "提示信息 (RGB 浅蓝)")))
(newline)
(newline)

;; --- 方式5: format-styled* 无 reset，适合拼接 ---
(displayln "--- 方式5: format-styled* 拼接 (无自动 reset) ---")
(style-define! 'red   (color-fg 1))
(style-define! 'green (color-fg 2))
(style-define! 'blue  (color-fg 4))
(display (bytes->string/utf-8
          (bytes-append (format-styled* 'red "红")
                        (format-content " | ")
                        (format-styled* 'green "绿")
                        (format-content " | ")
                        (format-styled* 'blue "蓝")
                        format-reset)))
(newline)
(newline)

(displayln "=== 演示完毕（终端始终处于正常模式） ===")
