#lang racket

;; ════════════════════════════════════════════════════════════════
;; tests/terminal-support-test.rkt
;;
;; terminal-support 的单元测试：不依赖 tty，用"假回复"喂给内存端口。
;;   raco test tests/terminal-support-test.rkt
;; ════════════════════════════════════════════════════════════════

(require rackunit
         racket/port
         racket/list
         "../terminal-support/main.rkt")

;; ── 工具（模块级，供 test 子模块用）──
(define E (string (integer->char 27)))
(define (B s) (string->bytes/latin-1 s))
(define (j . xs) (apply string-append xs))

(define (with-replies replies thunk)
  (parameterize ([current-input-port (open-input-bytes (B replies))]
                 [current-output-port (open-output-nowhere)])
    (thunk)))

;; 组一张表 → 跑 → 组装（纯组合）
(define (caps-from replies
                   #:groups [gs '(identity xtgettcap kitty colors sizes
                                  cursor mouse paste screen focus sync keyboard)]
                   #:env [env (hash)])
  (with-replies replies
    (λ ()
      (define qs (group->queries gs))
      (check-query-ids qs)
      (define-values (raw res) (run-queries/raw qs #:timeout 0.02 #:idle 0.005))
      (assemble-caps res raw #:env env))))

(module+ test

  ;; ══════════════════════════════════════════════════════════════
  ;; 1. 请求构造（精确字节）
  ;; ══════════════════════════════════════════════════════════════
  (check-equal? (da1-request) #"\e[c" "DA1 请求")
  (check-equal? (da2-request) #"\e[>c" "DA2 请求")
  (check-equal? (da3-request) #"\e[=c" "DA3 请求")
  (check-equal? (xtversion-request) #"\e[>0q" "XTVERSION 请求")
  (check-equal? (dsr-request) #"\e[6n" "DSR 请求")
  (check-equal? (kitty-flags-request) #"\e[?u" "kitty 请求")
  (check-equal? (xtmodkeys-request) #"\e[?4m" "modifyOtherKeys 请求")
  (check-equal? (decrqm-private-request 1006) #"\e[?1006$p" "DECRQM 私有请求")
  (check-equal? (decrqm-ansi-request 4) #"\e[4$p" "DECRQM ANSI 请求")
  (check-equal? (osc-color-request 10) #"\e]10;?\e\\" "OSC 颜色请求")
  (check-equal? (osc-palette-request 1) #"\e]4;1;?\e\\" "OSC 调色板请求")
  (check-equal? (text-area-size-request) #"\e[18t" "XTWINOPS 18t")
  (check-equal? (xtgettcap-request '("TN")) #"\eP+q544E\e\\" "XTGETTCAP 请求")
  (check-equal? (kitty-graphics-request) #"\e_Gi=31,s=1,v=1,a=q,t=d,f=24;AAAA\e\\" "kitty 图形请求")

  ;; ══════════════════════════════════════════════════════════════
  ;; 2. 解析
  ;; ══════════════════════════════════════════════════════════════
  (check-equal? (parse-da1 (B (j E "[?61;1;22c"))) '((61 1 22)) "parse-da1")
  (check-equal? (parse-da2 (B (j E "[>0;276;0c"))) '((0 276 0)) "parse-da2")
  (check-equal? (parse-da3 (B (j E "P!|7E565445" E "\\"))) "7E565445" "parse-da3")
  (check-equal? (parse-xtversion (B (j E "P>|VTE(8001)" E "\\"))) "VTE(8001)" "parse-xtversion")
  (check-equal? (parse-dsr (B (j E "[8;1R"))) (list (cons 8 1)) "parse-dsr")
  (check-equal? (parse-kitty-flags (B (j E "[?0u"))) '(0) "parse-kitty-flags")
  (check-equal? (parse-xtmodkeys (B (j E "[>4;2m"))) 2 "parse-xtmodkeys")
  (check-equal? (parse-decrqm-private (B (j E "[?1006;2$y" E "[?2026;4$y")))
                (list (cons 1006 2) (cons 2026 4)) "parse-decrqm-private")
  (check-equal? (parse-decrqm-ansi (B (j E "[4;2$y"))) (list (cons 4 2)) "parse-decrqm-ansi")
  (check-equal? (parse-xtgettcap (B (j E "P1+r544E=565445" E "\\" E "P0+r524742" E "\\")))
                (list (list "TN" #t "VTE") (list "RGB" #f #f)) "parse-xtgettcap")
  (check-equal? (parse-osc (B (j E "]10;rgb:cccc/cccc/cccc" E "\\")))
                '("10;rgb:cccc/cccc/cccc") "parse-osc")
  (check-equal? (parse-window-reports (B (j E "[8;24;80t" E "[4;480;640t" E "[6;17;8t")))
                (hash 8 (cons 24 80) 4 (cons 480 640) 6 (cons 17 8)) "parse-window-reports")
  (check-true (kitty-graphics-reply? (B (j E "_Gi=31;OK" E "\\"))) "kitty 图形：OK 回复")
  (check-true (kitty-graphics-reply? (B (j E "_Gi=31;EINVAL:bad" E "\\"))) "kitty 图形：错误回复也算支持")
  (check-false (kitty-graphics-reply? (B (j E "_Gi=31,s=1,v=1,a=q,t=d,f=24;AAAA" E "\\"))) "kitty 图形：我们自己的查询不算回复")

  ;; ══════════════════════════════════════════════════════════════
  ;; 3. 取值函数
  ;; ══════════════════════════════════════════════════════════════
  (check-equal? (decrqm-private-pm (B (j E "[?1006;2$y")) 1006) 2 "decrqm-private-pm")
  (check-equal? (decrqm-private-pm (B (j E "[?1006;2$y")) 9999) #f "decrqm-private-pm 缺项")
  (check-equal? (decrqm-ansi-pm (B (j E "[20;2$y")) 20) 2 "decrqm-ansi-pm")
  (check-equal? (osc-value (B (j E "]10;rgb:cccc/cccc/cccc" E "\\")) 10) "rgb:cccc/cccc/cccc" "osc-value")
  (check-equal? (osc-palette-value (B (j E "]4;5;rgb:aaaa/0000/bbbb" E "\\")) 5) "rgb:aaaa/0000/bbbb" "osc-palette-value")
  (check-equal? (window-size (B (j E "[8;24;80t")) 8) (cons 24 80) "window-size")
  (check-equal? (xtgettcap-lookup (B (j E "P1+r544E=565445" E "\\")) "TN") "VTE" "xtgettcap-lookup")
  (check-equal? (cursor-position (B (j E "[9;2R"))) (cons 9 2) "cursor-position")
  (check-equal? (kitty-flags-value (B (j E "[?3u"))) 3 "kitty-flags-value")
  (check-equal? (parse-color-string "rgb:cccc/cccc/cccc") '(204 204 204) "parse-color-string: rgb:")
  (check-equal? (parse-color-string "#0a141e") '(10 20 30) "parse-color-string: #rrggbb")
  (check-equal? (parse-color-string "garbage") #f "parse-color-string: 非法 -> #f")
  (check-equal? (bytes->hex (string->bytes/utf-8 "TN")) "544E" "bytes->hex")
  (check-equal? (hex->bytes "544E") (string->bytes/utf-8 "TN") "hex->bytes")
  (check-equal? (call-with-values (λ () (split-name-version "xterm.js(6.1)")) list)
                '("xterm.js" "6.1") "split-name-version")
  (check-equal? (vis-string (string-append (string (integer->char 27)) "[9m")) "^[[9m" "vis-string: ESC")
  (check-equal? (vis-string (string (integer->char 7))) "^G" "vis-string: BEL")
  (check-equal? (vis-string "abc") "abc" "vis-string: 明文")

  ;; ══════════════════════════════════════════════════════════════
  ;; 3.5 健壮性 / 错误处理（不因坏回复抛异常；坏输入明确报错）
  ;; ══════════════════════════════════════════════════════════════
  (check-equal? (parse-xtgettcap (B (j E "P1+rG" E "\\"))) '() "XTGETTCAP: 非 hex 体被跳过")
  (check-equal? (parse-xtgettcap (B (j E "P1+rABC" E "\\"))) '() "XTGETTCAP: 奇数长度 hex 被跳过")
  (check-equal? (hex->bytes "ABC") #f "hex->bytes: 奇数长度 -> #f")
  (check-equal? (hex->bytes "GG") #f "hex->bytes: 非 hex -> #f")
  (check-equal? (xtgettcap-lookup (B (j E "P1+r544E" E "\\")) "TN") #t
                "xtgettcap-lookup: 命中但无值 -> #t")
  (check-equal? (xtgettcap-lookup (B (j E "P0+r544E" E "\\")) "TN") #f
                "xtgettcap-lookup: 0+r（未找到）-> #f")
  (check-exn exn? (λ () (group->queries '(identityy))) "未知组名报错")
  (check-exn exn? (λ () (xtgettcap-request '())) "空 XTGETTCAP 名单报错")
  (check-false (caps-mux (caps-from (j E "[>c"))) "空 DA2 参数不崩溃")
  (check-equal? (caps-color-level (caps-from (j E "[?1;2c") #:env (hash "COLORTERM" "TrueColor")))
                'truecolor "COLORTERM 大小写不敏感")

  ;; ══════════════════════════════════════════════════════════════
  ;; 4. 组装 + 访问
  ;; ══════════════════════════════════════════════════════════════
  (define fake
    (j E "P>|xterm.js(6.1)" E "\\"
       E "[?1000;2$y" E "[?1002;2$y" E "[?1006;2$y" E "[?2004;2$y"
       E "[?2026;4$y" E "[?8;3$y" E "[?67;4$y" E "[4;2$y" E "[20;3$y"
       E "]10;rgb:cccc/cccc/cccc" E "\\" E "]4;5;rgb:aaaa/0000/bbbb" E "\\"
       E "[8;24;80t" E "[9;1R" E "[?0u" E "[>4;2m"
       E "[>0;276;0c" E "[?1;2c"))
  (define c (caps-from fake #:groups '(identity xtgettcap kitty colors sizes
                                                 cursor mouse paste screen focus sync
                                                 keyboard misc output)))

  (check-equal? (caps-id c) "xterm.js(6.1)" "身份 = XTVERSION")
  (check-equal? (caps-id-source c) 'xtversion "身份来源")
  (check-equal? (caps-name c) "xterm.js" "name")
  (check-equal? (caps-da1 c) '((1 2)) "da1 原始")
  (check-equal? (caps-da1-model c) "VT100" "DA1 型号")
  (check-equal? (caps-da1-attrs c) '() "DA1 属性：VT100 系 ?1;2 不拆出能力码")
  (check-equal? (caps-da2-model c) "VT100" "DA2 型号")
  (check-equal? (caps-text-size c) (cons 24 80) "文本区")
  (check-equal? (caps-cursor c) (cons 9 1) "光标")
  (check-equal? (caps-kitty-flags c) 0 "kitty flags")
  (check-equal? (caps-xtmodkeys c) 2 "modifyOtherKeys")

  (check-equal? (caps-mode-pm c 1006) 2 "1006 Pm")
  (check-equal? (caps-mode-state c 1006) 'reset "1006 状态")
  (check-true (caps-mode-available? c 1006) "1006 可用")
  (check-true (caps-mode-settable? c 1006) "1006 可设")
  (check-false (caps-mode-on? c 1006) "1006 未置位")
  (check-equal? (caps-mode-state c 2026) 'permanently-reset "2026 永久复位")
  (check-false (caps-mode-available? c 2026) "2026 不可用")
  (check-equal? (caps-mode-state c 8) 'permanently-set "8 永久置位")
  (check-true (caps-mode-on? c 8) "8 视为开")
  (check-true (caps-mode-available? c 8) "8 永久置位=可用")
  (check-equal? (caps-mode-state c 67) 'permanently-reset "67 永久复位")
  (check-equal? (caps-mode-state c 20 #t) 'permanently-set "ANSI 20 永久置位")
  (check-equal? (caps-mode-pm c 999) #f "未查模式 -> #f")
  (check-equal? (caps-mode-name 1006) "鼠标: SGR" "模式名")
  (check-equal? (caps-color c 10) "rgb:cccc/cccc/cccc" "OSC 前景")
  (check-equal? (caps-palette-color c 5) "rgb:aaaa/0000/bbbb" "调色板")
  (check-equal? (caps-color-rgb c 10) '(204 204 204) "色 RGB（rgb:cccc → 204）")
  (check-equal? (caps-palette-color-rgb c 5) '(170 0 187) "调色板 RGB（rgb:aaaa/0000/bbbb）")
  (check-equal? (caps-color-rgb (caps-from (j E "]10;#0a141e" E "\\")) 10) '(10 20 30) "色 RGB（#rrggbb）")
  (check-equal? (caps-color-rgb c 99) #f "色 RGB：无该项 → #f")
  (check-true (caps-osc-rgb? c) "osc-rgb?")
  (check-equal? (caps-truecolor c) 'unknown "真彩：无 XTGETTCAP -> unknown")

  (check-equal? (caps-da1-attrs (caps-from (j E "[?61;1;21;22;28c")))
                '("132 columns" "horizontal scrolling" "ANSI color" "rectangular editing")
                "DA1 属性：VT2xx+ 拆出能力码")

  (check-true (hash? (caps->hash c)) "caps->hash")
  (check-equal? (hash-ref (caps->hash c) 'id) "xterm.js(6.1)" "caps->hash id")

  ;; ══════════════════════════════════════════════════════════════
  ;; 5. 真彩三态
  ;; ══════════════════════════════════════════════════════════════
  (check-equal? (caps-truecolor (caps-from (j E "P1+r524742" E "\\" E "[?1;2c"))) #t "真彩：RGB 找到")
  (check-equal? (caps-truecolor (caps-from (j E "P0+r524742" E "\\" E "[?1;2c"))) #f "真彩：RGB 未找到")
  (check-equal? (caps-truecolor (caps-from (j E "[?1;2c"))) 'unknown "真彩：无 XTGETTCAP")
  (check-equal? (caps-colors-count (caps-from (j E "P1+r436F=323536" E "\\" E "[?1;2c"))) 256 "色数 Co=256")

  ;; 色深（caps-color-level）：把多个来源揉成一个确定符号
  (check-equal? (caps-color-level c) 'unknown "色深：无来源 → unknown")
  (check-equal? (caps-color-level (caps-from (j E "P1+r524742" E "\\" E "[?1;2c"))) 'truecolor "色深：XTGETTCAP RGB → truecolor")
  (check-equal? (caps-color-level (caps-from (j E "P1+r436F=323536" E "\\" E "[?1;2c"))) '256 "色深：Co=256 → 256")
  (check-equal? (caps-color-level (caps-from (j E "[?1;2c") #:env (hash "COLORTERM" "truecolor"))) 'truecolor "色深：COLORTERM=truecolor")
  (check-equal? (caps-color-level (caps-from (j E "[?1;2c") #:env (hash "COLORTERM" "yes"))) '256 "色深：COLORTERM 其他值 → 256")
  (check-equal? (caps-color-level (caps-from (j E "[?1;2c") #:env (hash "TERM" "xterm-256color"))) '256 "色深：TERM=...256color")
  (check-equal? (caps-color-level (caps-from (j E "[?61;1;22c"))) '16 "色深：DA1 ANSI color → 16")

  ;; 环境事实：多路复用器 / SSH
  (check-equal? (caps-mux (caps-from (j E "[?1;2c") #:env (hash "TMUX" "/tmp/tmux-1000/default,1,0"))) 'tmux "mux: TMUX")
  (check-equal? (caps-mux (caps-from (j E "[?1;2c") #:env (hash "STY" "12345.pts-0.host"))) 'screen "mux: STY")
  (check-equal? (caps-mux (caps-from (j E "[?1;2c") #:env (hash "ZELLIJ" "0"))) 'zellij "mux: ZELLIJ")
  (check-equal? (caps-mux (caps-from (j E "[?1;2c") #:env (hash "TERM" "screen-256color"))) 'screen "mux: TERM screen-*")
  (check-equal? (caps-mux (caps-from (j E "[?1;2c") #:env (hash "TERM" "tmux-256color"))) 'tmux "mux: TERM tmux-*")
  (check-equal? (caps-mux (caps-from (j E "[>84;0;0c"))) 'tmux "mux: DA2 Pp=84")
  (check-false (caps-mux? (caps-from (j E "[?1;2c"))) "mux: 无 → #f")
  (check-true (caps-ssh? (caps-from (j E "[?1;2c") #:env (hash "SSH_TTY" "/dev/pts/0"))) "ssh?：SSH_TTY")
  (check-false (caps-ssh? (caps-from (j E "[?1;2c"))) "ssh?：无 → #f")

  ;; ══════════════════════════════════════════════════════════════
  ;; 6. 表 / profile 不变量
  ;; ══════════════════════════════════════════════════════════════
  (check-equal? (length (group-private-modes (profile-groups 'full))) 82 "full 覆盖 82 私有模式")
  (check-equal? (length (group-ansi-modes (profile-groups 'full))) 6 "full 覆盖 6 ANSI 模式")
  (check-equal? (length (group-private-modes (profile-groups 'standard))) 24 "standard 24")
  (check-equal? (length (group-private-modes (profile-groups 'minimal))) 4 "minimal 4")
  (check-not-exn (λ () (check-query-ids (default-queries))) "default-queries id 唯一")
  (check-not-exn (λ () (check-query-ids (profile->queries 'full))) "full id 唯一")
  (check-exn exn? (λ () (check-query-ids (list (decrqm-private-query 1) (decrqm-private-query 1))))
             "重复 id 报错")
  (check-equal? (length (kitty-queries #f)) 2 "kitty-queries 默认 2 条")
  (check-equal? (length (kitty-queries #t)) 3 "kitty-queries 含图形 3 条")
  (check-true (for/or ([q (in-list (kitty-queries #t))]) (eq? (query-id q) 'kitty-graphics))
              "kitty-queries #t 含 kitty-graphics")

  ;; ══════════════════════════════════════════════════════════════
  ;; 7. 端到端：定查哪些 → 查 → hash → 组装句柄（无便捷入口，纯组合）
  ;; ══════════════════════════════════════════════════════════════
  (define c2 (with-replies fake
               (λ ()
                 (define-values (raw res) (run-queries/raw (default-queries)
                                                           #:timeout 0.02 #:idle 0.005))
                 (assemble-caps res raw #:env (hash)))))
  (check-equal? (caps-id c2) "xterm.js(6.1)" "端到端：default-queries → run-queries → assemble-caps"))
