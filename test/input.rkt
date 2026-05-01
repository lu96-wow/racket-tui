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
;; │ 其他: seq mod-seq resize null               │
;; │                                             │
;; │ 判断: (event-key? type) 等                  │
;; │ 提取: (ctrl->char data) 等                 │
;; └─────────────────────────────────────────────┘

(with-tui
    (screen-clear)
  (put-string "╔════════════════════════════╗") (put-newline)
  (put-string "║   输入 API 测试           ║") (put-newline)
  (put-string "║   按 q 退出              ║") (put-newline)
  (put-string "╚════════════════════════════╝") (put-newline)
  (put-newline)
  (put-string "按下任意键查看事件信息...") (put-newline)

  (define running? #t)

  (let loop ()
    (when running?
      (change-noblock)
      (let-values ([(type data mods) (read-event)])
        (unless (event-null? type)
          (put-string (format "[~a]" type))

          (cond
            [(event-key? type)
             (define b (event->byte data))
             (put-string (format " byte=~a" b))
             (cond [(event-tab? type data)       (put-string " → Tab")]
                   [(event-backspace? type data) (put-string " → Backspace")]
                   [(= b 13)                     (put-string " → Enter")]
                   [(= b 27)                     (put-string " → ESC")]
                   [(= b 32)                     (put-string " → Space")]
                   [(= b (char->integer #\q))    (put-string " → 退出") (set! running? #f)]
                   [(<= 32 b 126)                (put-string (format " → '~a'" (integer->char b)))]
                   [else (void)])]

            [(event-ctrl? type)
             (put-string (format " → Ctrl+~a" (ctrl->char data)))]

            [(event-alt? type)
             (put-string (format " → Alt+~a" (integer->char (alt->char data))))]

            [(event-up? type)    (put-string " → ↑")]
            [(event-down? type)  (put-string " → ↓")]
            [(event-left? type)  (put-string " → ←")]
            [(event-right? type) (put-string " → →")]

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