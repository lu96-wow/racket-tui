#lang racket
;; =============================================================================
;; 输入派发回归测试（无需终端）
;;
;; 验证两件事：
;;   1) 单字节特殊键在通用 char/ctrl 之前的分类顺序
;;      （尤其 0x08 与 0x7F 都必须映射为 'backspace）
;;   2) build-input 的派发顺序：特殊键快捷回调 > #:text > #:key > #:any
;;   3) 每个回调实参的类型符合契约
;;
;; 运行: racket demo/test-input-dispatch.rkt
;; =============================================================================
(require "../main.rkt")

(define failures 0)
(define (check label expected actual)
  (cond [(equal? expected actual) (printf "ok   ~a~n" label)]
        [else (set! failures (add1 failures))
              (printf "FAIL ~a~n  expected: ~s~n  actual:   ~s~n" label expected actual)]))

;; 使用库的真实分类函数 classify-byte，而不是复制一份分类逻辑
;; （ESC 在本测试里按 key 处理；utf8 按 utf8）
(define (raw-type b)
  (case (classify-byte b)
    [(ctrl) 'ctrl]
    [(utf8) 'utf8]
    [else 'key]))

(define (key-of b) (key-event-key (normalize-event (raw-type b) (bytes b) #f)))
(define (mods-of b) (mods->list (key-event-mods (normalize-event (raw-type b) (bytes b) #f))))

;; ── 1) 单字节分类顺序 ──────────────────────────────────────────
(printf "== 单字节特殊键分类 ==~n")
(check "0x08 -> backspace" 'backspace (key-of 8))
(check "0x7f -> backspace" 'backspace (key-of 127))
(check "0x09 -> tab"       'tab       (key-of 9))
(check "0x0a -> enter"     'enter     (key-of 10))
(check "0x0d -> enter"     'enter     (key-of 13))
(check "0x1b -> escape"    'escape    (key-of 27))
(check "0x20 -> #\\space"   #\space    (key-of 32))
(check "0x01 -> #\\A ctrl"  (list #\A '(#t #f #f))
       (list (key-of 1) (mods-of 1)))
(check "0x00 -> #\\space ctrl" (list #\space '(#t #f #f))
       (list (key-of 0) (mods-of 0)))
;; 特殊键必须无修饰（否则 shortcut 无法命中）
(for ([b (list 8 9 10 13 27 127)])
  (check (format "0x~x 无修饰" b) '(#f #f #f) (mods-of b)))

;; ── 2) 派发顺序 ────────────────────────────────────────────────
(printf "~n== build-input 派发顺序 ==~n")
(define hit (box #f))
(define handler
  (build-input
   #:text      (λ (s) (set-box! hit (list 'text s)))
   #:key       (λ (k m) (set-box! hit (list 'key k (mods-ctrl? m) (mods-alt? m))))
   #:space     (λ () (set-box! hit 'space))
   #:tab       (λ () (set-box! hit 'tab))
   #:enter     (λ () (set-box! hit 'enter))
   #:escape    (λ () (set-box! hit 'escape))
   #:backspace (λ () (set-box! hit 'backspace))
   #:delete    (λ () (set-box! hit 'delete))
   #:up        (λ () (set-box! hit 'up))))

(define (dispatch label ev) (set-box! hit #f) (handler ev) (unbox hit))
(define (K b) (normalize-event (raw-type b) (bytes b) #f))

(check "普通 char -> text"        '(text "a")      (dispatch "a" (K 97)))
(check "space -> #:space 优先"    'space            (dispatch " " (K 32)))
(check "tab -> #:tab"             'tab              (dispatch "tab" (K 9)))
(check "enter -> #:enter"         'enter            (dispatch "enter" (K 13)))
(check "escape -> #:escape"       'escape           (dispatch "esc" (K 27)))
(check "backspace(8) -> #:backspace"  'backspace    (dispatch "bs8" (K 8)))
(check "backspace(127) -> #:backspace" 'backspace   (dispatch "bs127" (K 127)))
(check "delete(CSI 3~) -> #:delete"   'delete       (dispatch "del" (normalize-event 'del #"\e[3~" #f)))
(check "up -> #:up"               'up               (dispatch "up" (normalize-event 'up #"\e[A" #f)))
(check "Ctrl+A -> #:key"          '(key #\A #t #f)  (dispatch "C-a" (normalize-event 'ctrl #"\x01" #f)))
(check "Ctrl+Space -> #:key"      '(key #\space #t #f) (dispatch "C-sp" (normalize-event 'ctrl #"\x00" #f)))
(check "Ctrl+Up -> #:key"         '(key up #t #f)   (dispatch "C-up" (normalize-event 'mod-seq #"\e[1;5A" (list #t #f #f))))
(check "Alt+x -> #:key"           '(key #\x #f #t)  (dispatch "A-x" (normalize-event 'alt #"\ex" #f)))

;; ── 3) 回落实参类型 ────────────────────────────────────────────
(printf "~n== 回调实参类型契约 ==~n")
(define type-hit (box #f))
(define th
  (build-input
   #:text   (λ (s) (check "text:string" #t (string? s)) (set-box! type-hit s))
   #:key    (λ (k m) (check "key:key" #t (or (char? k) (symbol? k)))
                      (check "key:mods" #t (mods? m)))
   #:paste  (λ (b) (check "paste:bytes" #t (bytes? b)))
   #:mouse  (λ (a b x y m) (check "mouse:action" #t (symbol? a))
                            (check "mouse:button" #t (or (symbol? b) (not b)))
                            (check "mouse:xy" #t (and (exact-nonnegative-integer? x)
                                                      (exact-nonnegative-integer? y)))
                            (check "mouse:mods" #t (mods? m)))
   #:resize (λ (r c) (check "resize:ints" #t (and (exact-positive-integer? r)
                                                  (exact-positive-integer? c))))
   #:any    (λ (ev) (check "any:event" #t (event? ev)))))
(for ([ev (list (normalize-event 'key #"a" #f)
                (normalize-event 'key #"a" #f)
                (normalize-event 'paste #"p" #f)
                (normalize-event 'mouse (list 'press 'left 1 2 (list #f #f #f)) #f)
                (normalize-event 'resize (cons 24 80) #f)
                (normalize-event 'seq #"\e[99z" #f))])
  (th ev))
(printf "（上方任一 FAIL 即表示契约不符）~n")

;; ── 汇总 ───────────────────────────────────────────────────────
(printf "~n~a~n" (if (zero? failures)
                     "ALL INPUT-DISPATCH TESTS PASSED"
                     (format "~a FAILURE(S)" failures)))
(unless (zero? failures) (exit 1))
