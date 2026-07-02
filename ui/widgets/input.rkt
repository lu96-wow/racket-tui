#lang racket

(require "../component.rkt"
         "../../base/io/build-input.rkt"
         "../../base/io/output-styles.rkt"
         "../../base/io/output-color.rkt"
         "../../base/io/output.rkt")

(provide make-input)

;; ═══════════════════════════════════════════════
;; 字符显示宽度（终端列数）
;; ═══════════════════════════════════════════════
(define (char-display-width ch)
  (define cp (char->integer ch))
  (cond
    [(<= #x1100 cp #x115F) 2] [(<= #x2329 cp #x232A) 2]
    [(<= #x2E80 cp #x303E) 2] [(<= #x3040 cp #x33BF) 2]
    [(<= #x3400 cp #x4DBF) 2] [(<= #x4E00 cp #x9FFF) 2]
    [(<= #xA000 cp #xA4CF) 2] [(<= #xAC00 cp #xD7AF) 2]
    [(<= #xF900 cp #xFAFF) 2] [(<= #xFE10 cp #xFE19) 2]
    [(<= #xFE30 cp #xFE6F) 2] [(<= #xFF01 cp #xFF60) 2]
    [(<= #xFFE0 cp #xFFE6) 2]
    [(<= #x1F300 cp #x1F5FF) 2] [(<= #x1F600 cp #x1F64F) 2]
    [(<= #x1F680 cp #x1F6FF) 2] [(<= #x1F900 cp #x1F9FF) 2]
    [(<= #x20000 cp #x2FFFF) 2] [(<= #x30000 cp #x3FFFF) 2]
    [else 1]))

;; ═══════════════════════════════════════════════
;; buffer 纯函数: 输入 plain vector + idx, 返回新 vector
;; ═══════════════════════════════════════════════
(define (buffer-insert chars widths idx ch w)
  (define len (vector-length chars))
  (define cs (make-vector (add1 len)))
  (define ws (make-vector (add1 len)))
  (vector-copy! cs 0 chars 0 idx)
  (vector-copy! ws 0 widths 0 idx)
  (vector-set! cs idx ch)
  (vector-set! ws idx w)
  (vector-copy! cs (add1 idx) chars idx len)
  (vector-copy! ws (add1 idx) widths idx len)
  (values cs ws))

(define (buffer-backspace chars widths idx)
  (define ni (sub1 idx))
  (define len (vector-length chars))
  (define cs (make-vector (sub1 len)))
  (define ws (make-vector (sub1 len)))
  (vector-copy! cs 0 chars 0 ni)
  (vector-copy! ws 0 widths 0 ni)
  (vector-copy! cs ni chars idx len)
  (vector-copy! ws ni widths idx len)
  (values cs ws ni))

(define (buffer-delete chars widths idx)
  (define len (vector-length chars))
  (define cs (make-vector (sub1 len)))
  (define ws (make-vector (sub1 len)))
  (vector-copy! cs 0 chars 0 idx)
  (vector-copy! ws 0 widths 0 idx)
  (vector-copy! cs idx chars (add1 idx) len)
  (vector-copy! ws idx widths (add1 idx) len)
  (values cs ws))

(define (buffer->string chars) (list->string (vector->list chars)))

;; ═══════════════════════════════════════════════
;; make-input
;; ═══════════════════════════════════════════════
(define (make-input #:placeholder [placeholder ""]
                    #:on-submit [on-submit void]
                    #:on-change [on-change void])
  (define chars  (box (vector)))
  (define widths (box (vector)))
  (define cid    (box 0))
  (define dirty  (box #t))
  ;; 组件在屏幕上的位置（由 render 更新，供鼠标事件使用）
  (define pos-x  (box 0))
  (define pos-y  (box 0))
  (define pos-w  (box 0))

  (define (text-string) (buffer->string (unbox chars)))

  ;; 将鼠标绝对坐标转换为光标索引
  (define (mouse-xy->cid mx my)
    (define cs (unbox chars))
    (define ws (unbox widths))
    (define total (vector-length cs))
    (define w (unbox pos-w))
    ;; 空文本或无字符 → 光标在 0
    (when (zero? total)
      (set-box! cid 0)
      (set-box! dirty #t))
    (when (positive? total)
      (define ci (unbox cid))
      ;; 计算当前视口的起始索引（与 render 逻辑一致）
      (define cw (if (< ci total) (vector-ref ws ci) 1))
      (define start
        (let loop ([i ci] [rem (- w cw)])
          (if (or (<= i 0) (< rem (vector-ref ws (sub1 i))))
              i
              (loop (sub1 i) (- rem (vector-ref ws (sub1 i)))))))
      ;; 将相对 x 映射为字符索引
      (define rel-x (- mx (unbox pos-x)))
      (define new-cid
        (let loop ([i start] [rem rel-x])
          (cond [(>= i total) total]
                [(< rem (vector-ref ws i)) i]
                [else (loop (add1 i) (- rem (vector-ref ws i)))])))
      (when (not (= new-cid ci))
        (set-box! cid new-cid)
        (set-box! dirty #t))))

  (define (insert-char! str)
    (for ([ch (in-string str)])
      (let-values ([(cs ws) (buffer-insert (unbox chars) (unbox widths)
                                            (unbox cid) ch
                                            (char-display-width ch))])
        (set-box! chars cs)
        (set-box! widths ws)
        (set-box! cid (add1 (unbox cid)))))
    (set-box! dirty #t)
    (on-change (text-string)))

  (define (backspace!)
    (when (> (unbox cid) 0)
      (let-values ([(cs ws ni) (buffer-backspace (unbox chars) (unbox widths)
                                                  (unbox cid))])
        (set-box! chars cs)
        (set-box! widths ws)
        (set-box! cid ni))
      (set-box! dirty #t)
      (on-change (text-string))))

  (define (delete!)
    (when (< (unbox cid) (vector-length (unbox chars)))
      (let-values ([(cs ws) (buffer-delete (unbox chars) (unbox widths)
                                            (unbox cid))])
        (set-box! chars cs)
        (set-box! widths ws))
      (set-box! dirty #t)
      (on-change (text-string))))

  (component
   (λ (focused? x y w h)
     ;; 记录组件位置，供鼠标事件使用
     (set-box! pos-x x)
     (set-box! pos-y y)
     (set-box! pos-w w)
     ;; 清区域
     (for ([i (in-range h)])
       (cursor-move (+ y i) x)
       (put-string (make-string w #\space)))

     (define cs (unbox chars))
     (define ws (unbox widths))
     (define ci (unbox cid))
     (define total (vector-length cs))

     (if (and (zero? total) (not focused?))
         ;; 空 + 无焦点 → 占位符
         (when (positive? (string-length placeholder))
           (put-styled-at! y x 'input-normal
                           (if (> (string-length placeholder) w)
                               (substring placeholder 0 w)
                               placeholder)))
         ;; 有内容或聚焦 → 显示文本 + 光标
         (let* ((cw (if (< ci total) (vector-ref ws ci) 1))
                ;; 从光标往回走，填满视口宽度（光标靠右）
                (start
                 (let loop ([i ci] [rem (- w cw)])
                   (if (or (<= i 0) (< rem (vector-ref ws (sub1 i))))
                       i
                       (loop (sub1 i) (- rem (vector-ref ws (sub1 i)))))))
                ;; 从 start 往后走，填满视口
                (end
                 (let loop ([i start] [rem w])
                   (if (or (>= i total) (< rem (vector-ref ws i)))
                       i
                       (loop (add1 i) (- rem (vector-ref ws i))))))
                (visible (list->string
                          (for/list ([i (in-range start end)]) (vector-ref cs i))))
                ;; 光标在视口内的 x 偏移
                (pre-w (for/sum ([i (in-range start ci)]) (vector-ref ws i)))
                (cursor-x (+ x pre-w)))
           (put-styled-at! y x (if focused? 'input-focus 'input-normal) visible)
           (when (and focused? (< pre-w w))
             (define cursor-char (if (< ci total) (string (vector-ref cs ci)) " "))
             (put-styled-at! y cursor-x 'cursor cursor-char)))))

   ;; ── handler ──
   (build-input
    #:char (λ (ch)
             (when (<= 32 ch 126)
               (insert-char! (string (integer->char ch)))))
    #:utf-char insert-char!
    #:backspace backspace!
    #:delete delete!
    #:left  (λ () (when (> (unbox cid) 0)
                    (set-box! cid (sub1 (unbox cid)))
                    (set-box! dirty #t)))
    #:right (λ () (when (< (unbox cid) (vector-length (unbox chars)))
                    (set-box! cid (add1 (unbox cid)))
                    (set-box! dirty #t)))
    #:home (λ () (set-box! cid 0) (set-box! dirty #t))
    #:end  (λ () (set-box! cid (vector-length (unbox chars)))
                (set-box! dirty #t))
    #:enter (λ () (on-submit (text-string)))
    #:escape void
    #:mouse-press (λ (btn mx my mods)
                    (when (eq? btn 'left)
                      (mouse-xy->cid mx my)))
    #:mouse-move (λ (mx my mods)
                   (mouse-xy->cid mx my)))

   #t #t 0 1 dirty #f))
