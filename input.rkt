;; input.rkt
#lang racket
(require "base.rkt" "resize.rkt" "autoresources.rkt")

(define ESC 27)

;; 字节分类
(define (utf8-multi-start? b) (>= b 194))
(define (utf8-length b) (cond [(<= 194 b 223) 2] [(<= 224 b 239) 3] [(<= 240 b 244) 4] [else 1]))
(define (csi-done? b) (<= 64 b 126))
(define (ctrl-char? b) (and (integer? b) (<= 0 b 31) (not (memv b '(9 10 13 27)))))

;; CSI 参数解析
(define (parse-csi-params bytes)
  (let loop ([i 2] [cur 0] [ps '()])
    (if (>= i (bytes-length bytes)) (values '() 0)
        (let ([b (bytes-ref bytes i)])
          (cond [(<= 48 b 57) (loop (+ i 1) (+ (* cur 10) (- b 48)) ps)]
                [(= b 59)     (loop (+ i 1) 0 (append ps (list cur)))]
                [(csi-done? b) (if (and (= i 2) (zero? cur) (null? ps))
                                   (values '() b)
                                   (values (append ps (list cur)) b))]
                [else         (loop (+ i 1) cur ps)])))))

;; 提取修饰键
(define (extract-modifiers ps)
  ;; 只有多参数序列才可能含修饰键
  (if (<= (length ps) 1)
      (cons #f #f)
      (let ([ctrl? (ormap (λ (p) (memv p '(5 7))) ps)]
            [alt?  (ormap (λ (p) (memv p '(3 7))) ps)])
        (cons ctrl? alt?))))

;; CSI 键类型
(define csi-key-table '((65 . up) (66 . down) (67 . right) (68 . left)
                                  (72 . home) (70 . end)))

;; 需要根据 params 和 final 联合判断
(define (csi-params-final->type ps final)
  (cond
    ;; ~ 结尾的序列，看第一个参数
    [(= final 126)
     (case (and (pair? ps) (car ps))
       [(3) 'del]
       [(2) 'insert]
       [(5) 'pageup]
       [(6) 'pagedown]
       [else 'seq])]
    ;; 其他直接根据 final 判断
    [else
     (define p (assv final '((65 . up) (66 . down) (67 . right) (68 . left)
                                       (72 . home) (70 . end))))
     (if p (cdr p) 'seq)]))

;; 鼠标事件解析
(define (parse-mouse-event ps final)
  ;; SGR 鼠标事件 (final 为 'M' 或 'm')
  (let* ([type (car ps)]
         [x (cadr ps)]
         [y (caddr ps)]
         [button-code (bitwise-and type 3)]
         [modifiers (arithmetic-shift type -2)]
         [is-move? (bitwise-bit-set? type 5)]
         [is-release? (and (= final 109) (not is-move?))]
         [button (case button-code
                   [(0) 'left]
                   [(1) 'middle]
                   [(2) 'right]
                   [else 'unknown])]
         [action (cond
                   [(<= 64 type 65) 'scroll]
                   [is-release? 'release]
                   [is-move? 'move]
                   [else 'press])]
         [scroll-direction (cond
                             [(= type 64) 'up]
                             [(= type 65) 'down]
                             [else #f])])

    ;; 构建事件详情列表
    (if scroll-direction
        (list action 'scroll scroll-direction (- x 1) (- y 1) modifiers)
        (list action button (- x 1) (- y 1) modifiers))))

;; 内部读取
(define (read-n-bytes count)
  (let loop ([n 0] [acc (bytes)])
    (if (>= n count) acc
        (let ([b (getc)]) (if (integer? b) (loop (+ n 1) (bytes-append acc (bytes b))) acc)))))

(define (read-csi-seq b2)
  (let loop ([acc (list ESC b2)])
    (let ([b (getc)])
      (if (integer? b) (let ([acc (append acc (list b))])
                         (if (csi-done? b) (list->bytes acc) (loop acc)))
          (list->bytes acc)))))

;; 读取粘贴内容
(define (read-paste-content)
  (let loop ([acc (bytes)])
    (define b (getc))
    (cond [(eq? b 'null)
           ;; 超时或错误，返回已收集的内容
           acc]
          [(= b ESC)
           ;; 可能是粘贴结束序列
           (define b2 (getc))
           (cond [(eq? b2 'null)
                  ;; ESC 后无数据，保留 ESC
                  (bytes-append acc (bytes ESC))]
                 [(= b2 91)  ; '['
                  ;; 继续检查是否为 ESC[201~
                  (define b3 (getc))
                  (define b4 (getc))
                  (define b5 (getc))
                  ;; 只有在读取到完整序列且为 ESC[201~ 时才结束
                  (if (and (integer? b3) (integer? b4) (integer? b5)
                           (= b3 50)      ; '2'
                           (= b4 49)      ; '1'
                           (= b5 126))    ; '~'
                      acc  ; 粘贴结束，返回内容
                      ;; 不是粘贴结束，将所有字节添加到内容中
                      (loop (bytes-append acc
                                          (bytes ESC b2)
                                          (if (integer? b3) (bytes b3) (bytes))
                                          (if (integer? b4) (bytes b4) (bytes))
                                          (if (integer? b5) (bytes b5) (bytes)))))]
                 [else
                  ;; 不是 '[' 开头的序列，继续收集
                  (loop (bytes-append acc (bytes ESC b2)))])]
          [else
           ;; 普通字节，继续收集
           (loop (bytes-append acc (bytes b)))])))

;; read-event 实现
(define (read-event-impl)
  (define first (getc))
  (cond [(eq? first 'null) (values 'null (bytes) #f)]
        [(ctrl-char? first) (values 'ctrl (bytes first) #f)]
        [(= first ESC)
         (change-block)
         (define b2 (getc))
         (cond [(eq? b2 'null) (change-noblock) (values 'key (bytes first) #f)]
               [(= b2 79)
                (define b3 (getc)) (change-noblock)
                (values 'seq (bytes first b2 (if (eq? b3 'null) '() b3)) #f)]
               [(= b2 91)
                (define seq (read-csi-seq b2))
                (let-values ([(ps final) (parse-csi-params seq)])
                  (cond
                    ;; 括号粘贴开始 ESC[200~
                    [(and (null? ps) (= final 126)
                          (= (bytes-length seq) 5)
                          (= (bytes-ref seq 2) 50)  ; '2'
                          (= (bytes-ref seq 3) 48)  ; '0'
                          (= (bytes-ref seq 4) 48)) ; '0'
                     (define content (read-paste-content))
                     (change-noblock)
                     (values 'paste content #f)]
                    ;; 鼠标事件检测 (final 为 'M'=77 或 'm'=109)
                    [(and (memv final '(77 109)) (>= (length ps) 3))
                     (change-noblock)
                     (values 'mouse (parse-mouse-event ps final) #f)]
                    ;; 原有的处理逻辑
                    [else
                     (change-noblock)
                     (define mods (extract-modifiers ps))
                     (if (or (car mods) (cdr mods))
                         (values 'mod-seq seq mods)
                         (values (csi-params-final->type ps final) seq #f))]))]
               [(<= 32 b2 126) (change-noblock) (values 'alt (bytes first b2) #f)]
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
  (let ([ri (check-resize!)]) (if ri (values 'resize ri #f) (read-event-impl))))

;; 事件判断
(define (event-null? t)     (eq? t 'null))     (define (event-key? t)      (eq? t 'key))
(define (event-utf8? t)     (eq? t 'utf8))     (define (event-seq? t)      (eq? t 'seq))
(define (event-ctrl? t)     (eq? t 'ctrl))     (define (event-alt? t)      (eq? t 'alt))
(define (event-mod-seq? t)  (eq? t 'mod-seq))  (define (event-resize? t)   (eq? t 'resize))
(define (event-up? t)       (eq? t 'up))       (define (event-down? t)     (eq? t 'down))
(define (event-left? t)     (eq? t 'left))     (define (event-right? t)    (eq? t 'right))
(define (event-del? t)      (eq? t 'del))      (define (event-insert? t)   (eq? t 'insert))
(define (event-home? t)     (eq? t 'home))     (define (event-end? t)      (eq? t 'end))
(define (event-pageup? t)   (eq? t 'pageup))   (define (event-pagedown? t) (eq? t 'pagedown))

;; 鼠标事件判断 - 统一接口
(define (event-touch? t)  (eq? t 'mouse))
(define (event-mouse? t)  (eq? t 'mouse))

;; 鼠标事件子类型判断
(define (mouse-press? detail)   (eq? (car detail) 'press))
(define (mouse-release? detail) (eq? (car detail) 'release))
(define (mouse-move? detail)    (eq? (car detail) 'move))
(define (mouse-scroll? detail)  (eq? (car detail) 'scroll))

;; 鼠标按钮判断
(define (mouse-left? detail)   (eq? (cadr detail) 'left))
(define (mouse-middle? detail) (eq? (cadr detail) 'middle))
(define (mouse-right? detail)  (eq? (cadr detail) 'right))

;; 滚轮方向判断
(define (scroll-up? detail)   (eq? (caddr detail) 'up))
(define (scroll-down? detail) (eq? (caddr detail) 'down))

;; 提取鼠标坐标
(define (mouse-x d)
  (if (eq? (car d) 'scroll)
      (cadddr d)  ; scroll 事件中坐标在位置4
      (caddr d)))  ; 普通鼠标事件中坐标在位置3

(define (mouse-y d)
  (if (eq? (car d) 'scroll)
      (car (cddddr d))  ; scroll 事件中坐标在位置5
      (cadddr d)))       ; 普通鼠标事件中坐标在位置4

(define (get-mouse-pos d) (values (mouse-x d) (mouse-y d)))

;; 提取鼠标修饰键
(define (mouse-modifiers d) (last d))

;; 粘贴事件判断
(define (event-paste? t) (eq? t 'paste))

(define (event-tab? t d)       (and (eq? t 'key) (bytes? d) (= (bytes-length d) 1) (= (bytes-ref d 0) 9)))
(define (event-backspace? t d) (and (eq? t 'key) (bytes? d) (= (bytes-length d) 1) (memv (bytes-ref d 0) '(8 127))))

;; 数据提取
(define (ctrl->char d)     (and (bytes? d) (= (bytes-length d) 1) (let ([b (bytes-ref d 0)]) (and (<= 1 b 26) (integer->char (+ b 64))))))
(define (alt->char d)      (and (bytes? d) (= (bytes-length d) 2) (bytes-ref d 1)))
(define (mod-seq->char d)  (and (bytes? d) (> (bytes-length d) 2) (bytes-ref d (sub1 (bytes-length d)))))
(define (get-resize-rows d) (car d))
(define (get-resize-cols d) (cdr d))
(define (get-resize-size d) (values (car d) (cdr d)))
(define (event->string d)  (with-handlers ([exn:fail? (const "")]) (bytes->string/utf-8 d)))
(define (event->byte d)    (and (= (bytes-length d) 1) (bytes-ref d 0)))

(provide read-event
         ;; 键盘事件
         event-null? event-key? event-utf8? event-seq? event-ctrl? event-alt?
         event-mod-seq? event-resize? event-up? event-down? event-left? event-right?
         event-del? event-insert? event-home? event-end? event-pageup? event-pagedown?
         event-tab? event-backspace?
         ;; 鼠标事件 - 统一接口
         event-touch? event-mouse?
         mouse-press? mouse-release? mouse-move? mouse-scroll?
         mouse-left? mouse-middle? mouse-right?
         scroll-up? scroll-down?
         mouse-x mouse-y get-mouse-pos
         mouse-modifiers
         ;; 粘贴事件
         event-paste?
         ;; 数据提取
         ctrl->char alt->char mod-seq->char
         get-resize-rows get-resize-cols get-resize-size event->string event->byte)