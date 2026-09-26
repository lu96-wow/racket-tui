#lang racket
;; ════════════════════════════════════════════════════════════════
;; 输入事件调试器 —— 同时展示三层
;;
;;   raw   : read-event/raw 的 (type data mods) 字节级结果
;;   event : normalize-event 后的规范 event?（即 read-event 的返回值）
;;   cb    : 该事件在 build-input 中命中的回调关键字
;;
;; 按 q 退出。
;;
;; 建议测试清单（用于验证组合键解析）:
;;   方向键 / Home / End / PgUp / PgDn / Insert / Delete / Backspace
;;   Alt+x              → key-event  key=#\x    mods=Alt         cb #:key
;;   Ctrl+x             → key-event  key=#\X    mods=Ctrl        cb #:key
;;   Ctrl+Alt+x         → key-event  mods=Ctrl+Alt   cb #:key
;;                        （默认编码 ESC ^X → key=#\X）
;;                        （modifyOtherKeys ESC[27;7;120~ → key=#\x）
;;   Ctrl+方向键 / Alt+方向键 / Shift+方向键 / Ctrl+Alt+Shift+方向键
;;                      → key-event  key=up ... mods=...         cb #:key
;;   Tab / Shift+Tab / Enter / 独立 Esc / 空格  → 对应快捷回调
;;   鼠标点击/移动/滚轮（含 Shift/Ctrl+点击）、中键粘贴
;;   注: F1-F12 不映射 — 桌面环境会吞键，终端收不到
;; ════════════════════════════════════════════════════════════════
(require "../main.rkt")

;; ── raw 层：鼠标 detail → 语义 ───────────────────────────────
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

;; mods 可为 mods 结构体 / (list ctrl? alt? shift?) / #f
(define (describe-mods m)
  (define l (if (mods? m) (mods->list m) m))
  (if (not (list? l))
      "无"
      (let ([parts (filter identity
                           (list (and (car l) "Ctrl")
                                 (and (cadr l) "Alt")
                                 (and (caddr l) "Shift")))])
        (if (null? parts) "无" (string-join parts "+")))))

;; 导航键符号 → 显示名
(define (describe-key k)
  (case k
    [(up) "Up"] [(down) "Down"] [(left) "Left"] [(right) "Right"]
    [(home) "Home"] [(end) "End"]
    [(pageup) "PgUp"] [(pagedown) "PgDn"]
    [(insert) "Insert"] [(del) "Delete"]
    [(backtab) "Shift+Tab"]
    [(tab) "Tab"] [(enter) "Enter"] [(escape) "Esc"] [(backspace) "Backspace"]
    [else (format "~a" k)]))

;; ── raw 层：事件 type/data → 语义 ────────────────────────────
(define (describe-raw type data mods)
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
     (let ([ch (alt->char data)])
       (if ch (format "Alt+~a" ch) "Alt+?"))]
    [(event-mod-seq? type)
     (define prefix (string-append
                     (if (car mods) "Ctrl+" "")
                     (if (cadr mods) "Alt+" "")
                     (if (caddr mods) "Shift+" "")))
     (define key (mod-seq->key data))
     (if key
         (format "~a~a" prefix (describe-key key))
         (let ([ch (mod-seq->char data)])
           (format "~a~a" prefix (if ch ch "?"))))]
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

;; ── 规范事件 event? → 可读描述 ───────────────────────────────
(define (describe-event ev)
  (match ev
    [(key-event key mods)
     (format "key-event  key=~s (~a)  mods=~a"
             key
             (cond [(char? key) (format "char ~s" key)]
                   [(symbol? key) (format "named ~a" (describe-key key))]
                   [else "?"])
             (describe-mods mods))]
    [(paste-event bytes text)
     (format "paste-event  ~a bytes  text=~s" (bytes-length bytes) text)]
    [(mouse-event action button x y mods)
     (format "mouse-event  action=~a button=~a x=~a y=~a  mods=~a"
             action button x y (describe-mods mods))]
    [(resize-event rows cols) (format "resize-event  ~ax~a" rows cols)]
    [(null-event) "null-event"]
    [(other-event type data mods) (format "other-event  type=~a" type)]))

;; ── 该事件在 build-input 中命中的回调关键字 ──────────────────
;; 所有关键字都设一个探针回调；命中哪个就返回哪个（#:any 为兜底）。
(define probe
  (let ([hit #f])
    (define (mk name) (λ args (set! hit name)))
    (define handler
      (build-input
       #:text (mk '#:text) #:key (mk '#:key) #:paste (mk '#:paste)
       #:mouse (mk '#:mouse) #:resize (mk '#:resize) #:null (mk '#:null)
       #:tab (mk '#:tab) #:backtab (mk '#:backtab) #:space (mk '#:space)
       #:enter (mk '#:enter) #:backspace (mk '#:backspace) #:escape (mk '#:escape)
       #:up (mk '#:up) #:down (mk '#:down) #:left (mk '#:left) #:right (mk '#:right)
       #:delete (mk '#:delete) #:insert (mk '#:insert) #:home (mk '#:home)
       #:end (mk '#:end) #:pageup (mk '#:pageup) #:pagedown (mk '#:pagedown)
       #:any (mk '#:any)))
    (λ (ev) (set! hit #f) (handler ev) hit)))

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
   (put-styled 'title "═══ 输入事件调试器 (raw / event / callback) ═══") (put-newline)
   (put-styled 'info "按 q 退出 · 组合键: Alt+x / Ctrl+方向键 / Ctrl+Alt+x · 鼠标 / 粘贴") (put-newline)
   (put-newline)
   (define running? #t)
   (define count 0)
   (let loop ()
     (when running?
       (let-values ([(type data mods) (read-event/raw)])
         (define ev (normalize-event type data mods))
         (set! count (add1 count))
         (put-styled 'heading (format "事件 #~a:" count)) (put-newline)
         (put-string (format "  raw:    type=~a  data=~a  mods=~a"
                             type (show-bytes data) (describe-mods mods)))
         (put-newline)
         (put-string (format "  raw →   ~a" (describe-raw type data mods))) (put-newline)
         (put-string (format "  event:  ~a" (describe-event ev))) (put-newline)
         (put-styled 'success (format "  cb:     ~a" (probe ev))) (put-newline)
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
