#lang racket

;; char 后端的输入事件模型 —— 自包含，不依赖 base/io/input.rkt（后者会拉 FFI/termios）。
;;
;; 归一化逻辑与 base/io/event.rkt 保持一致（复制自 base，便于零依赖）；
;; 但 read-event 从「脚本队列」取，而不是读真实终端。事件结构体也是 char 自己的
;; （两个后端不会在同一模块里混用，因此类型独立没问题）。

(require "../ansi/ansi-var.rkt"
         "../ansi/input-var.rkt")

(provide
 ;; 修饰键
 (struct-out mods) no-mods no-mods? ->mods mods->list
 ;; 事件结构体
 (struct-out key-event) (struct-out paste-event) (struct-out mouse-event)
 (struct-out resize-event) (struct-out null-event) (struct-out other-event)
 event?
 byte->key normalize-event
 ;; 低层类型/键判断（与 base 同名）
 event-null? event-key? event-utf8? event-seq? event-ctrl? event-alt?
 event-mod-seq? event-resize? event-up? event-down? event-left? event-right?
 event-del? event-insert? event-home? event-end? event-pageup? event-pagedown?
 event-backtab? event-mouse? event-paste?
 event-tab? event-space? event-backspace? event-enter? event-escape?
 mouse-press? mouse-release? mouse-move? mouse-scroll?
 mouse-left? mouse-middle? mouse-right?
 scroll-up? scroll-down?
 mouse-x mouse-y get-mouse-pos mouse-modifiers
 ctrl->char alt->char mod-seq->char mod-seq->key
 event->string event->byte classify-byte
 get-resize-rows get-resize-cols get-resize-size
 ;; 事件分发
 build-input
 ;; 脚本输入
 read-event read-event-noblock
 char-input-push! char-input-empty? char-input-clear! char-input-remaining
 char-input-close! char-input-exhausted? char-input-open?)

;; ── 修饰键 ───────────────────────────────────────────────

(struct mods (ctrl? alt? shift?) #:transparent)

(define no-mods (mods #f #f #f))

(define (no-mods? m)
  (and (mods? m)
       (not (or (mods-ctrl? m) (mods-alt? m) (mods-shift? m)))))

(define (->mods m)
  (cond [(mods? m) m]
        [(and (list? m) (= (length m) 3)) (mods (car m) (cadr m) (caddr m))]
        [else no-mods]))

(define (mods->list m)
  (if (mods? m) (list (mods-ctrl? m) (mods-alt? m) (mods-shift? m)) m))

;; ── 事件结构体 ───────────────────────────────────────────

(struct key-event    (key mods)               #:transparent)
(struct paste-event  (bytes text)             #:transparent)
(struct mouse-event  (action button x y mods) #:transparent)
(struct resize-event (rows cols)              #:transparent)
(struct null-event   ()                       #:transparent)
(struct other-event  (type data mods)         #:transparent)

(define (event? v)
  (or (key-event? v) (paste-event? v) (mouse-event? v)
      (resize-event? v) (null-event? v) (other-event? v)))

(define (byte->key b)
  (cond [(= b TAB) 'tab]
        [(memv b (list LF CR)) 'enter]
        [(memv b (list BACKSPACE DELETE)) 'backspace]
        [(= b ESC) 'escape]
        [else (integer->char b)]))

;; ── 纯解码辅助（复制自 base/io/input.rkt）────────────────

(define (ctrl->char d)
  (and (bytes? d) (= (bytes-length d) 1)
       (let ([b (bytes-ref d 0)])
         (and (<= 1 b 26) (integer->char (+ b 64))))))

(define (alt->char d)
  (and (bytes? d) (>= (bytes-length d) 2)
       (let ([s (with-handlers ([exn:fail? (λ (_) #f)])
                  (bytes->string/utf-8 (subbytes d 1)))])
         (and s (positive? (string-length s)) (string-ref s 0)))))

(define (find-last-sep d hi)
  (let loop ([i hi])
    (cond [(< i 1) #f]
          [(= (bytes-ref d i) CSI-PARAM-SEP) i]
          [else (loop (sub1 i))])))

(define (parse-number d lo hi)
  (let loop ([i lo] [acc 0])
    (if (>= i hi)
        acc
        (let ([b (bytes-ref d i)])
          (if (<= ASCII-DIGIT-START b ASCII-DIGIT-END)
              (loop (+ i 1) (+ (* acc 10) (- b ASCII-DIGIT-START)))
              #f)))))

(define (parse-modify-other-keys-code d)
  (define n (bytes-length d))
  (and (>= n 9)
       (= (bytes-ref d 0) ESC)
       (= (bytes-ref d 1) CSI-OPEN)
       (= (bytes-ref d (sub1 n)) TILDE)
       (let ([last-sep (find-last-sep d (- n 2))])
         (and last-sep (parse-number d (+ last-sep 1) (sub1 n))))))

(define (mod-seq->char d)
  (and (bytes? d)
       (let ([code (parse-modify-other-keys-code d)])
         (and code
              (<= 0 code #x10FFFF)
              (not (<= #xD800 code #xDFFF))
              (integer->char code)))))

(define (mod-seq-first-param d)
  (let loop ([i 2] [acc 0])
    (define b (bytes-ref d i))
    (if (<= ASCII-DIGIT-START b ASCII-DIGIT-END)
        (loop (+ i 1) (+ (* acc 10) (- b ASCII-DIGIT-START)))
        acc)))

(define (mod-seq->key d)
  (define n (bytes-length d))
  (define last (and (> n 2) (bytes-ref d (sub1 n))))
  (cond
    [(and (>= n 4)
          (= (bytes-ref d 0) ESC) (= (bytes-ref d 1) CSI-OPEN)
          (= (bytes-ref d 2) 50) (= (bytes-ref d 3) 55)) #f]
    [(= last TILDE)
     (case (mod-seq-first-param d)
       [(2) KEY-INSERT] [(3) KEY-DELETE]
       [(5) KEY-PAGEUP] [(6) KEY-PAGEDOWN]
       [(1) KEY-HOME]   [(4) KEY-END]
       [else #f])]
    [else
     (case last
       [(65) KEY-UP] [(66) KEY-DOWN] [(67) KEY-RIGHT] [(68) KEY-LEFT]
       [(72) KEY-HOME] [(70) KEY-END] [(90) KEY-BACKTAB]
       [else #f])]))

(define (event->string d)
  (with-handlers ([exn:fail? (const "")])
    (bytes->string/utf-8 d)))

(define (event->byte d)
  (and (= (bytes-length d) 1) (bytes-ref d 0)))

(define (utf8-multi-start? b) (>= b UTF8-2BYTE-START))
(define (utf8-length b)
  (cond [(<= UTF8-2BYTE-START b UTF8-2BYTE-END) 2]
        [(<= UTF8-3BYTE-START b UTF8-3BYTE-END) 3]
        [(<= UTF8-4BYTE-START b UTF8-4BYTE-END) 4]
        [else 1]))
(define (ctrl-char? b)
  (and (integer? b) (<= 0 b 31)
       (not (memv b (list TAB LF CR ESC BACKSPACE)))))

;; 单字节分类（与 base 同名；脚本输入一般不直接用它）
(define (classify-byte b)
  (cond [(ctrl-char? b) 'ctrl]
        [(= b ESC) 'escape]
        [(utf8-multi-start? b) 'utf8]
        [else 'key]))

(define (get-resize-rows d) (car d))
(define (get-resize-cols d) (cdr d))
(define (get-resize-size d) (values (car d) (cdr d)))

;; ── 低层原始事件判断（与 base 同名）──────────────────────

(define (event-null? t)     (eq? t EVENT-NULL))
(define (event-key? t)      (eq? t EVENT-KEY))
(define (event-utf8? t)     (eq? t EVENT-UTF8))
(define (event-seq? t)      (eq? t EVENT-SEQ))
(define (event-ctrl? t)     (eq? t EVENT-CTRL))
(define (event-alt? t)      (eq? t EVENT-ALT))
(define (event-mod-seq? t)  (eq? t EVENT-MOD))
(define (event-resize? t)   (eq? t EVENT-RESIZE))
(define (event-up? t)       (eq? t KEY-UP))
(define (event-down? t)     (eq? t KEY-DOWN))
(define (event-left? t)     (eq? t KEY-LEFT))
(define (event-right? t)    (eq? t KEY-RIGHT))
(define (event-del? t)      (eq? t KEY-DELETE))
(define (event-insert? t)   (eq? t KEY-INSERT))
(define (event-home? t)     (eq? t KEY-HOME))
(define (event-end? t)      (eq? t KEY-END))
(define (event-pageup? t)   (eq? t KEY-PAGEUP))
(define (event-pagedown? t) (eq? t KEY-PAGEDOWN))
(define (event-backtab? t)  (eq? t KEY-BACKTAB))
(define (event-mouse? t)    (eq? t EVENT-MOUSE))
(define (event-paste? t)    (eq? t EVENT-PASTE))

(define (event-tab? t d)
  (and (eq? t EVENT-KEY) (bytes? d) (= (bytes-length d) 1) (= (bytes-ref d 0) TAB)))
(define (event-space? t d)
  (and (eq? t EVENT-KEY) (bytes? d) (= (bytes-length d) 1) (= (bytes-ref d 0) SPACE)))
(define (event-backspace? t d)
  (and (eq? t EVENT-KEY) (bytes? d) (= (bytes-length d) 1)
       (memv (bytes-ref d 0) (list BACKSPACE DELETE))))
(define (event-enter? t d)
  (and (eq? t EVENT-KEY) (bytes? d) (= (bytes-length d) 1)
       (memv (bytes-ref d 0) (list LF CR))))
(define (event-escape? t d)
  (and (eq? t EVENT-KEY) (bytes? d) (= (bytes-length d) 1) (= (bytes-ref d 0) ESC)))

(define (mouse-press? detail)   (eq? (car detail) EVENT-MOUSE-PRESS))
(define (mouse-release? detail) (eq? (car detail) EVENT-MOUSE-RELEASE))
(define (mouse-move? detail)    (eq? (car detail) EVENT-MOUSE-MOVE))
(define (mouse-scroll? detail)  (eq? (car detail) EVENT-MOUSE-SCROLL))
(define (mouse-left? detail)   (eq? (cadr detail) BUTTON-LEFT))
(define (mouse-middle? detail) (eq? (cadr detail) BUTTON-MIDDLE))
(define (mouse-right? detail)  (eq? (cadr detail) BUTTON-RIGHT))
(define (scroll-up? detail)   (eq? (caddr detail) SCROLL-UP))
(define (scroll-down? detail) (eq? (caddr detail) SCROLL-DOWN))
(define (mouse-x d)
  (if (eq? (car d) EVENT-MOUSE-SCROLL) (cadddr d) (caddr d)))
(define (mouse-y d)
  (if (eq? (car d) EVENT-MOUSE-SCROLL) (car (cddddr d)) (cadddr d)))
(define (get-mouse-pos d) (values (mouse-x d) (mouse-y d)))
(define (mouse-modifiers d) (last d))

;; ── 归一化 ───────────────────────────────────────────────

(define (ctrl-byte->key data)
  (or (ctrl->char data)
      (and (bytes? data) (= (bytes-length data) 1)
           (let ([b (bytes-ref data 0)])
             (if (zero? b) #\space (integer->char b))))))

(define (normalize-mouse data fallback-mods)
  (match data
    [(list 'press b x y ms)   (mouse-event 'press b x y (->mods ms))]
    [(list 'release b x y ms) (mouse-event 'release b x y (->mods ms))]
    [(list 'move x y ms)      (mouse-event 'move #f x y (->mods ms))]
    [(list 'scroll d x y ms)  (mouse-event 'scroll d x y (->mods ms))]
    [_ (other-event 'mouse data fallback-mods)]))

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
     (let ([key (ctrl-byte->key data)])
       (if key
           (key-event key (mods #t (mods-alt? m) (mods-shift? m)))
           (other-event type data m)))]
    [(alt)
     (let ([c (alt->char data)])
       (if c
           (key-event c (mods (mods-ctrl? m) #t (mods-shift? m)))
           (other-event type data m)))]
    [(mod-seq)
     (let ([key (or (mod-seq->key data) (mod-seq->char data))])
       (if key (k key) (other-event type data m)))]
    [(utf8)
     (let ([s (event->string data)])
       (if (= (string-length s) 1)
           (k (string-ref s 0))
           (other-event type data m)))]
    [(up) (k 'up)] [(down) (k 'down)] [(left) (k 'left)] [(right) (k 'right)]
    [(del) (k 'del)] [(insert) (k 'insert)] [(home) (k 'home)] [(end) (k 'end)]
    [(pageup) (k 'pageup)] [(pagedown) (k 'pagedown)] [(backtab) (k 'backtab)]
    [else (other-event type data m)]))

;; ── 事件分发器（与 base/io/build-input.rkt 的 build-input 一致）──

(define (build-input
          #:key [on-key #f]
          #:text [on-text #f]
          #:paste [on-paste #f]
          #:mouse [on-mouse #f]
          #:resize [on-resize #f]
          #:null [on-null #f]
          #:any [on-any #f]
          #:tab [on-tab #f]
          #:backtab [on-backtab #f]
          #:space [on-space #f]
          #:enter [on-enter #f]
          #:backspace [on-backspace #f]
          #:escape [on-escape #f]
          #:up [on-up #f]
          #:down [on-down #f]
          #:left [on-left #f]
          #:right [on-right #f]
          #:delete [on-delete #f]
          #:insert [on-insert #f]
          #:home [on-home #f]
          #:end [on-end #f]
          #:pageup [on-pageup #f]
          #:pagedown [on-pagedown #f])

  (define (any ev) (when on-any (on-any ev)))

  (define (shortcut-handler key)
    (cond [(eqv? key #\space) on-space]
          [(symbol? key)
           (case key
             [(tab) on-tab] [(backtab) on-backtab] [(enter) on-enter]
             [(escape) on-escape] [(backspace) on-backspace] [(up) on-up] [(down) on-down]
             [(left) on-left] [(right) on-right] [(del) on-delete]
             [(insert) on-insert] [(home) on-home] [(end) on-end]
             [(pageup) on-pageup] [(pagedown) on-pagedown]
             [else #f])]
          [else #f]))

  (define (text-key? key mods)
    (and (char? key) (not (mods-ctrl? mods)) (not (mods-alt? mods))))

  (lambda (ev)
    (match ev
      [(null-event)
       (if on-null (on-null) (any ev))]
      [(resize-event rows cols)
       (if on-resize (on-resize rows cols) (any ev))]
      [(paste-event bytes text)
       (cond [on-paste (on-paste bytes)]
             [on-text (on-text text)]
             [else (any ev)])]
      [(mouse-event action button x y mods)
       (if on-mouse (on-mouse action button x y mods) (any ev))]
      [(key-event key mods)
       (define shortcut (and (no-mods? mods) (shortcut-handler key)))
       (cond [shortcut (shortcut)]
             [(and (text-key? key mods) on-text) (on-text (string key))]
             [on-key (on-key key mods)]
             [else (any ev)])]
      [(other-event _ _ _) (any ev)]
      [_ (any ev)])))

;; ── 脚本输入 ─────────────────────────────────────────────
;;
;; 设计要点：read-event 默认 **阻塞**（与真实终端一致），队列为空且未关闭时
;; 等待新事件，因此不会空转；read-event-noblock 才是非阻塞。
;;
;; 脚本跑完后用 char-input-close! 标记结束，此时 read-event 返回
;; null-event，配合 (char-input-exhausted?) 作为循环停止条件即可有界退出。
;; 若要「脚本跑完自动结束、且每事件只输出一帧」，直接用 char-run。

(define queue (box '()))
(define closed? (box #f))
(define sema (box (make-semaphore 0)))

(define (spec->event s)
  (cond
    [(event? s) s]
    [(char? s) (key-event s no-mods)]
    [(symbol? s) (key-event s no-mods)]
    [(and (list? s) (= (length s) 2) (mods? (cadr s)))
     (key-event (car s) (cadr s))]
    [(and (list? s) (= (length s) 3))
     (normalize-event (car s) (cadr s) (caddr s))]
    [else (error 'char-input-push! "无法识别的输入 spec: ~a" s)]))

(define (char-input-push! . specs)
  (define was-empty? (null? (unbox queue)))
  (for ([s specs])
    (set-box! queue (append (unbox queue) (list (spec->event s)))))
  ;; 仅当队列由空变非空时唤醒一个等待者，避免陈旧的 semaphore 计数
  (when (and was-empty? (pair? (unbox queue)))
    (semaphore-post (unbox sema))))

(define (char-input-empty?) (null? (unbox queue)))
(define (char-input-remaining) (length (unbox queue)))
(define (char-input-open?) (not (unbox closed?)))
(define (char-input-exhausted?) (and (unbox closed?) (null? (unbox queue))))

;; 清空并重新打开（可重复利用同一进程内的多次脚本）
(define (char-input-clear!)
  (set-box! queue '())
  (set-box! closed? #f)
  (set-box! sema (make-semaphore 0)))

;; 标记脚本结束：唤醒等待者；队列排空后 read-event 返回 null-event
(define (char-input-close!)
  (set-box! closed? #t)
  (semaphore-post (unbox sema)))

(define (dequeue!)
  (define q (unbox queue))
  (set-box! queue (cdr q))
  (car q))

;; 阻塞：队列空且未关闭时等待；关闭且空时返回 null-event
(define (read-event)
  (let loop ()
    (cond [(pair? (unbox queue)) (dequeue!)]
          [(unbox closed?) (null-event)]
          [else (semaphore-wait (unbox sema)) (loop)])))

;; 非阻塞：无事件立即返回 null-event
(define (read-event-noblock)
  (if (pair? (unbox queue)) (dequeue!) (null-event)))
