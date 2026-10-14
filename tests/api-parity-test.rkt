#lang racket

;; 后端一致性回归测试：tui 与 tui/char 的公共 API 必须同名同签名，
;; 这样同一份用户代码只改 require 路径即可在两个后端切换。
;;
;; 剩余差异（base 专有：probe-caps / faction / plan-* / read-event*-raw；
;; char 专有：grid / frame / parser / char-input / char-run 调试 API）是
;; 有意的，见 base-char/README.md「与 base 的差异与限制」。

(require rackunit
         racket/set)

;; base 依赖 Linux/Android 的 FFI（termios / signalfd）；其他平台跳过。
;; 注意 (system-type 'os) 在 Linux 上返回 'unix，内核平台要用 'os*。
(define terminal-os? (memq (system-type 'os*) '(linux android)))

(define (exports-of mp)
  (dynamic-require mp #f)
  (define (names lst)
    (for*/list ([phase (in-list lst)] [spec (in-list (cdr phase))]) (car spec)))
  (define-values (vars stx) (module->exports mp))
  (values (names vars) (names stx)))

;; 期望在两个后端都存在的「可移植 API」
(define portable
  '(;; 生命周期 / 会话
    with-tui with-tui-nobuffer with-tui-nobuffer-echo tui-init tui-exit
    tui-init-no-buffer tui-exit-no-buffer
    current-screen-size current-features default-features
    features? features-color features-mouse? features-paste? features-alt-screen?
    features-kitty-keys? features-sync?
    use-color-auto! use-color-from-features! current-key-protocol
    ;; 输出
    put put-byte put-bytes put-format-bytes put-char put-string put-newline put-at put-at!
    ;; 光标
    cursor-up cursor-down cursor-left cursor-right cursor-move cursor-col
    cursor-home cursor-hide cursor-show get-cursor update-cursor!
    current-cursor-row current-cursor-col
    ;; 屏幕 / 行
    screen-clear screen-clear-below screen-clear-above
    line-clear line-clear-right line-clear-left buffer-alt-enable buffer-alt-disable
    ;; 颜色 / 属性
    put-rgb-fg put-rgb-bg put-rgb-fg-bg put-256-fg put-256-bg
    color-fg color-bg color256-fg color256-bg color-rgb-fg color-rgb-bg
    color-fg* color-bg* attr-bold attr-dim attr-italic attr-underline attr-blink attr-reverse
    ;; 样式
    style-define! style-apply! style-reset style->bytes
    put-styled put-styled-at put-styled-at!
    format-styled format-styled-at format-styled-at!
    ;; format-*
    format-screen-clear format-cursor-move format-cursor-up format-cursor-down
    format-cursor-left format-cursor-right format-cursor-col format-cursor-home
    format-cursor-hide format-cursor-show format-screen-clear-below format-screen-clear-above
    format-line-clear format-line-clear-right format-line-clear-left
    format-buffer-alt-enable format-buffer-alt-disable format-reset
    format-rgb-fg format-rgb-bg format-rgb-fg-bg format-256-fg format-256-bg
    ;; 输入 / 事件循环
    read-event read-event-noblock build-input
    loop-input loop-input-noblock loop-input/stop loop-input-noblock/stop
    ;; 事件模型
    mods? no-mods ->mods mods->list
    key-event? paste-event? mouse-event? resize-event? null-event? other-event?
    event? normalize-event byte->key
    event-key? event-mouse? event-paste? event-resize? event-null?
    mouse-x mouse-y get-mouse-pos mouse-modifiers
    get-resize-rows get-resize-cols get-resize-size classify-byte))

;; char 后端应当额外提供、用于无终端调试的 API
(define char-debug
  '(char-frame char-run
    char-input-push! char-input-close! char-input-clear! char-input-remaining
    char-input-empty? char-input-exhausted? char-input-open?
    current-screen the-screen call-with-screen screen-size screen-cursor
    screen-ref cell-text cell-fg cell-bg cell-attrs style->string
    screen-styled-cells screen-attr-ranges screen-style-at screen-current-style
    make-grid grid-ref grid->text grid->lines
    make-ansi-parser ansi-parser-feed-bytes! ansi-parser-grid
    flush! frame-end! frame-reset! current-frame-hook current-frame-dedup?
    screen-frame-log-enable! screen-frame-log-disable! screen-frame-count
    ops-append op op? op-seq? bytes-append))

(module+ test
  (when terminal-os?
    (define-values (b-vars b-stx) (exports-of 'tui))
    (define-values (c-vars c-stx) (exports-of 'tui/char))
    (define b-all (list->set (append b-vars b-stx)))
    (define c-all (list->set (append c-vars c-stx)))

    (test-case "可移植 API 在两个后端都存在"
      (for ([n (in-list portable)])
        (check-true (set-member? b-all n) (format "tui 缺少 ~a" n))
        (check-true (set-member? c-all n) (format "tui/char 缺少 ~a" n))))

    (test-case "公共过程的 arity 一致"
      (for ([n (in-list portable)]
            #:when (and (set-member? b-vars n) (set-member? c-vars n)))
        (define b (dynamic-require 'tui n))
        (define c (dynamic-require 'tui/char n))
        (when (and (procedure? b) (procedure? c))
          (check-equal? (procedure-arity b) (procedure-arity c)
                        (format "arity 不一致: ~a" n)))))

    (test-case "char 调试 API 存在"
      (for ([n (in-list char-debug)])
        (check-true (set-member? c-all n) (format "tui/char 缺少调试 API ~a" n))))

    (test-case "会话参数默认值 / 语义一致"
      (for ([mp (in-list '(tui tui/char))])
        (define css (dynamic-require mp 'current-screen-size))
        (define cf  (dynamic-require mp 'current-features))
        (define ckp (dynamic-require mp 'current-key-protocol))
        (define fcolor (dynamic-require mp 'features-color))
        (check-equal? (css) (cons 24 80) (format "~a 默认尺寸" mp))
        (check-equal? (parameterize ([css (cons 5 9)]) (css)) (cons 5 9)
                      (format "~a 尺寸可 parameterize" mp))
        (check-equal? (fcolor (cf)) '16 (format "~a 默认 color" mp))
        (check-equal? (ckp) 'ansi (format "~a 默认 key protocol" mp))))

    (test-case "use-color-from-features! 返回实际档位"
      (for ([mp (in-list '(tui tui/char))])
        (define pick (dynamic-require mp 'use-color-from-features!))
        (define mk   (dynamic-require mp 'features))
        (check-equal? (pick (mk '256 #f #f #f #f #f)) '256)
        (check-equal? (pick (mk 'truecolor #f #f #f #f #f)) 'truecolor)
        (check-equal? (pick (mk '16 #f #f #f #f #f)) '16)))))
