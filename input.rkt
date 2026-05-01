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

;; 替换 extract-modifiers
(define (extract-modifiers ps)
  ;; 只有多参数序列才可能含修饰键
  (if (<= (length ps) 1)
      (cons #f #f)
      (let ([ctrl? (ormap (λ (p) (memv p '(5 7))) ps)]
            [alt?  (ormap (λ (p) (memv p '(3 7))) ps)])
        (cons ctrl? alt?))))

;; CSI 键类型
(define csi-key-table '((65 . up) (66 . down) (67 . right) (68 . left)
                                  (72 . home) (70 . end)
                                  ;; 对于 ~ 结尾的序列，需要看参数
                                  ))

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
               ;; 将 (csi-final->type final) 改为 (csi-params-final->type ps final)
               [(= b2 91)
                (define seq (read-csi-seq b2)) (change-noblock)
                (let-values ([(ps final) (parse-csi-params seq)])
                  (define mods (extract-modifiers ps))
                  (if (or (car mods) (cdr mods))
                      (values 'mod-seq seq mods)
                      (values (csi-params-final->type ps final) seq #f)))]
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

(provide read-event event-null? event-key? event-utf8? event-seq? event-ctrl? event-alt?
         event-mod-seq? event-resize? event-up? event-down? event-left? event-right?
         event-del? event-insert? event-home? event-end? event-pageup? event-pagedown?
         event-tab? event-backspace? ctrl->char alt->char mod-seq->char
         get-resize-rows get-resize-cols get-resize-size event->string event->byte)