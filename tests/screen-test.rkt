#lang racket

(require rackunit
         "../base-char/screen/grid.rkt"
         "../base-char/screen/ansi-parse.rkt"
         "../base-char/screen/render.rkt")

;; ── 测试辅助 ─────────────────────────────────────────────

(define (run/bytes bs #:rows [rows 8] #:cols [cols 24])
  (define p (make-ansi-parser rows cols))
  (ansi-parser-feed-bytes! p bs)
  p)

(define (u s) (string->bytes/utf-8 s))

(define (render bs #:rows [rows 8] #:cols [cols 24] #:trim? [trim? #t])
  (grid->text (ansi-parser-grid (run/bytes bs #:rows rows #:cols cols))
              #:trim-right? trim?))

(define (lines bs #:rows [rows 8] #:cols [cols 24])
  (grid->lines (ansi-parser-grid (run/bytes bs #:rows rows #:cols cols))
               #:trim-right? #f))

(module+ test

  (test-case "普通文本 + 绝对定位"
    (check-equal? (lines #"\e[2J\e[1;1Habc" #:rows 4 #:cols 10)
                  '("abc       " "          " "          " "          "))
    (check-equal? (lines #"\e[2J\e[3;5Hxy" #:rows 4 #:cols 10)
                  '("          " "          " "    xy    " "          ")))

  (test-case "相对移动与列定位"
    (check-equal? (render #"\e[2J\e[2;2Habc\e[1A\e[1DX" #:rows 3 #:cols 12)
                  "   X\n abc\n"))

  (test-case "DECSC/DECRC 保存恢复（format-*-at 依赖它）"
    (define p (run/bytes #"\e7\e[5;3Hhi\e8" #:rows 8 #:cols 12))
    (define g (ansi-parser-grid p))
    (check-equal? (cell-text (grid-ref g 4 2)) "h")
    (check-equal? (cell-text (grid-ref g 4 3)) "i")
    (check-equal? (call-with-values (λ () (grid-cursor g)) list) '(0 0)))

  (test-case "RGB / 256 / 16 色"
    (define g (ansi-parser-grid
               (run/bytes #"\e[2J\e[1;1H\e[38;2;255;0;0mX\e[0m\e[38;5;46mG\e[0m\e[31mR"
                          #:rows 3 #:cols 12)))
    (check-equal? (cell-fg (grid-ref g 0 0)) '(rgb 255 0 0))
    (check-equal? (cell-fg (grid-ref g 0 1)) '(idx 46))
    (check-equal? (cell-fg (grid-ref g 0 2)) '(idx 1))
    (check-equal? (cell-fg (grid-ref g 0 3)) #f))

  (test-case "属性累积与 SGR 0 重置"
    (define g (ansi-parser-grid
               (run/bytes #"\e[2J\e[1;1H\e[1;4mB\e[0mN" #:rows 3 #:cols 12)))
    (check-equal? (cell-attrs (grid-ref g 0 0)) '(underline bold))
    (check-equal? (cell-attrs (grid-ref g 0 1)) '())
    (check-equal? (cell-text (grid-ref g 0 1)) "N"))

  (test-case "CR / LF 控制字符"
    (check-equal? (lines #"\e[2Jab\r\ncd" #:rows 4 #:cols 10)
                  '("ab        " "cd        " "          " "          ")))

  (test-case "宽字符占用两列，右半格为 #f"
    (define g (ansi-parser-grid (run/bytes (u "\e[2J\e[1;1H你好") #:rows 3 #:cols 12)))
    (check-equal? (cell-text (grid-ref g 0 0)) "你")
    (check-equal? (cell-text (grid-ref g 0 1)) #f)
    (check-equal? (cell-text (grid-ref g 0 2)) "好")
    (check-equal? (cell-text (grid-ref g 0 3)) #f)
    (check-equal? (call-with-values (λ () (grid-cursor g)) list) '(0 4))
    (check-equal? (render (u "\e[2J\e[1;1H你好") #:rows 3 #:cols 12) "你好\n\n"))

  (test-case "组合记号追加到前一格"
    (define g (ansi-parser-grid
               (run/bytes (string->bytes/utf-8 "\e[2J\e[1;1He\u0301")
                          #:rows 3 #:cols 12)))
    (check-equal? (cell-text (grid-ref g 0 0)) "e\u0301")
    (check-equal? (call-with-values (λ () (grid-cursor g)) list) '(0 1)))

  (test-case "行擦除 / 屏幕擦除"
    (check-equal? (render #"\e[2Jabcdef\e[1;1H\e[K" #:rows 3 #:cols 12) "\n\n")
    (check-equal? (render #"\e[2Jabc\e[2;1Hdef\e[1;1H\e[0J" #:rows 3 #:cols 12) "\n\n")
    (check-equal? (lines #"\e[2Jabc\e[1;2H\e[K" #:rows 3 #:cols 12)
                  (list (string-append "a" (make-string 11 #\space))
                        (make-string 12 #\space)
                        (make-string 12 #\space))))

  (test-case "备用缓冲切换"
    (define p (run/bytes #"\e[2J\e[?1049h\e[2JALT\e[?1049l" #:rows 4 #:cols 10))
    (check-equal? (grid->text (ansi-parser-grid p)) "\n\n\n")   ; 主缓冲为空
    (check-equal? (grid->text (parser-alt p)) "ALT\n\n\n"))

  (test-case "未识别序列记入 diag 而不丢内容"
    (define p (run/bytes #"\e[2J\e[1;1H\e[99;99zok" #:rows 3 #:cols 10))
    (check-equal? (grid->text (ansi-parser-grid p)) "ok\n\n")
    (check-true (pair? (ansi-parser-diag p))))

  (test-case "分片 fuzz：任意切割点结果一致"
    (define sample
      (u "\e[2J\e[1;1H\e[38;5;46mhello\e[0m\e[3;2H\e[1mworld\e[0m\e[1A\e[2C你"))
    (define expected (lines sample #:rows 6 #:cols 20))
    (for ([i (in-range 0 (add1 (bytes-length sample)))])
      (define p (make-ansi-parser 6 20))
      (ansi-parser-feed-bytes! p (subbytes sample 0 i))
      (ansi-parser-feed-bytes! p (subbytes sample i))
      (check-equal? (grid->lines (ansi-parser-grid p) #:trim-right? #f)
                    expected
                    (format "split at ~a" i))))

  (test-case "按需属性查询"
    (define g (ansi-parser-grid
               (run/bytes #"\e[2J\e[1;1H\e[31mA\e[0mB" #:rows 3 #:cols 8)))
    (check-equal? (style->string (grid-ref g 0 0)) "fg#1")
    (check-equal? (style->string (grid-ref g 0 1)) "")
    (check-not-false (member '(0 0 "A" "fg#1") (screen-styled-cells g)))))
