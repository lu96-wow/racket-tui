#lang racket
;; ════════════════════════════════════════════════════════════════
;; 输入事件调试器 — 验证 read-event 的字节流解析
;;
;; 显示每个事件的: type / data 原始字节 / mods / 语义
;; 按 q 退出
;;
;; 建议测试清单（用于验证组合键解析）:
;;   方向键 / Home / End / PgUp / PgDn / Insert / Delete
;;   Alt+x              → alt 'x'        (ESC x)
;;   Ctrl+x             → ctrl #\X       (控制字节)
;;   Ctrl+Alt+x         → mod-seq        (xterm: ESC [ 27;7;120~)
;;   Ctrl+方向键 / Alt+方向键 / Shift+方向键 / Ctrl+Alt+Shift+方向键
;;                     → mod-seq        (xterm: ESC [ 1;5A / 1;3A / 1;2A / 1;8A)
;;   Tab / Shift+Tab / Enter / 独立 Esc
;;   鼠标点击/移动/滚轮（含 Shift/Ctrl+点击）、中键粘贴
;;   注: F1-F12 不映射 — 桌面环境会吞键，终端收不到
;; ════════════════════════════════════════════════════════════════
(require "../main.rkt")

;; 语义描述
(define (describe-mouse data)
  (cond
    [(mouse-press? data)
     (format "mouse-press ~a (~a,~a)"
             (cond [(mouse-left? data) "left"]
                   [(mouse-middle? data) "middle"]
                   [(mouse-right? data) "right"]
                   [else "?"])
             (mouse-x data) (mouse-y data))]
    [(mouse-release? data)
     (format "mouse-release (~a,~a)" (mouse-x data) (mouse-y data))]
    [(mouse-move? data)
     (format "mouse-move (~a,~a)" (mouse-x data) (mouse-y data))]
    [(mouse-scroll? data)
     (format "mouse-scroll ~a (~a,~a)"
             (if (scroll-up? data) "up" "down")
             (mouse-x data) (mouse-y data))]
    [else "mouse?"]))

;; mods 三元组 (list ctrl? alt? shift?) → 人可读
(define (describe-mods mods)
  (if (not (list? mods))
      "无"
      (let ([parts (filter identity
                           (list (and (car mods) "Ctrl")
                                 (and (cadr mods) "Alt")
                                 (and (caddr mods) "Shift")))])  
        (if (null? parts) "无" (string-join parts "+")))))

;; mod-seq data 的键名（修饰 CSI 形式: ESC [ 1;5A 的 final 字母）
(define (mod-seq-key-name data)
  (define n (bytes-length data))
  (define final (and (> n 2) (bytes-ref data (sub1 n))))
  (case final
    [(65) "Up"] [(66) "Down"] [(67) "Right"] [(68) "Left"]
    [(72) "Home"] [(70) "End"]
    [(90) "Tab"]                    ; Shift+Tab 的修饰形式
    [else (format "byte ~a" (if final final 0))]))

(define (describe type data mods)
  (cond
    [(event-null? type)   "null"]
    [(event-resize? type) (format "resize ~ax~a" (get-resize-rows data) (get-resize-cols data))]
    [(event-paste? type)  (format "paste (~a bytes)" (bytes-length data))]
    [(event-mouse? type)  (describe-mouse data)]
    [(event-ctrl? type)
     (let ([ch (ctrl->char data)])
       (if ch (format "Ctrl+~a" ch)
           (format "Ctrl+byte~a" (event->byte data))))]
    [(event-alt? type)
     (let ([b (alt->char data)])
       (if b (format "Alt+~a" (integer->char b)) "Alt+?"))]
    [(event-mod-seq? type)
     (define prefix (string-append
                     (if (car mods) "Ctrl+" "")
                     (if (cadr mods) "Alt+" "")
                     (if (caddr mods) "Shift+" "")))
     (define last (and (> (bytes-length data) 0)
                       (bytes-ref data (sub1 (bytes-length data)))))
     (if (= last 126)   ; 以 ~ 结尾 = modifyOtherKeys 字符型
         (let ([ch (mod-seq->char data)])
           (format "~a~a" prefix (if ch (integer->char ch) "?")))
         (format "~a~a" prefix (mod-seq-key-name data)))]
    [(event-key? type)
     (define b (event->byte data))
     (cond [(and b (= b 9))  "Tab"]
           [(and b (memv b (list 8 127))) "Backspace"]
           [(and b (memv b (list 10 13))) "Enter"]
           [(and b (= b 27)) "Esc"]
           [(and b (= b 0))  "Ctrl+Space"]
           [(and b (<= 32 b 126)) (format "'~a'" (integer->char b))]
           [else (format "byte ~a" b)])]
    [(event-utf8? type) (format "\"~a\"" (event->string data))]
    [(event-up? type) "Up"]   [(event-down? type) "Down"]
    [(event-left? type) "Left"] [(event-right? type) "Right"]
    [(event-del? type) "Delete"]  [(event-insert? type) "Insert"]
    [(event-home? type) "Home"]   [(event-end? type) "End"]
    [(event-pageup? type) "PgUp"] [(event-pagedown? type) "PgDn"]
    [(event-backtab? type) "Shift+Tab"]
    [(event-seq? type) (format "seq ~s" data)]
    [else (format "~a" type)]))

;; data 的原始字节（十进制 + ASCII 可读形式）
;; 注意：鼠标的 data 是 list，resize 的 data 是 pair，只有按键/粘贴是 bytes
(define (show-bytes data)
  (if (bytes? data)
      (let ([bs (bytes->list data)])
        (define readable
          (apply string-append
                 (for/list ([b bs])
                   (cond [(= b 27) "^["]
                         [(= b 13) "\\r"] [(= b 10) "\\n"]
                         [(<= 32 b 126) (string (integer->char b))]
                         [else (format "<~a>" b)]))))
        (format "~a  (~a)" readable bs))
      (format "~s" data)))

(with-tui
 (λ ()
   (screen-clear)
   (put-styled 'title "═══ 输入事件调试器 (read-event) ═══") (put-newline)
   (put-styled 'info "按 q 退出 · 组合键: Alt+x / Ctrl+方向键 / Ctrl+Alt+x · 鼠标 / 粘贴") (put-newline)
   (put-newline)
   (define running? #t)
   (define count 0)
   (let loop ()
     (when running?
       (let-values ([(type data mods) (read-event)])
         (set! count (add1 count))
         (put-styled 'heading (format "事件 #~a:" count)) (put-newline)
         (put-string (format "  type: ~a" type)) (put-newline)
         (put-string (format "  data: ~a" (show-bytes data))) (put-newline)
         (put-string (format "  mods: ~a" (describe-mods mods))) (put-newline)
         (put-styled 'success (format "  → ~a" (describe type data mods))) (put-newline)
         (put-newline)
         ;; 清屏前 50 个事件，避免滚动太长
         (when (>= count 50)
           (screen-clear)
           (set! count 0)
           (put-styled 'info "已清屏，继续测试...") (put-newline) (put-newline))
         ;; q 退出
         (when (and (event-key? type) (event->byte data)
                    (= (event->byte data) (char->integer #\q)))
           (set! running? #f))
         (loop))))))
