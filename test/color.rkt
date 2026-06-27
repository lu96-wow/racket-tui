;; test-color.rkt - 颜色/样式API测试与教程
#lang racket
(require "../main.rkt" "../base/output-styles.rkt")

;; ┌─────────────────────────────────────────────┐
;; │ 颜色/样式 API 概览                          │
;; │ 定义: (style-define! name spec...)         │
;; │ 应用: (style-apply! name)                  │
;; │ 输出: (put-styled name value)              │
;; │ 绝对: (put-styled-at row col name value)   │
;; │                                             │
;; │ 颜色: color-fg color-bg color256-*         │
;; │       color-rgb-fg color-rgb-bg            │
;; │ 别名: clr-red bclr-blue ...                │
;; │ 属性: attr-bold attr-underline ...          │
;; └─────────────────────────────────────────────┘

(with-tui
    (screen-clear)

  ;; === 预设样式 ===
  (put-at 1 2 "=== 预设样式 ===")
  (put-styled-at 3  4 'error   "■ error   - 红色粗体")
  (put-styled-at 4  4 'warning "■ warning - 黄色粗体")
  (put-styled-at 5  4 'success "■ success - 绿色")
  (put-styled-at 6  4 'info    "■ info    - 青色")

  ;; === 自定义颜色 ===
  (put-at 8 2 "=== 自定义颜色 ===")

  (style-define! 'my-red clr-red attr-bold)
  (put-styled-at 10 4 'my-red "16色: 红色粗体")

  (style-define! 'my-256 (color256-fg 208) attr-bold)
  (put-styled-at 11 4 'my-256 "256色: 橙色 #208")

  (style-define! 'my-rgb (color-rgb-fg 100 200 255) (color-rgb-bg 30 30 30))
  (put-styled-at 12 4 'my-rgb "真彩: 浅蓝字+深灰底")

  (style-define! 'fancy clr-yellow bclr-blue attr-bold attr-underline)
  (put-styled-at 13 4 'fancy "组合: 黄字蓝底粗体下划线")

  (style-define! 'default clr-default bclr-default)
  (put-styled-at 14 4 'default "16色原色")

  ;; === 位置无关组合 ===
  (put-at 15 2 "=== 位置无关组合 ===")
  (style-define! 'demo1 attr-bold clr-green)
  (style-define! 'demo2 clr-green attr-bold)
  (put-styled-at 17 4 'demo1 "demo1: 先粗体后绿色")
  (put-styled-at 18 4 'demo2 "demo2: 先绿色后粗体 → 效果一致")

  ;; === 一键输出 ===
  (put-at 20 2 "=== 一键输出 ===")
  (put-styled-at 21 4 'error "put-styled 一键应用样式+输出+重置")

  ;; === 绝对位置 ===
  (put-at 23 2 "=== 绝对位置+样式(不影响光标) ===")
  (put-styled-at 25 6 'success "样式+绝对位置")


  ;; read-event 内部使用 select() 阻塞等待, 零 CPU
  (let loop ()
    (let-values ([(type data mods) (read-event)])
      (cond [(and (event-key? type)
                  (= (event->byte data) (char->integer #\q))) (void)]
            [(and (event-key? type)
                  (= (event->byte data) (char->integer #\t)))
             (screen-clear)
             (loop)]
            [else (loop)]))))