#lang racket
;; =============================================================================
;; event — 规范化输入事件（公共输入 API）
;;
;; read-event 返回一个事件结构体（event?），类型由语义决定，不再随字节编码
;; 漂移。修饰键统一为 mods 结构体。低层字节级接口在 input.rkt
;; （read-event/raw），仅用于调试或自定义协议。
;;
;;   key-event    (key mods)              key: char? | symbol?
;;   paste-event  (bytes text)            粘贴：原始字节 + UTF-8 宽松解码
;;   mouse-event  (action button x y mods)
;;   resize-event (rows cols)
;;   null-event   ()
;;   other-event  (type data mods)        无法识别/规范化的序列
;; =============================================================================
(require "input.rkt" "../ansi/ansi-var.rkt" "../ansi/input-var.rkt")

;; ─── 修饰键 ───
(struct mods (ctrl? alt? shift?) #:transparent)

(define no-mods (mods #f #f #f))

(define (no-mods? m)
  (and (mods? m)
       (not (or (mods-ctrl? m) (mods-alt? m) (mods-shift? m)))))

;; 位置化 list (ctrl? alt? shift?) 或 #f → mods 结构体
(define (->mods m)
  (cond [(mods? m) m]
        [(and (list? m) (= (length m) 3))
         (mods (car m) (cadr m) (caddr m))]
        [else no-mods]))

;; 兼容访问器：mods 结构体 → (list ctrl? alt? shift?)
(define (mods->list m)
  (if (mods? m) (list (mods-ctrl? m) (mods-alt? m) (mods-shift? m)) m))

;; ─── 事件结构体 ───
(struct key-event    (key mods)               #:transparent)
;; key: char?（可打印/控制字符）| symbol?（命名键，如 'up 'tab 'enter）
;; mods 含 ctrl/alt/shift。EVENT-CTRL / EVENT-ALT 隐含的修饰位已补回。

(struct paste-event  (bytes text)             #:transparent)
;; bytes: 原始粘贴字节；text: UTF-8 宽松解码（非法字节 → U+FFFD）

(struct mouse-event  (action button x y mods) #:transparent)
;; action: 'press | 'release | 'move | 'scroll
;; button: 'left | 'middle | 'right（press/release）
;;         'up | 'down（scroll，表示滚轮方向）
;;         #f（move）

(struct resize-event (rows cols)              #:transparent)
(struct null-event   ()                       #:transparent)
(struct other-event  (type data mods)         #:transparent)
;; 未识别的原始事件；type/data 为低层原值，mods 已规范化

(define (event? v)
  (or (key-event? v) (paste-event? v) (mouse-event? v)
      (resize-event? v) (null-event? v) (other-event? v)))

;; EVENT-KEY 单字节 → key：命名键符号 或 单个 char（含空格）
(define (byte->key b)
  (cond [(= b TAB) 'tab]
        [(memv b (list LF CR)) 'enter]
        [(memv b (list BACKSPACE DELETE)) 'backspace]
        [(= b ESC) 'escape]
        [else (integer->char b)]))

;; EVENT-CTRL data → key：Ctrl+字母 → #\A-#\Z；其余控制字节 → 对应 char
;; （byte 0 即 Ctrl+Space — → #\space）
(define (ctrl-byte->key data)
  (or (ctrl->char data)
      (and (bytes? data) (= (bytes-length data) 1)
           (let ([b (bytes-ref data 0)])
             (if (zero? b) #\space (integer->char b))))))

(define (normalize-mouse data fallback-mods)
  (match data
    [(list 'press b x y ms)   (mouse-event 'press b x y (->mods ms))]
    [(list 'release b x y ms) (mouse-event 'release b x y (->mods ms))]
    ;; move：raw = (move button x y ms)（button 多为 #f；规范化后按文档置 #f）
    [(list 'move _ x y ms)    (mouse-event 'move #f x y (->mods ms))]
    ;; 滚轮：raw = (scroll scroll dir x y ms) —— 比其它鼠标事件多一个类型位；
    ;;       mouse-x / mouse-y / mouse-modifiers 也是按这个形状取的。
    [(list 'scroll _ d x y ms) (mouse-event 'scroll d x y (->mods ms))]
    [_ (other-event 'mouse data fallback-mods)]))

;; 原始 (type data mods) → 规范事件
(define (normalize-event type data raw-mods)
  (define m (->mods raw-mods))
  (define (k key) (key-event key m))
  (case type
    [(null) (null-event)]
    [(resize) (resize-event (car data) (cdr data))]
    [(paste) (paste-event data (bytes->string/utf-8 data (integer->char 65533)))]
    [(mouse) (normalize-mouse data m)]
    [(key)
     (if (and (bytes? data) (= (bytes-length data) 1))
         (k (byte->key (bytes-ref data 0)))
         (other-event type data m))]
    [(ctrl)
     ;; EVENT-CTRL 隐含 Ctrl 修饰；raw mods 为 #f，补回 ctrl? 位
     (let ([key (ctrl-byte->key data)])
       (if key
           (key-event key (mods #t (mods-alt? m) (mods-shift? m)))
           (other-event type data m)))]
    [(alt)
     ;; EVENT-ALT 隐含 Alt 修饰
     (let ([c (alt->char data)])
       (if c
           (key-event c (mods (mods-ctrl? m) #t (mods-shift? m)))
           (other-event type data m)))]
    [(mod-seq)
     (let ([key (or (mod-seq->key data) (mod-seq->char data))])
       (cond
         [key (k key)]
         ;; ESC + 单控制/特殊字节：默认 xterm 下 Alt[+Ctrl]+键 的编码
         ;; （如 Ctrl+Alt+x = ESC ^X）。控制字节 1-26 → Ctrl+字母。
         [(and (bytes? data) (= (bytes-length data) 2)
               (= (bytes-ref data 0) ESC))
          (define b (bytes-ref data 1))
          (define ctrl-letter?
            (and (<= 1 b 26)
                 (not (memv b (list TAB LF CR BACKSPACE)))))
          (key-event (if ctrl-letter?
                         (integer->char (+ 64 b))
                         (byte->key b))
                     m)]
         [else (other-event type data m)]))]
    [(utf8)
     (let ([s (event->string data)])
       (if (= (string-length s) 1)
           (k (string-ref s 0))
           (other-event type data m)))]
    [(up) (k 'up)] [(down) (k 'down)] [(left) (k 'left)] [(right) (k 'right)]
    [(del) (k 'del)] [(insert) (k 'insert)] [(home) (k 'home)] [(end) (k 'end)]
    [(pageup) (k 'pageup)] [(pagedown) (k 'pagedown)] [(backtab) (k 'backtab)]
    [else (other-event type data m)]))

;; ─── 公共输入入口：返回 event? ───
(define (read-event)
  (let-values ([(t d m) (read-event/raw)]) (normalize-event t d m)))

(define (read-event-noblock)
  (let-values ([(t d m) (read-event-noblock/raw)]) (normalize-event t d m)))

(provide (struct-out mods) no-mods no-mods? ->mods mods->list
         (struct-out key-event) (struct-out paste-event) (struct-out mouse-event)
         (struct-out resize-event) (struct-out null-event) (struct-out other-event)
         event?
         byte->key normalize-event
         read-event read-event-noblock)
