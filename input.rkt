#lang racket
(require "base.rkt" "resize.rkt" "autoresources.rkt")

;; 常量定义 - 全部使用数字

;; ASCII 控制字符
(define TAB 9)           ; Tab
(define LF 10)           ; Line Feed
(define CR 13)           ; Carriage Return
(define ESC 27)          ; Escape
(define SPACE 32)        ; Space
(define DELETE 127)      ; Delete

;; ASCII 字符范围
(define ASCII-DIGIT-START 48)    ; '0'
(define ASCII-DIGIT-END 57)      ; '9'
(define ASCII-PRINTABLE-START 32)
(define ASCII-PRINTABLE-END 126)

;; CSI 序列字符
(define CSI-OPEN 91)     ; '['
(define CSI-SS3 79)      ; 'O'
(define CSI-FINAL-START 64)   ; '@'
(define CSI-FINAL-END 126)    ; '~'

;; 括号粘贴标记
(define BRACKETED-PASTE-START-1 50)   ; '2'
(define BRACKETED-PASTE-START-2 48)   ; '0'
(define BRACKETED-PASTE-START-3 48)   ; '0'
(define BRACKETED-PASTE-END-1 50)     ; '2'
(define BRACKETED-PASTE-END-2 48)     ; '0'
(define BRACKETED-PASTE-END-3 49)     ; '1'
(define TILDE 126)                    ; '~'

;; 鼠标事件标记
(define MOUSE-EVENT 77)      ; 'M' - 鼠标按下/移动
(define MOUSE-RELEASE 109)   ; 'm' - 鼠标释放

;; CSI 参数分隔符
(define CSI-PARAM-SEP 59)    ; ';'

;; UTF-8 编码范围
(define UTF8-2BYTE-START 194)
(define UTF8-2BYTE-END 223)
(define UTF8-3BYTE-START 224)
(define UTF8-3BYTE-END 239)
(define UTF8-4BYTE-START 240)
(define UTF8-4BYTE-END 244)

;; 修饰键参数值
(define MOD-ALT 3)       ; Alt 修饰符
(define MOD-CTRL 5)      ; Ctrl 修饰符
(define MOD-ALT-CTRL 7)  ; Alt+Ctrl

;; 鼠标事件类型位掩码
(define MOUSE-BUTTON-MASK #b11)      ; 按钮掩码 (bits 0-1)
(define MOUSE-MOVE-FLAG #b100000)    ; 移动标志 (bit 5)
(define MOUSE-SCROLL-START 64)       ; 滚轮向上
(define MOUSE-SCROLL-END 65)         ; 滚轮向下

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
       [(3) 'del]
       [(2) 'insert]
       [(5) 'pageup]
       [(6) 'pagedown]
       [else 'seq])]
    [else
     (case final
       [(65) 'up]     ; CSI A
       [(66) 'down]   ; CSI B
       [(67) 'right]  ; CSI C
       [(68) 'left]   ; CSI D
       [(72) 'home]   ; CSI H
       [(70) 'end]    ; CSI F
       [else 'seq])]))

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
                   [(0) 'left]
                   [(1) 'middle]
                   [(2) 'right]
                   [else 'unknown])]
         [action (cond
                   [(<= MOUSE-SCROLL-START type MOUSE-SCROLL-END) 'scroll]
                   [is-release? 'release]
                   [is-move? 'move]
                   [else 'press])]
         [scroll-direction (cond
                             [(= type MOUSE-SCROLL-START) 'up]
                             [(= type MOUSE-SCROLL-END) 'down]
                             [else #f])])
    (if scroll-direction
        (list action 'scroll scroll-direction (- x 1) (- y 1) modifiers)
        (list action button (- x 1) (- y 1) modifiers))))

;; 内部读取函数

(define (read-n-bytes count)
  (let loop ([n 0] [acc (bytes)])
    (if (>= n count) acc
        (let ([b (getc)])
          (if (integer? b)
              (loop (+ n 1) (bytes-append acc (bytes b)))
              acc)))))

(define (read-csi-seq b2)
  (let loop ([acc (list ESC b2)])
    (let ([b (getc)])
      (if (integer? b)
          (let ([acc (append acc (list b))])
            (if (csi-done? b) (list->bytes acc) (loop acc)))
          (list->bytes acc)))))

;; 读取粘贴内容
(define (read-paste-content)
  (let loop ([acc (bytes)])
    (define b (getc))
    (cond [(eq? b 'null) acc]
          [(= b ESC)
           (define b2 (getc))
           (cond [(eq? b2 'null)
                  (bytes-append acc (bytes ESC))]
                 [(= b2 CSI-OPEN)
                  (define b3 (getc))
                  (define b4 (getc))
                  (define b5 (getc))
                  (if (and (integer? b3) (integer? b4) (integer? b5)
                           (= b3 BRACKETED-PASTE-END-1)
                           (= b4 BRACKETED-PASTE-END-2)
                           (= b5 BRACKETED-PASTE-END-3))
                      acc
                      (loop (bytes-append acc
                                          (bytes ESC)
                                          (bytes b2)
                                          (if (integer? b3) (bytes b3) (bytes))
                                          (if (integer? b4) (bytes b4) (bytes))
                                          (if (integer? b5) (bytes b5) (bytes)))))]
                 [else
                  (loop (bytes-append acc (bytes ESC) (bytes b2)))])]
          [else
           (loop (bytes-append acc (bytes b)))])))

;; read-event 核心实现

(define (read-event-impl)
  (define first (getc))
  (cond [(eq? first 'null) (values 'null (bytes) #f)]
        [(ctrl-char? first) (values 'ctrl (bytes first) #f)]
        [(= first ESC)
         (change-block)
         (define b2 (getc))
         (cond [(eq? b2 'null) (change-noblock) (values 'key (bytes first) #f)]
               [(= b2 CSI-SS3)
                (define b3 (getc)) (change-noblock)
                (values 'seq (bytes first b2 (if (eq? b3 'null) '() b3)) #f)]
               [(= b2 CSI-OPEN)
                (define seq (read-csi-seq b2))
                (let-values ([(ps final) (parse-csi-params seq)])
                  (cond
                    [(and (null? ps) (= final TILDE)
                          (= (bytes-length seq) 5)
                          (= (bytes-ref seq 2) BRACKETED-PASTE-START-1)
                          (= (bytes-ref seq 3) BRACKETED-PASTE-START-2)
                          (= (bytes-ref seq 4) BRACKETED-PASTE-START-3))
                     (define content (read-paste-content))
                     (change-noblock)
                     (values 'paste content #f)]
                    [(and (memv final (list MOUSE-EVENT MOUSE-RELEASE))
                          (>= (length ps) 3))
                     (change-noblock)
                     (values 'mouse (parse-mouse-event ps final) #f)]
                    [else
                     (change-noblock)
                     (define mods (extract-modifiers ps))
                     (if (or (car mods) (cdr mods))
                         (values 'mod-seq seq mods)
                         (values (csi-params-final->type ps final) seq #f))]))]
               [(<= ASCII-PRINTABLE-START b2 ASCII-PRINTABLE-END)
                (change-noblock)
                (values 'alt (bytes first b2) #f)]
               [else (change-noblock) (values 'seq (bytes first b2) #f)])]
        [(utf8-multi-start? first)
         (change-block)
         (define rest (read-n-bytes (sub1 (utf8-length first))))
         (change-noblock)
         (values 'utf8 (bytes-append (bytes first) rest) #f)]
        [else (values 'key (bytes first) #f)]))

;; resize 监控

(define resize-channel (make-channel))

(define (resize-monitor-start)
  (let-values ([(r c) (get-window-size)])
    (thread (λ () (let loop ([pr r] [pc c])
                    (sleep 0.1)
                    (let-values ([(nr nc) (get-window-size)])
                      (when (and nr nc (or (not (= nr pr)) (not (= nc pc))))
                        (channel-put resize-channel (cons nr nc)))
                      (loop (or nr pr) (or nc pc))))))))

(define (resize-monitor-stop t) (kill-thread t))
(register-thread! 'resize resize-monitor-start resize-monitor-stop)

(define (check-resize!) (channel-try-get resize-channel))

(define (read-event)
  (let ([ri (check-resize!)])
    (if ri (values 'resize ri #f) (read-event-impl))))

;; 底层事件类型判断

(define (event-null? t)     (eq? t 'null))
(define (event-key? t)      (eq? t 'key))
(define (event-utf8? t)     (eq? t 'utf8))
(define (event-seq? t)      (eq? t 'seq))
(define (event-ctrl? t)     (eq? t 'ctrl))
(define (event-alt? t)      (eq? t 'alt))
(define (event-mod-seq? t)  (eq? t 'mod-seq))
(define (event-resize? t)   (eq? t 'resize))
(define (event-up? t)       (eq? t 'up))
(define (event-down? t)     (eq? t 'down))
(define (event-left? t)     (eq? t 'left))
(define (event-right? t)    (eq? t 'right))
(define (event-del? t)      (eq? t 'del))
(define (event-insert? t)   (eq? t 'insert))
(define (event-home? t)     (eq? t 'home))
(define (event-end? t)      (eq? t 'end))
(define (event-pageup? t)   (eq? t 'pageup))
(define (event-pagedown? t) (eq? t 'pagedown))
(define (event-touch? t)    (eq? t 'mouse))
(define (event-mouse? t)    (eq? t 'mouse))
(define (event-paste? t)    (eq? t 'paste))

;; 高层语义化事件判断
;; 注意：这些判断应该放在 event-key? 之前使用

(define (event-tab? t d)
  (and (eq? t 'key) (bytes? d) (= (bytes-length d) 1) (= (bytes-ref d 0) TAB)))

(define (event-space? t d)
  (and (eq? t 'key) (bytes? d) (= (bytes-length d) 1) (= (bytes-ref d 0) SPACE)))

(define (event-backspace? t d)
  (and (eq? t 'key) (bytes? d) (= (bytes-length d) 1)
       (memv (bytes-ref d 0) (list 8 DELETE))))

(define (event-enter? t d)
  (and (eq? t 'key) (bytes? d) (= (bytes-length d) 1)
       (memv (bytes-ref d 0) (list LF CR))))

(define (event-escape? t d)
  (and (eq? t 'key) (bytes? d) (= (bytes-length d) 1) (= (bytes-ref d 0) ESC)))

;; 鼠标事件子类型判断

(define (mouse-press? detail)   (eq? (car detail) 'press))
(define (mouse-release? detail) (eq? (car detail) 'release))
(define (mouse-move? detail)    (eq? (car detail) 'move))
(define (mouse-scroll? detail)  (eq? (car detail) 'scroll))

(define (mouse-left? detail)   (eq? (cadr detail) 'left))
(define (mouse-middle? detail) (eq? (cadr detail) 'middle))
(define (mouse-right? detail)  (eq? (cadr detail) 'right))

(define (scroll-up? detail)   (eq? (caddr detail) 'up))
(define (scroll-down? detail) (eq? (caddr detail) 'down))

(define (mouse-x d)
  (if (eq? (car d) 'scroll)
      (cadddr d)
      (caddr d)))

(define (mouse-y d)
  (if (eq? (car d) 'scroll)
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

(provide read-event
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