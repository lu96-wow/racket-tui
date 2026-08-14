#lang racket
(require "../terminal/base.rkt" "../terminal/resize.rkt" "../terminal/config.rkt"
         "../ansi/ansi-var.rkt" "../ansi/input-var.rkt")

;; 字节分类函数

(define (utf8-multi-start? b) (>= b UTF8-2BYTE-START))

(define (utf8-length b)
  (cond [(<= UTF8-2BYTE-START b UTF8-2BYTE-END) 2]
        [(<= UTF8-3BYTE-START b UTF8-3BYTE-END) 3]
        [(<= UTF8-4BYTE-START b UTF8-4BYTE-END) 4]
        [else 1]))

(define (csi-done? b) (<= CSI-FINAL-START b CSI-FINAL-END))

(define (ctrl-char? b)
  (and (integer? b) (<= 0 b 31)
       (not (memv b (list TAB LF CR ESC)))))

;; CSI 参数解析

(define (parse-csi-params bytes)
  (let loop ([i 2] [cur 0] [ps '()])
    (if (>= i (bytes-length bytes)) (values '() 0)
        (let ([b (bytes-ref bytes i)])
          (cond [(<= ASCII-DIGIT-START b ASCII-DIGIT-END)
                 (loop (+ i 1) (+ (* cur 10) (- b ASCII-DIGIT-START)) ps)]
                [(= b CSI-PARAM-SEP)
                 (loop (+ i 1) 0 (append ps (list cur)))]
                [(csi-done? b)
                 (if (and (= i 2) (zero? cur) (null? ps))
                     (values '() b)
                     (values (append ps (list cur)) b))]
                [else (loop (+ i 1) cur ps)])))))

;; 提取修饰键
(define (extract-modifiers ps)
  (if (<= (length ps) 1)
      (cons #f #f)
      (let ([ctrl? (ormap (λ (p) (memv p (list MOD-CTRL MOD-ALT-CTRL))) ps)]
            [alt?  (ormap (λ (p) (memv p (list MOD-ALT MOD-ALT-CTRL))) ps)])
        (cons ctrl? alt?))))

;; CSI 键类型映射
(define (csi-params-final->type ps final)
  (cond
    [(= final TILDE)
     (case (and (pair? ps) (car ps))
       [(3) KEY-DELETE]
       [(2) KEY-INSERT]
       [(5) KEY-PAGEUP]
       [(6) KEY-PAGEDOWN]
       [else EVENT-SEQ])]
    [else
     (case final
       [(65) KEY-UP]     ; CSI A
       [(66) KEY-DOWN]   ; CSI B
       [(67) KEY-RIGHT]  ; CSI C
       [(68) KEY-LEFT]   ; CSI D
       [(72) KEY-HOME]   ; CSI H
       [(70) KEY-END]    ; CSI F
       [else EVENT-SEQ])]))

;; 鼠标事件解析

(define (parse-mouse-event ps final)
  (let* ([type (car ps)]
         [x (cadr ps)]
         [y (caddr ps)]
         [button-code (bitwise-and type MOUSE-BUTTON-MASK)]
         [modifiers (arithmetic-shift type -2)]
         [is-move? (bitwise-bit-set? type MOUSE-MOVE-FLAG)]
         [is-release? (and (= final MOUSE-RELEASE) (not is-move?))]
         [button (case button-code
                   [(0) BUTTON-LEFT]
                   [(1) BUTTON-MIDDLE]
                   [(2) BUTTON-RIGHT]
                   [else BUTTON-UNKNOWN])]
         [action (cond
                   [(<= MOUSE-SCROLL-START type MOUSE-SCROLL-END) EVENT-MOUSE-SCROLL]
                   [is-release? EVENT-MOUSE-RELEASE]
                   [is-move? EVENT-MOUSE-MOVE]
                   [else EVENT-MOUSE-PRESS])]
         [scroll-direction (cond
                             [(= type MOUSE-SCROLL-START) SCROLL-UP]
                             [(= type MOUSE-SCROLL-END) SCROLL-DOWN]
                             [else #f])])
    (if scroll-direction
        (list action EVENT-MOUSE-SCROLL scroll-direction x y modifiers)
        (list action button x y modifiers))))

;; ════════════════════════════════════════════════════════════════
;; ncurses ESCDELAY 超时机制 — 解决独立 ESC 空转 + 防御性上限
;; ════════════════════════════════════════════════════════════════

;; ESCDELAY / CSI-MAX-BYTES / PASTE-MAX-BYTES 见 config.rkt

;; 带超时的单字节读取, 绝不空转 (sync/timeout 与调度器协作)
;; 返回 byte 或 #f (超时/EOF)
(define (read-byte/timeout timeout-sec)
  (define evt (sync/timeout timeout-sec (make-stdin-evt)))
  (and (bytes? evt) (= (bytes-length evt) 1) (bytes-ref evt 0)))

;; 内部解析函数

(define (read-n-bytes count)
  (let loop ([n 0] [acc (bytes)])
    (if (>= n count) acc
        (let ([b (read-byte/timeout UTF8-READ-TIMEOUT)])
          (if b
              (loop (+ n 1) (bytes-append acc (bytes b)))
              acc)))))

(define (read-csi-seq b2)
  (let loop ([acc (list ESC b2)] [left CSI-MAX-BYTES])
    (if (zero? left)
        (list->bytes acc)
        (let ([b (read-byte/timeout ESCDELAY)])
          (cond [(not b) (list->bytes acc)]
                [(csi-done? b) (list->bytes (append acc (list b)))]
                [else (loop (append acc (list b)) (sub1 left))])))))

(define (read-paste-content)
  (let loop ([acc (bytes)] [left PASTE-MAX-BYTES])
    (if (zero? left) acc
        (let ([b (read-byte/timeout PASTE-READ-TIMEOUT)])
          (cond [(not b) acc]
              [(= b ESC)
               (define b2 (read-byte/timeout ESCDELAY))
               (cond [(not b2) (bytes-append acc (bytes ESC))]
                     [(= b2 CSI-OPEN)
                      (define b3 (read-byte/timeout ESCDELAY))
                      (define b4 (read-byte/timeout ESCDELAY))
                      (define b5 (read-byte/timeout ESCDELAY))
                      (if (and b3 b4 b5
                               (= b3 BRACKETED-PASTE-END-1)
                               (= b4 BRACKETED-PASTE-END-2)
                               (= b5 BRACKETED-PASTE-END-3))
                          (begin (read-byte/timeout ESCDELAY) acc)
                          (loop (bytes-append acc
                                   (bytes ESC) (bytes b2)
                                   (bytes b3) (bytes b4) (bytes b5))
                                (sub1 left)))]
                     [else (loop (bytes-append acc (bytes ESC) (bytes b2))
                                 (sub1 left))])]
              [else (loop (bytes-append acc (bytes b))
                          (sub1 left))])))))

;; read-event 核心 — ESC 后用 ESCDELAY 超时区分独立 ESC vs 序列

(define (read-event-impl first)
  (cond [(ctrl-char? first) (values EVENT-CTRL (bytes first) #f)]
        [(= first ESC)
         (define b2 (read-byte/timeout ESCDELAY))
         (cond [(not b2) (values EVENT-KEY (bytes first) #f)]    ; 独立 ESC
               [(= b2 CSI-SS3)
                (define b3 (read-byte/timeout ESCDELAY))
                (values EVENT-SEQ (bytes first b2 (if b3 b3 '())) #f)]
               [(= b2 CSI-OPEN)
                (define seq (read-csi-seq b2))
                (let-values ([(ps final) (parse-csi-params seq)])
                  (cond
                    [(and (= final TILDE)
                          (= (bytes-length seq) CSI-PASTE-SEQ-LEN)
                          (= (bytes-ref seq 2) BRACKETED-PASTE-START-1)
                          (= (bytes-ref seq 3) BRACKETED-PASTE-START-2)
                          (= (bytes-ref seq 4) BRACKETED-PASTE-START-3))
                     (define content (read-paste-content))
                     (values EVENT-PASTE content #f)]
                    [(and (memv final (list MOUSE-EVENT MOUSE-RELEASE))
                          (>= (length ps) 3))
                     (values EVENT-MOUSE (parse-mouse-event ps final) #f)]
                    [else
                     (define mods (extract-modifiers ps))
                     (if (or (car mods) (cdr mods))
                         (values EVENT-MOD seq mods)
                         (values (csi-params-final->type ps final) seq #f))]))]
               [(<= ASCII-PRINTABLE-START b2 ASCII-PRINTABLE-END)
                (values EVENT-ALT (bytes first b2) #f)]
               [else (values EVENT-SEQ (bytes first b2) #f)])]
        [(utf8-multi-start? first)
         (define rest (read-n-bytes (sub1 (utf8-length first))))
         (values EVENT-UTF8 (bytes-append (bytes first) rest) #f)]
        [else (values EVENT-KEY (bytes first) #f)]))

;; resize 监控 — 见 terminal/resize.rkt: signalfd 事件, 无轮询线程
;; read-event 的 sync 统一等 stdin-evt + resize-evt, 调度器协作, 零 CPU

;; read-event — sync 统一等 stdin 和 resize 事件
;; 阻塞模式, 零 CPU, 等价于 ncurses getch()
(define (read-event)
  (define evt (sync (make-stdin-evt) (make-resize-evt)))
  (cond [(bytes? evt)
         ;; stdin 来了 1 个字节
         (read-event-impl (bytes-ref evt 0))]
        [(pair? evt)
         ;; resize 事件: (rows . cols)
         (values EVENT-RESIZE evt #f)]
        [else (values EVENT-NULL (bytes) #f)]))

;; 非阻塞版本, 等价于 ncurses timeout(0) getch()
;; 无事件时 evt 为 #f (sync/timeout 返回), 返回 EVENT-NULL
(define (read-event-noblock)
  ;; sync/timeout 避免 CPU 空转，~60fps 足够流式刷新
  (define evt (sync/timeout 0.016 (make-stdin-evt) (make-resize-evt)))
  (cond [(bytes? evt)
         (read-event-impl (bytes-ref evt 0))]
        [(pair? evt)
         (values EVENT-RESIZE evt #f)]
        [else (values EVENT-NULL (bytes) #f)]))

;; 底层事件类型判断

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
(define (event-touch? t)    (eq? t EVENT-MOUSE))
(define (event-mouse? t)    (eq? t EVENT-MOUSE))
(define (event-paste? t)    (eq? t EVENT-PASTE))

;; 高层语义化事件判断
;; 注意：这些判断应该放在 event-key? 之前使用

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

;; 鼠标事件子类型判断

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
  (if (eq? (car d) EVENT-MOUSE-SCROLL)
      (cadddr d)
      (caddr d)))

(define (mouse-y d)
  (if (eq? (car d) EVENT-MOUSE-SCROLL)
      (car (cddddr d))
      (cadddr d)))

(define (get-mouse-pos d) (values (mouse-x d) (mouse-y d)))
(define (mouse-modifiers d) (last d))

;; 数据提取辅助函数

(define (ctrl->char d)
  (and (bytes? d) (= (bytes-length d) 1)
       (let ([b (bytes-ref d 0)])
         (and (<= 1 b 26) (integer->char (+ b 64))))))

(define (alt->char d)
  (and (bytes? d) (= (bytes-length d) 2) (bytes-ref d 1)))

(define (mod-seq->char d)
  (and (bytes? d) (> (bytes-length d) 2)
       (bytes-ref d (sub1 (bytes-length d)))))

(define (get-resize-rows d) (car d))
(define (get-resize-cols d) (cdr d))
(define (get-resize-size d) (values (car d) (cdr d)))

(define (event->string d)
  (with-handlers ([exn:fail? (const "")])
    (bytes->string/utf-8 d)))

(define (event->byte d)
  (and (= (bytes-length d) 1) (bytes-ref d 0)))

;; 导出

(provide read-event read-event-noblock
         event-null? event-key? event-utf8? event-seq? event-ctrl? event-alt?
         event-mod-seq? event-resize? event-up? event-down? event-left? event-right?
         event-del? event-insert? event-home? event-end? event-pageup? event-pagedown?
         event-touch? event-mouse? event-paste?
         event-tab? event-space? event-backspace? event-enter? event-escape?
         mouse-press? mouse-release? mouse-move? mouse-scroll?
         mouse-left? mouse-middle? mouse-right?
         scroll-up? scroll-down?
         mouse-x mouse-y get-mouse-pos
         mouse-modifiers
         ctrl->char alt->char mod-seq->char
         get-resize-rows get-resize-cols get-resize-size event->string event->byte)