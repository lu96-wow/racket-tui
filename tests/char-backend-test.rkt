#lang racket

;; char 后端测试
;;  1. bytes-append 确实被覆盖成 ops-append
;;  2. 同一段 UI：op 路径（base-char）与 ANSI 解析路径（base-char/screen/ansi-parse）
;;     渲染出的字符图完全一致 —— 用独立实现互为对照

(require rackunit
         (rename-in racket/base [bytes-append raw-bytes-append])
         (prefix-in b: "../base/ansi/ansi-format.rkt")
         (prefix-in be: "../base/io/event.rkt")
         "../char.rkt")

(define (op-path thunk #:rows [rows 8] #:cols [cols 24])
  (parameterize ([current-screen-size (cons rows cols)])
    (with-tui (λ () (thunk) (char-frame)))))

(define (parse-path bs #:rows [rows 8] #:cols [cols 24])
  (define p (make-ansi-parser rows cols))
  (ansi-parser-feed-bytes! p bs)
  (grid->text (ansi-parser-grid p)))

(module+ test

  (test-case "bytes-append 被 base-char 覆盖为 op 拼接"
    (check-true (op-seq? (bytes-append format-screen-clear)))
    (check-true (op-seq? (bytes-append format-screen-clear (format-cursor-move 1 1) "hi")))
    (check-equal? (length (bytes-append format-reset format-reset)) 2))

  (test-case "op 路径与 ANSI 解析路径一致"
    (define op-text
      (op-path
       (λ ()
         (screen-clear)
         (put-at 3 5 "hi")
         (put-rgb-fg 255 0 0 "R")
         (put-256-fg 46 "G")
         (put-bold)
         (put-string "B")
         (put-reset)
         (cursor-move 5 2)
         (put-string "end"))
       #:rows 8 #:cols 24))

    (define ansi-bytes
      (raw-bytes-append
       b:format-screen-clear
       (b:format-cursor-move 1 1)          ; 对齐 screen-clear 的归位
       (b:format-content-at 3 5 "hi")
       (b:format-rgb-fg 255 0 0 "R")
       (b:format-256-fg 46 "G")
       b:format-bold #"B" b:format-reset
       (b:format-cursor-move 5 2) #"end"))

    (check-equal? op-text (parse-path ansi-bytes #:rows 8 #:cols 24)))

  (test-case "宽度 / 宽字符两路径一致"
    (define op-text
      (op-path
       (λ () (screen-clear) (put-at 1 1 "a你b好c"))
       #:rows 4 #:cols 16))
    (define ansi-bytes
      (raw-bytes-append
       b:format-screen-clear
       (b:format-content-at 1 1 (string->bytes/utf-8 "a你b好c"))))
    (check-equal? op-text (parse-path ansi-bytes #:rows 4 #:cols 16)))

  (test-case "消隐/擦除两路径一致"
    (define op-text
      (op-path
       (λ ()
         (screen-clear)
         (put-at 1 1 "abcdef")
         (cursor-move 1 3)
         (line-clear-right))
       #:rows 4 #:cols 12))
    (define ansi-bytes
      (raw-bytes-append
       b:format-screen-clear (b:format-cursor-move 1 1)
       (b:format-content-at 1 1 "abcdef")
       (b:format-cursor-move 1 3) b:format-line-clear-right))
    (check-equal? op-text (parse-path ansi-bytes #:rows 4 #:cols 12)))

  (test-case "归一化行为与 base 一致（防漂移）"
    ;; char 与 base 的事件结构体类型不同，比较语义摘要
    (define (char-sum ev)
      (cond [(key-event? ev) (list 'key (key-event-key ev) (mods->list (key-event-mods ev)))]
            [(null-event? ev) '(null)]
            [(resize-event? ev) (list 'resize (resize-event-rows ev) (resize-event-cols ev))]
            [(mouse-event? ev) (list 'mouse (mouse-event-action ev) (mouse-event-button ev)
                                     (mouse-event-x ev) (mouse-event-y ev))]
            [(paste-event? ev) (list 'paste (paste-event-bytes ev) (paste-event-text ev))]
            [else (list 'other)]))
    (define (base-sum ev)
      (cond [(be:key-event? ev) (list 'key (be:key-event-key ev) (be:mods->list (be:key-event-mods ev)))]
            [(be:null-event? ev) '(null)]
            [(be:resize-event? ev) (list 'resize (be:resize-event-rows ev) (be:resize-event-cols ev))]
            [(be:mouse-event? ev) (list 'mouse (be:mouse-event-action ev) (be:mouse-event-button ev)
                                        (be:mouse-event-x ev) (be:mouse-event-y ev))]
            [(be:paste-event? ev) (list 'paste (be:paste-event-bytes ev) (be:paste-event-text ev))]
            [else (list 'other)]))
    (define cases
      (list '(null #f #f)
            '(resize (10 . 20) #f)
            '(key #"a" #f)
            '(key #"\r" #f)
            '(key #"\x7f" #f)
            '(ctrl #"\x01" #f)
            '(alt #"\x1bb" #f)
            '(up #f #f)
            '(home #f #f)
            '(mod-seq #"\x1b[1;5A" #f)
            '(mod-seq #"\x1b[3;5~" #f)
            '(utf8 #"\xe4\xbd\xa0" #f)
            '(paste #"hi" #f)
            '(mouse (press left 3 4 #f) #f)))
    (for ([c cases])
      (check-equal? (char-sum (apply normalize-event c))
                    (base-sum (apply be:normalize-event c))
                    (format "case ~a" c))))

  (test-case "鼠标 raw 形状 → mouse-event（move / scroll 防回归）"
    ;; raw 形状由 input.rkt 的 parse-mouse-event 决定：
    ;;   press/release : (action button x y mods)
    ;;   move          : (move   button x y mods)
    ;;   scroll        : (scroll scroll dir x y mods)
    (for ([d (list 'up 'down)])
      (define ev (normalize-event 'mouse (list 'scroll 'scroll d 3 4 #f) #f))
      (check-true (mouse-event? ev))
      (check-equal? (mouse-event-action ev) 'scroll)
      (check-equal? (mouse-event-button ev) d)
      (check-equal? (list (mouse-event-x ev) (mouse-event-y ev)) '(3 4)))
    (define mev (normalize-event 'mouse (list 'move #f 3 4 #f) #f))
    (check-true (mouse-event? mev))
    (check-equal? (mouse-event-action mev) 'move)
    (check-equal? (list (mouse-event-x mev) (mouse-event-y mev)) '(3 4))
    ;; base 后端同样
    (define bev (be:normalize-event 'mouse (list 'scroll 'scroll 'down 3 4 #f) #f))
    (check-true (be:mouse-event? bev))
    (check-equal? (be:mouse-event-button bev) 'down)
    (define bmv (be:normalize-event 'mouse (list 'move #f 3 4 #f) #f))
    (check-true (be:mouse-event? bmv))
    (check-equal? (be:mouse-event-action bmv) 'move))

  (test-case "随机操作对拍：op 路径 vs ANSI 解析路径（300 步）"
    (define rows 8)
    (define cols 16)
    ;; 自写 LCG，保证两边消费完全相同的操作序列
    (define seed (box 12345))
    (define (rnd n)
      (set-box! seed (modulo (+ (* 1103515245 (unbox seed)) 12345) 2147483648))
      (modulo (quotient (unbox seed) 65536) n))
    (define (ch) (integer->char (+ 65 (rnd 26))))
    (define (str) (list->string (for/list ([i (rnd 4)]) (if (zero? (rnd 6)) #\你 (ch)))))
    (define (rand-desc)
      (case (rnd 16)
        [(0) (list 'move (rnd 9) (rnd 17))]
        [(1) (list 'text (str))]
        [(2) (list 'fg (rnd 256) (rnd 256) (rnd 256) (str))]
        [(3) (list 'c256 (rnd 256) (str))]
        [(4) (list 'at (rnd 9) (rnd 17) (str))]
        [(5) (list 'at! (rnd 9) (rnd 17) (str))]
        [(6) (list 'bold (str))]
        [(7) (list 'clear)]
        [(8) (list 'eline (rnd 3))]
        [(9) (list 'eclear (rnd 3))]
        [(10) (list 'relup (rnd 3))]
        [(11) (list 'reldown (rnd 3))]
        [(12) (list 'col (rnd 17))]
        [(13) (list 'save-or-restore (rnd 2))]
        [(14) (list 'home)]
        [(15) (list 'alt (rnd 2))]))
    (define (desc->char d)
      (match d
        [(list 'move r c) (format-cursor-move r c)]
        [(list 'text s) s]
        [(list 'fg r g b s) (format-rgb-fg r g b s)]
        [(list 'c256 n s) (format-256-fg n s)]
        [(list 'at r c s) (format-content-at r c s)]
        [(list 'at! r c s) (format-content-at! r c s)]
        [(list 'bold s) (ops-append format-bold s format-reset)]
        [(list 'clear) format-screen-clear]
        [(list 'eline m) (case m [(0) format-line-clear-right]
                                 [(1) format-line-clear-left]
                                 [(2) format-line-clear])]
        [(list 'eclear m) (case m [(0) format-screen-clear-below]
                                  [(1) format-screen-clear-above]
                                  [(2) format-screen-clear])]
        [(list 'relup n) (format-cursor-up n)]
        [(list 'reldown n) (format-cursor-down n)]
        [(list 'col n) (format-cursor-col n)]
        [(list 'save-or-restore k) (if (zero? k) format-cursor-save format-cursor-restore)]
        [(list 'home) format-cursor-home]
        [(list 'alt k) (if (zero? k) format-buffer-alt-enable format-buffer-alt-disable)]))
    (define (desc->base d)
      (match d
        [(list 'move r c) (b:format-cursor-move r c)]
        [(list 'text s) (string->bytes/utf-8 s)]
        [(list 'fg r g b s) (b:format-rgb-fg r g b s)]
        [(list 'c256 n s) (b:format-256-fg n s)]
        [(list 'at r c s) (b:format-content-at r c s)]
        [(list 'at! r c s) (b:format-content-at! r c s)]
        [(list 'bold s) (raw-bytes-append b:format-bold (string->bytes/utf-8 s) b:format-reset)]
        [(list 'clear) b:format-screen-clear]
        [(list 'eline m) (case m [(0) b:format-line-clear-right]
                                 [(1) b:format-line-clear-left]
                                 [(2) b:format-line-clear])]
        [(list 'eclear m) (case m [(0) b:format-screen-clear-below]
                                  [(1) b:format-screen-clear-above]
                                  [(2) b:format-screen-clear])]
        [(list 'relup n) (b:format-cursor-up n)]
        [(list 'reldown n) (b:format-cursor-down n)]
        [(list 'col n) (b:format-cursor-col n)]
        [(list 'save-or-restore k) (if (zero? k) b:format-cursor-save b:format-cursor-restore)]
        [(list 'home) b:format-cursor-home]
        [(list 'alt k) (if (zero? k) b:format-buffer-alt-enable b:format-buffer-alt-disable)]))
    (define descs (for/list ([i 300]) (rand-desc)))
    (define cg (parameterize ([current-screen-size (cons rows cols)])
                 (with-tui (λ () (for ([d descs]) (emit (desc->char d))) (the-screen)))))
    (define p (make-ansi-parser rows cols))
    (for ([d descs]) (ansi-parser-feed-bytes! p (desc->base d)))
    (define pg (ansi-parser-grid p))
    (check-equal? (grid->text cg #:trim-right? #f) (grid->text pg #:trim-right? #f))
    (check-equal? (screen-styled-cells cg) (screen-styled-cells pg)))

  (test-case "样式系统写入 grid（按需属性）"
    (define cells
      (parameterize ([current-screen-size (cons 6 16)])
        (with-tui
         (λ ()
           (screen-clear)
           (put-at 1 1 "X")
           (put-styled-at 2 1 'error "E")
           (screen-styled-cells (the-screen))))))
    (check-not-false (member '(0 0 "X" "") cells))
    (define e (findf (λ (c) (equal? (cadr c) 0)) (filter (λ (c) (equal? (car c) 1)) cells)))
    (check-true (and e (string-contains? (cadddr e) "fg#1"))))

  (test-case "备用缓冲：alt 期间不破坏主屏（= base ESC[?1049h/l）"
    (define frames
      (parameterize ([current-screen-size (cons 3 10)])
        (with-tui
         (λ ()
           (screen-clear)
           (put-string "MAIN")
           (define before (char-frame))
           (buffer-alt-enable)          ; 切到 alt（清空）
           (check-true (screen-alt-active?))
           (define in-alt (char-frame))
           (put-string "ALT")
           (define alt-drawn (char-frame))
           (buffer-alt-disable)         ; 切回主屏
           (define after (char-frame))
           (list before in-alt alt-drawn after)))))
    (check-equal? (list-ref frames 0) "MAIN\n\n")
    (check-equal? (list-ref frames 1) "\n\n")
    (check-equal? (list-ref frames 2) "ALT\n\n")
    (check-equal? (list-ref frames 3) "MAIN\n\n")   ; 主屏内容恢复
    (check-false (screen-alt-active?))
    ;; 停在 alt 时直接退出 with-tui，也应像 base 的 tui-exit 一样恢复主屏
    (parameterize ([current-screen-size (cons 3 10)])
      (with-tui
       (λ ()
         (screen-clear)
         (put-string "MAIN")
         (buffer-alt-enable)
         (put-string "ALT"))))
    (check-false (screen-alt-active?))
    (check-equal? (char-frame) "MAIN\n\n")))
