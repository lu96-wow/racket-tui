#lang racket

;; ═══════════════════════════════════════════════════════════════════════════
;; Input 组件 — 两层架构
;;
;; Layer 1 (gap-buffer.rkt): 数据 + 编辑 + 查询 — 纯逻辑，零渲染依赖
;; Layer 2 (本模块):         渲染 + 滚动 + 事件绑定 — 只读 buffer，写屏幕
;;
;; 核心原则:
;;   1. 编辑操作只改 buffer, 设置 dirty 标记, 绝不碰滚动/渲染
;;   2. 渲染只读 buffer, 计算滚动确保光标始终可见, 写屏幕
;;   3. 滚动偏移由渲染统一计算, 编辑后自动修正
;;   4. 水平滚动"惰性": 只有光标贴边时才移
;;
;; ═══════════════════════════════════════════════════════════════════════════
;; 渲染边界情况:
;;
;;  R01. 空缓冲区 + 聚焦 → 显示光标在 (x, y)
;;  R02. 空缓冲区 + 无焦点 → 显示 placeholder
;;  R03. 光标在换行符上 → 显示高亮空格
;;  R04. 光标在行尾 (total-len) → 显示高亮空格
;;  R05. 行长 > 视口宽 → 水平滚动, 光标贴边触发
;;  R06. 行数 > 视口高 → 垂直滚动, 光标出界触发
;;  R07. 输入换行符 (多行模式) → 光标下移, 必要时滚动
;;  R08. CJK 宽字符在视口边缘 → 正确裁剪, 不显示半字符
;;  R09. 视口尺寸变化 → 重新计算滚动
;;  R10. 光标始终在视口内 → 渲染保证 scroll-y ≤ cursor-line < scroll-y + h
;;     且 scroll-x ≤ cursor-col < scroll-x + w (cursor-width 预留)
;;
;; ═══════════════════════════════════════════════════════════════════════════

(require "../component.rkt"
         "../../base/gap-buffer.rkt"
         "../../base/io/build-input.rkt"
         "../../base/io/output-styles.rkt"
         "../../base/io/output-color.rkt"
         "../../base/io/output.rkt")

(provide make-input)

(define (make-input #:placeholder [placeholder ""]
                    #:on-submit   [on-submit void]
                    #:on-change   [on-change void]
                    #:multiline?  [multiline? #f]
                    #:initial-text [initial-text ""])

  ;; ═══════════════════════════════════════════════════════
  ;; 状态 (Layer 1: buffer / Layer 2: 渲染上下文)
  ;; ═══════════════════════════════════════════════════════

  ;; ── Layer 1: 纯数据 ──
  (define buf   (box (make-gap-buffer initial-text)))
  (define dirty (box #t))

  ;; ── Layer 2: 渲染上下文 (由 render 读写, 编辑操作不碰) ──
  (define scroll-y (box 0))
  (define scroll-x (box 0))
  (define vp-x (box 0)) (define vp-y (box 0))
  (define vp-w (box 0)) (define vp-h (box 0))

  ;; ═══════════════════════════════════════════════════════
  ;; Layer 1: 编辑操作 — 只改 buffer, 设置 dirty
  ;; ═══════════════════════════════════════════════════════

  (define (edit! thunk)
    (thunk)
    (set-box! dirty #t)
    (on-change (buffer-text (unbox buf))))

  (define (do-insert str)
    (define norm (regexp-replace* #rx"\r\n|\r" str "\n"))
    (define filtered (if multiline? norm (string-replace norm "\n" "")))
    (unless (equal? filtered "")
      (edit! (λ () (buffer-insert! (unbox buf) filtered)))))

  (define (do-backspace)
    (when (> (buffer-cursor-pos (unbox buf)) 0)
      (edit! (λ () (buffer-backspace! (unbox buf))))))

  (define (do-delete)
    (define b (unbox buf))
    (when (< (buffer-cursor-pos b) (buffer-total-len b))
      (edit! (λ () (buffer-delete! b)))))

  (define (do-move-left)
    (define b (unbox buf))
    (when (> (buffer-cursor-pos b) 0)
      (buffer-move-left b)
      (set-box! dirty #t)))

  (define (do-move-right)
    (define b (unbox buf))
    (when (< (buffer-cursor-pos b) (buffer-total-len b))
      (buffer-move-right b)
      (set-box! dirty #t)))

  (define (do-move-up)
    (when multiline?
      (define b (unbox buf))
      (when (> (buffer-cursor-line b) 0)
        (buffer-move-up b)
        (set-box! dirty #t))))

  (define (do-move-down)
    (when multiline?
      (define b (unbox buf))
      (when (< (add1 (buffer-cursor-line b)) (buffer-line-count b))
        (buffer-move-down b)
        (set-box! dirty #t))))

  (define (do-move-home)
    (define b (unbox buf))
    (define ls (buffer-line-start b (buffer-cursor-line b)))
    (unless (= (buffer-cursor-pos b) ls)
      (buffer-move-home b)
      (set-box! dirty #t)))

  (define (do-move-end)
    (define b (unbox buf))
    (buffer-move-end b)
    (set-box! dirty #t))

  ;; ── 鼠标 → 光标 ──
  (define (mouse->cursor mx my)
    (define b (unbox buf))
    (define sy (unbox scroll-y))
    (define sx (unbox scroll-x))
    (define li (+ sy (- my (unbox vp-y))))
    (define n  (buffer-line-count b))
    (define tl (buffer-total-len b))

    (define pos
      (cond
        [(< li 0) 0]
        [(>= li n) tl]
        [else
         (define lstart (buffer-line-start b li))
         (define lend   (buffer-line-end b li))
         ;; 鼠标相对视口的 display-width 列
         (define rx (- mx (unbox vp-x)))
         ;; 将 display-width 列 + 当前水平滚动 → 目标 display-width 列
         (define target-col (+ sx rx))
         ;; 在当前行找最接近的位置
         (let loop ([p lstart] [col 0])
           (cond
             [(>= p lend) p]
             [(>= col target-col) p]
             [else (loop (add1 p) (+ col (buffer-char-display-width-at b p)))]))]))

    (when (not (= pos (buffer-cursor-pos b)))
      (buffer-move-to b pos)
      (set-box! dirty #t)))

  ;; ═══════════════════════════════════════════════════════
  ;; Layer 2: 滚动计算 — 确保光标始终在视口内
  ;; ═══════════════════════════════════════════════════════

  (define (compute-scroll! b focused? w h)
    (define tl   (buffer-total-len b))
    (define li   (buffer-cursor-line b))
    (define n    (buffer-line-count b))
    (define lstart (buffer-line-start b li))
    (define lend   (buffer-line-end b li))

    ;; ── 垂直滚动 ──
    ;; 保证: scroll-y ≤ li < scroll-y + h
    (define old-sy (unbox scroll-y))
    (define max-sy (max 0 (- n h)))
    (define new-sy
      (cond
        [(< li old-sy)       li]                    ; 光标在视口上方
        [(>= li (+ old-sy h)) (add1 (- li h))]     ; 光标在视口下方
        [(> old-sy max-sy)   max-sy]               ; 缓冲区缩小后 clamp
        [else old-sy]))
    (unless (= new-sy old-sy)
      (set-box! scroll-y new-sy))

    ;; ── 水平滚动 (仅光标所在行) ──
    ;; 保证: scroll-x ≤ cursor-col < scroll-x + w, 且光标有 1 格余量
    (define old-sx (unbox scroll-x))
    (define new-sx
      (cond
        [(zero? tl) 0]  ;; 空缓冲区

        ;; 计算当前行的总 display-width
        [else
         (define line-width
           (let loop ([p lstart] [lw 0])
             (if (>= p lend) lw
                 (loop (add1 p) (+ lw (buffer-char-display-width-at b p))))))

         ;; 光标 display-width 列及宽度
         (define cur-col (buffer-cursor-display-col b))
         (define cur-w
           (if (and (< (buffer-cursor-pos b) tl)
                    (not (char=? (buffer-char-at b (buffer-cursor-pos b)) #\newline)))
               (buffer-char-display-width-at b (buffer-cursor-pos b))
               1))  ;; 换行符或末尾 → 宽度为 1 的空格

         (define cur-end (+ cur-col cur-w))

         (cond
           ;; 行宽小于视口 → 不滚动
           [(<= line-width w) 0]

           ;; 光标左侧贴边 → 滚动到光标左侧
           [(< cur-col old-sx)
            (max 0 cur-col)]

           ;; 光标右侧贴边 → 滚动使光标完整可见 (预留 1 格)
           [(> cur-end (+ old-sx w -1))
            (max 0 (min cur-col (- cur-end w)))]

           ;; 无贴边 → 保持; 但若光标实际已超出旧 sx (缓冲区扩大后) → clamp
           [(> old-sx cur-col)
            (max 0 cur-col)]

           [else old-sx])]))

    (unless (= new-sx old-sx)
      (set-box! scroll-x new-sx)))

  ;; ═══════════════════════════════════════════════════════
  ;; Layer 2: 渲染 — 只读 buffer, 写屏幕
  ;; ═══════════════════════════════════════════════════════

  (define (render focused? x y w h)
    ;; 保存视口参数
    (set-box! vp-x x) (set-box! vp-y y)
    (set-box! vp-w w) (set-box! vp-h h)

    (define b      (unbox buf))
    (define tl     (buffer-total-len b))
    (define n      (buffer-line-count b))
    (define cur-li (buffer-cursor-line b))
    (define cur-pos (buffer-cursor-pos b))

    ;; ── 1. 计算滚动 (确保光标可见) ──
    (compute-scroll! b focused? w h)
    (define sy (unbox scroll-y))
    (define sx (unbox scroll-x))

    ;; ── 2. 渲染: 空/非空分两路, 避免 placeholder 被覆盖 ──
    (cond
      ;; 空 + 无焦点 + placeholder → 仅显示 placeholder
      [(and (zero? tl) (not focused?)
            (positive? (string-length placeholder)))
       (for ([sr (in-range h)])
         (cursor-move (+ y sr) x)
         (put-string (make-string w #\space)))
       (define disp (if (> (string-length placeholder) w)
                        (substring placeholder 0 w) placeholder))
       (put-styled-at! y x 'input-normal disp)]

      ;; 空 + 聚焦 → 仅显示光标
      [(zero? tl)
       (for ([sr (in-range h)])
         (cursor-move (+ y sr) x)
         (put-string (make-string w #\space)))
       (when focused?
         (put-styled-at! y x 'cursor " "))]

      ;; 有内容: 清空 + 逐行渲染
      [else
       (for ([sr (in-range h)])
         (cursor-move (+ y sr) x)
         (put-string (make-string w #\space)))

       (for ([sr (in-range h)])
         (define li (+ sy sr))
         (when (< li n)
           (define line-start (buffer-line-start b li))
           (define line-end   (buffer-line-end b li))
           (define is-cur-line (= li cur-li))

           (define line-str
             (call-with-output-string
              (λ (out)
                (let loop ([p line-start] [col 0])
                  (when (< p line-end)
                    (define cw (buffer-char-display-width-at b p))
                    (define cr (+ col cw))
                    (cond
                      [(<= cr sx)  (loop (add1 p) cr)]
                      [(>= col (+ sx w)) (void)]
                      [else
                       (define display-ch
                         (if (char=? (buffer-char-at b p) #\newline)
                             #\space
                             (buffer-char-at b p)))
                       (write-char display-ch out)
                       (loop (add1 p) cr)]))))))

           (define style (if focused? 'input-focus 'input-normal))
           (put-styled-at! (+ y sr) x style line-str)

           ;; ── 光标 ──
           (when (and focused? is-cur-line)
             (define cur-col-x (buffer-cursor-display-col b))
             (define sx-cur (- cur-col-x sx))
             (when (and (>= sx-cur 0) (< sx-cur w))
               (define cch
                 (if (and (< cur-pos tl)
                          (not (char=? (buffer-char-at b cur-pos) #\newline)))
                     (string (buffer-char-at b cur-pos))
                     " "))
               (put-styled-at! (+ y sr) (+ x sx-cur) 'cursor cch)))))]))

  ;; ═══════════════════════════════════════════════════════
  ;; 事件绑定
  ;; ═══════════════════════════════════════════════════════

  (define handler
    (if multiline?
        (build-input
         #:char       (λ (ch) (when (<= 32 ch 126) (do-insert (string (integer->char ch)))))
         #:utf-char   do-insert
         #:backspace  do-backspace
         #:delete     do-delete
         #:left       do-move-left
         #:right      do-move-right
         #:up         do-move-up
         #:down       do-move-down
         #:home       do-move-home
         #:end        do-move-end
         #:enter      (λ () (on-submit (buffer-text (unbox buf))))
         #:escape     (λ () (do-insert "\n"))
         #:paste      (λ (data) (do-insert (bytes->string/utf-8 data)))
         #:mouse-press (λ (btn mx my mods) (when (eq? btn 'left) (mouse->cursor mx my)))
         #:mouse-move  (λ (mx my mods) (mouse->cursor mx my)))
        (build-input
         #:char       (λ (ch) (when (<= 32 ch 126) (do-insert (string (integer->char ch)))))
         #:utf-char   do-insert
         #:backspace  do-backspace
         #:delete     do-delete
         #:left       do-move-left
         #:right      do-move-right
         #:up         void
         #:down       void
         #:home       do-move-home
         #:end        do-move-end
         #:enter      (λ () (on-submit (buffer-text (unbox buf))))
         #:escape     void
         #:paste      (λ (data) (do-insert (bytes->string/utf-8 data)))
         #:mouse-press (λ (btn mx my mods) (when (eq? btn 'left) (mouse->cursor mx my)))
         #:mouse-move  (λ (mx my mods) (mouse->cursor mx my)))))

  ;; ═══════════════════════════════════════════════════════
  ;; 组件封装
  ;; ═══════════════════════════════════════════════════════

  (component render handler #t #t 0 1 dirty #f))
