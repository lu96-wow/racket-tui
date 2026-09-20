#lang racket

;; 增量 ANSI / UTF-8 解析器
;;
;; 目标：把 base 项目产生的字节流（put-* / format-* 的输出）解释成一个
;; 字符网格。之所以用字节而不是语义 op，是因为 README 主推的用法是
;;   (bytes-append format-screen-clear (format-cursor-move ...) ...) → put-bytes
;; 要保持接口完全一致，就只能解释同一份字节协议。
;;
;; 支持的序列是本库实际会产出的子集：
;;   CSI H/f 绝对定位      CSI A/B/C/D 相对移动     CSI G 列定位   CSI d 行定位
;;   CSI J 屏幕擦除        CSI K 行擦除
;;   CSI m SGR（16 色 / 256 色 / RGB / 属性）
;;   CSI ?25h/l 光标显隐   CSI ?1049h/l 备用缓冲
;;   CSI s/u 光标保存恢复  CSI r 滚动区域
;;   ESC 7/8 (DECSC/DECRC)  ESC c (RIS)
;;   控制字符 CR / LF / BS / TAB / BEL
;; 其余序列忽略并记入 diag，不静默丢内容（会记录原始 final byte）。

(require "grid.rkt"
         "width.rkt"
         "sgr.rkt")

(provide (struct-out parser)
         make-ansi-parser
         ansi-parser-feed-bytes!
         ansi-parser-feed-string!
         ansi-parser-grid
         ansi-parser-diag
         ansi-parser-diag-clear!
         ansi-parser-alt?)

;; 解析状态机：
;;   ground → esc → csi / osc
;;   utf8 用于跨 chunk 的多字节 UTF-8
(struct parser
  (main alt grid                             ; 主/备缓冲 + 当前激活
   state                                     ; 'ground 'esc 'csi 'osc 'osc-esc 'utf8
   params cur cur-seen?                      ; CSI 参数（前向 list + 当前累加）
   private intermediate                      ; CSI 私有标记 / 中间字节
   utf8-acc utf8-need
   diag)                                     ; 未识别序列（逆序 list）
  #:mutable #:transparent)

(define (make-ansi-parser rows cols)
  (define main (make-grid rows cols))
  (define alt (make-grid rows cols))
  (parser main alt main
          'ground
          '() #f #f
          #f #f
          0 0
          '()))

(define (ansi-parser-alt? p) (eq? (parser-grid p) (parser-alt p)))

(define (ansi-parser-grid p) (parser-grid p))
(define (ansi-parser-diag p) (parser-diag p))

(define (note-diag! p what)
  (set-parser-diag! p (cons what (parser-diag p))))

(define (ansi-parser-diag-clear! p)
  (set-parser-diag! p '()))

;; ── 入口 ─────────────────────────────────────────────────

(define (ansi-parser-feed-bytes! p bs)
  (for ([b (in-bytes bs)])
    (feed-byte! p b)))

(define (ansi-parser-feed-string! p s)
  (ansi-parser-feed-bytes! p (string->bytes/utf-8 s)))

;; ── 字节层：UTF-8 解码 ───────────────────────────────────

(define (feed-byte! p b)
  (cond
    [(eq? (parser-state p) 'utf8) (utf8-continue! p b)]
    [(< b #x80) (feed-char! p (integer->char b))]
    [(<= #xc2 b #xdf) (utf8-start! p 1 (bitwise-and b #x1f))]
    [(<= #xe0 b #xef) (utf8-start! p 2 (bitwise-and b #x0f))]
    [(<= #xf0 b #xf4) (utf8-start! p 3 (bitwise-and b #x07))]
    [else (feed-char! p #\uFFFD)]))

(define (utf8-start! p need acc)
  (set-parser-state! p 'utf8)
  (set-parser-utf8-need! p need)
  (set-parser-utf8-acc! p acc))

(define (utf8-continue! p b)
  (cond
    [(<= #x80 b #xbf)
     (define acc (bitwise-ior (arithmetic-shift (parser-utf8-acc p) 6)
                              (bitwise-and b #x3f)))
     (define need (- (parser-utf8-need p) 1))
     (set-parser-utf8-acc! p acc)
     (set-parser-utf8-need! p need)
     (when (zero? need)
       (set-parser-state! p 'ground)
       (feed-char! p (integer->char acc)))]
    [else
     ;; 非法续字节：吐一个替换字符，然后按新字节重新处理
     (set-parser-state! p 'ground)
     (feed-char! p #\uFFFD)
     (feed-byte! p b)]))

;; ── 字符层：状态派发 ─────────────────────────────────────

(define (feed-char! p ch)
  (case (parser-state p)
    [(ground) (ground-char! p ch (char->integer ch))]
    [(esc)    (esc-char! p ch (char->integer ch))]
    [(csi)    (csi-char! p ch (char->integer ch))]
    [(osc)    (osc-char! p ch)]
    [(osc-esc) (if (char=? ch #\\) 
                   (set-parser-state! p 'ground)
                   (set-parser-state! p 'osc))]
    [else (void)]))

(define (ground-char! p ch code)
  (define g (parser-grid p))
  (cond
    [(= code 27) (set-parser-state! p 'esc)]
    [(= code 13) (grid-carriage-return! g)]
    [(= code 10) (grid-index! g)]
    [(= code 8)  (grid-backspace! g)]
    [(= code 9)  (grid-tab! g)]
    [(or (< code 32) (= code 127)) (void)]
    [else (grid-put-char! g ch)]))

(define (esc-char! p ch code)
  (case code
    [(91) (reset-csi! p) (set-parser-state! p 'csi)]         ; [
    [(93) (set-parser-state! p 'osc)]                        ; ] OSC
    [(80 88 94 95) (set-parser-state! p 'osc)]               ; DCS/SOS/PM/APC，整体跳过
    [(55) (grid-save! (parser-grid p)) (set-parser-state! p 'ground)]     ; 7 DECSC
    [(56) (grid-restore! (parser-grid p)) (set-parser-state! p 'ground)]  ; 8 DECRC
    [(99) (grid-clear! (parser-grid p)) (set-parser-state! p 'ground)]    ; c RIS
    [(68) (grid-index! (parser-grid p)) (set-parser-state! p 'ground)]    ; D IND
    [(69) (grid-carriage-return! (parser-grid p))
          (grid-index! (parser-grid p)) (set-parser-state! p 'ground)]    ; E NEL
    [(77) (grid-reverse-index! (parser-grid p)) (set-parser-state! p 'ground)] ; M RI
    [else (set-parser-state! p 'ground)]))

;; OSC：忽略内容，遇到 BEL 或 ST 结束
(define (osc-char! p ch)
  (cond
    [(char=? ch #\u0007) (set-parser-state! p 'ground)]
    [(char=? ch #\u001b) (set-parser-state! p 'osc-esc)]
    [else (void)]))

;; ── CSI 参数收集 ─────────────────────────────────────────

(define (reset-csi! p)
  (set-parser-params! p '())
  (set-parser-cur! p #f)
  (set-parser-cur-seen?! p #f)
  (set-parser-private! p #f)
  (set-parser-intermediate! p #f))

(define (param-digit! p d)
  (set-parser-cur! p (+ (* (or (parser-cur p) 0) 10) d))
  (set-parser-cur-seen?! p #t))

(define (param-push! p)
  (set-parser-params! p
                      (append (parser-params p)
                              (list (if (parser-cur-seen? p) (parser-cur p) #f))))
  (set-parser-cur! p #f)
  (set-parser-cur-seen?! p #f))

(define (csi-char! p ch code)
  (cond
    [(<= 48 code 57) (param-digit! p (- code 48))]
    [(or (= code 59) (= code 58)) (param-push! p)]        ; ; 与 : 都当参数分隔
    [(= code 63) (set-parser-private! p #\?)]             ; ?
    [(or (= code 60) (= code 61) (= code 62)) (set-parser-private! p ch)] ; < = >
    [(<= 32 code 47) (set-parser-intermediate! p ch)]
    [(<= 64 code 126) (finish-csi! p ch)
                      (set-parser-state! p 'ground)]
    [else (void)]))

(define (finish-csi! p final)
  (define ps (if (parser-cur-seen? p)
                 (append (parser-params p) (list (parser-cur p)))
                 (parser-params p)))
  (define g (parser-grid p))
  (case final
    [(#\H #\f) (grid-move! g (sub1 (max 1 (pget ps 0 1)))
                           (sub1 (max 1 (pget ps 1 1))))]
    [(#\A) (grid-move-rel! g (- (max 1 (pget ps 0 1))) 0)]
    [(#\B) (grid-move-rel! g (max 1 (pget ps 0 1)) 0)]
    [(#\C) (grid-move-rel! g 0 (max 1 (pget ps 0 1)))]
    [(#\D) (grid-move-rel! g 0 (- (max 1 (pget ps 0 1))))]
    [(#\E) (grid-move! g (+ (grid-cursor-row g) (max 1 (pget ps 0 1))) 0)]
    [(#\F) (grid-move! g (- (grid-cursor-row g) (max 1 (pget ps 0 1))) 0)]
    [(#\G) (grid-move! g (grid-cursor-row g) (sub1 (max 1 (pget ps 0 1))))]
    [(#\d) (grid-move! g (sub1 (max 1 (pget ps 0 1))) (grid-cursor-col g))]
    [(#\J) (grid-erase-display! g (or (pget ps 0 0) 0))]
    [(#\K) (grid-erase-line! g (or (pget ps 0 0) 0))]
    [(#\m) (apply-sgr! g ps)]
    [(#\h) (when (eqv? (parser-private p) #\?) (set-modes! p ps #t))]
    [(#\l) (when (eqv? (parser-private p) #\?) (set-modes! p ps #f))]
    [(#\s) (grid-save! g)]
    [(#\u) (grid-restore! g)]
    [(#\r) (grid-set-scroll-region! g
                                     (sub1 (max 1 (pget ps 0 1)))
                                     (sub1 (max 1 (pget ps 1 (grid-rows g)))))]
    [(#\n) (void)]                          ; DSR 属于输入方向，忽略
    [else (note-diag! p (list 'csi (parser-private p) ps final))]))

(define (pget ps i default)
  (define v (and (< i (length ps)) (list-ref ps i)))
  (if v v default))

;; ── 私有模式 ─────────────────────────────────────────────

(define (set-modes! p ps on?)
  (for ([v ps])
    (case (or v 0)
      [(25) (set-grid-cursor-visible?! (parser-grid p) on?)]
      [(47 1047 1049)
       (if on?
           (begin (set-parser-grid! p (parser-alt p))
                  (grid-clear! (parser-alt p)))
           (set-parser-grid! p (parser-main p)))]
      [else (void)])))

;; SGR 处理见 sgr.rkt（与 op 路径共用）
