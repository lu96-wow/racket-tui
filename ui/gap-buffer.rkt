#lang racket

;; ═══════════════════════════════════════════════════════════════════════════
;; Gap Buffer — 纯文本缓冲区（零渲染依赖）
;;
;; 物理布局: [left...][gap...][right...]
;;   光标位置 = gap-start（插入点）
;;   逻辑布局: 字符在 [0, total-len) 内连续
;;
;; 两层架构:
;;   Layer 1 (本模块): 数据 + 编辑操作 + 查询 → 纯逻辑，无终端/渲染概念
;;   Layer 2 (input.rkt): 渲染 + 滚动 + 事件绑定 → 只读 buffer，写屏幕
;;
;; ═══════════════════════════════════════════════════════════════════════════
;; 边界情况全集 (Edge Cases)
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; ── 插入 ──
;;  E01. 空缓冲区插入任意字符串 → 正常
;;  E02. 光标在 buffer 末尾插入 → gap 已在末尾，直接写入
;;  E03. gap 空间不足 → 自动 2x 扩容，内容完整保留
;;  E04. 插入空字符串 "" → no-op（无副作用）
;;  E05. 插入换行符 \n → 写入换行符，行索引失效
;;
;; ── 删除 ──
;;  E06. 光标在位置 0 → backspace no-op
;;  E07. 光标在 total-len → delete no-op
;;  E08. 空缓冲区 backspace/delete → no-op
;;  E09. backspace 删除换行符 → 两行合并，行索引失效
;;  E10. delete 删除换行符（光标在换行符上）→ 两行合并
;;  E11. 连续 backspace 删光内容 → 回到空缓冲区状态
;;
;; ── 光标水平移动 ──
;;  E12. left 在位置 0 → no-op，pref-col 不变
;;  E13. right 在 total-len → no-op，pref-col 不变
;;  E14. left/right 正常移动 → pref-col 更新为移动后的 display-width 列
;;  E15. 跨越宽字符 (CJK/emoji) 左右移动 → 每次移动 1 个逻辑位置
;;
;; ── 光标垂直移动 (pref-col 记忆) ──
;;  E16. up 在第一行 → no-op（pref-col 不变）
;;  E17. down 在最后一行 → no-op（pref-col 不变）
;;  E18. 从长行上移到短行 → 光标夹紧到短行末尾，pref-col 保持长行的值
;;  E19. 从短行继续上移 → pref-col 不变，逐行夹紧
;;  E20. 从被夹紧的行下移回长行 → 恢复到 pref-col（列记忆恢复）
;;  E21. 空行 (仅 \n) 上移/下移 → 光标到换行符位置
;;  E22. 空缓冲区 up/down → no-op
;;
;; ── Home / End ──
;;  E23. Home → 移到行首（该行第一个字符位置），pref-col = 0
;;  E24. End → 移到行尾（换行符位置；最后一行则是 total-len），pref-col 更新
;;  E25. 空行 Home/End → 都移到换行符位置（行首=行尾）
;;  E26. 空缓冲区 Home/End → no-op
;;
;; ── move-to (鼠标定位) ──
;;  E27. pos < 0 → clamp 到 0，pref-col 更新
;;  E28. pos > total-len → clamp 到 total-len，pref-col 更新
;;  E29. pos 在宽字符中间 → 停在字符开始位置（当前实现: pos 为单位，上层保证）
;;
;; ── 行查询 ──
;;  E30. 空缓冲区 → line-count = 1, start = 0, end = 0
;;  E31. 单行 "hello" → line-count = 1, range [0, 5)
;;  E32. "ab\ncd\n" → line-count = 3, last-line range [5, 6) (仅换行符)
;;  E33. "ab\ncd" → line-count = 2, last-line range [3, 5) (无尾随换行)
;;  E34. 光标在 \n 上 → cursor-col 可能等于该行的 char-count
;;
;; ═══════════════════════════════════════════════════════════════════════════

(provide make-gap-buffer
         ;; 编辑操作
         buffer-insert! buffer-backspace! buffer-delete!
         ;; 光标移动
         buffer-move-left buffer-move-right
         buffer-move-up buffer-move-down
         buffer-move-home buffer-move-end
         buffer-move-to
         ;; 查询
         buffer-cursor-pos buffer-total-len
         buffer-text buffer-empty?
         buffer-char-at buffer-char-display-width-at
         ;; 行查询
         buffer-line-count buffer-line-start buffer-line-end
         buffer-cursor-line buffer-cursor-col buffer-cursor-display-col
         ;; 工具
         char-display-width)

;; ═══════════════════════════════════════════════════════════
;; 字符显示宽度
;; ═══════════════════════════════════════════════════════════

(define (char-display-width ch)
  (define cp (char->integer ch))
  (cond [(<= #x1100 cp #x115F) 2] [(<= #x2329 cp #x232A) 2]
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

;; ═══════════════════════════════════════════════════════════
;; Gap Buffer 结构体
;; ═══════════════════════════════════════════════════════════

(struct gap-buf
  (chars          ; vector[capacity] — 字符存储
   widths         ; vector[capacity] — 预计算的显示宽度
   gap-start      ; natural — 光标位置 = 插入点
   gap-end        ; natural — gap 右边界
   total-len      ; natural — 有效字符数
   capacity       ; natural — 物理容量
   lines          ; (listof natural) — 行起始位置（惰性计算）
   lines-valid?   ; boolean — 行缓存有效性
   pref-col       ; (or/c #f natural) — 垂直移动记忆列（display-width 单位）
   )
  #:mutable)

(define (make-gap-buffer [initial-text ""])
  (define cap 256)
  (define buf (gap-buf (make-vector cap #\nul) (make-vector cap 0) 0 cap 0 cap '(0) #t #f))
  (unless (equal? initial-text "")
    (buffer-insert! buf initial-text)
    ;; 光标移到位置 0（move-to 正确搬运物理数据 + 更新 pref-col）
    (buffer-move-to buf 0))
  buf)

;; ═══════════════════════════════════════════════════════════
;; 内部：物理 ↔ 逻辑坐标
;; ═══════════════════════════════════════════════════════════

(define (logic->phys buf pos)
  (if (< pos (gap-buf-gap-start buf))
      pos
      (+ pos (- (gap-buf-gap-end buf) (gap-buf-gap-start buf)))))

(define (phys-ref-char buf phys)   (vector-ref (gap-buf-chars buf) phys))
(define (phys-ref-width buf phys)  (vector-ref (gap-buf-widths buf) phys))

;; ═══════════════════════════════════════════════════════════
;; 内部：gap 扩容
;; ═══════════════════════════════════════════════════════════

(define (ensure-gap! buf need)
  (when (< (- (gap-buf-gap-end buf) (gap-buf-gap-start buf)) need)
    (define old-cap (gap-buf-capacity buf))
    (define new-cap (* 2 (+ old-cap need)))
    (define nc (make-vector new-cap #\nul))
    (define nw (make-vector new-cap 0))
    (define gs (gap-buf-gap-start buf))
    (define ge (gap-buf-gap-end buf))
    (define cs (gap-buf-chars buf))
    (define ws (gap-buf-widths buf))
    (vector-copy! nc 0 cs 0 gs)
    (vector-copy! nw 0 ws 0 gs)
    (vector-copy! nc (+ gs need) cs ge old-cap)
    (vector-copy! nw (+ gs need) ws ge old-cap)
    (set-gap-buf-chars! buf nc)
    (set-gap-buf-widths! buf nw)
    (set-gap-buf-gap-end! buf (+ gs need))
    (set-gap-buf-capacity! buf new-cap)))

;; ═══════════════════════════════════════════════════════════
;; 内部：移动 gap 到指定逻辑位置
;; ═══════════════════════════════════════════════════════════

(define (move-gap! buf pos)
  (define gs (gap-buf-gap-start buf))
  (define ge (gap-buf-gap-end buf))
  (when (not (= pos gs))
    (define cs (gap-buf-chars buf))
    (define ws (gap-buf-widths buf))
    (cond
      [(< pos gs)
       (define n (- gs pos))
       (vector-copy! cs (- ge n) cs pos gs)
       (vector-copy! ws (- ge n) ws pos gs)
       (set-gap-buf-gap-start! buf pos)
       (set-gap-buf-gap-end! buf (- ge n))]
      [else
       (define n (- pos gs))
       (vector-copy! cs gs cs ge (+ ge n))
       (vector-copy! ws gs ws ge (+ ge n))
       (set-gap-buf-gap-start! buf (+ gs n))
       (set-gap-buf-gap-end! buf (+ ge n))])))

;; ═══════════════════════════════════════════════════════════
;; 内部：行缓存
;; ═══════════════════════════════════════════════════════════

(define (invalidate-lines! buf)
  (set-gap-buf-lines-valid?! buf #f))

(define (rebuild-lines buf)
  (define tl (gap-buf-total-len buf))
  (define gs (gap-buf-gap-start buf))
  (define ge (gap-buf-gap-end buf))
  (define cs (gap-buf-chars buf))
  (let loop ([lp 0] [start 0] [acc '()])
    (cond
      [(>= lp tl) (reverse (cons start acc))]
      [(char=? (if (< lp gs)
                   (vector-ref cs lp)
                   (vector-ref cs (+ lp (- ge gs))))
               #\newline)
       (loop (add1 lp) (add1 lp) (cons start acc))]
      [else (loop (add1 lp) start acc)])))

(define (get-lines buf)
  (unless (gap-buf-lines-valid? buf)
    (set-gap-buf-lines! buf (rebuild-lines buf))
    (set-gap-buf-lines-valid?! buf #t))
  (gap-buf-lines buf))

;; ═══════════════════════════════════════════════════════════
;; 内部：通过 display-width 列找逻辑位置
;; 在 [line-start, line-end) 范围内，找到最接近 target-col 的位置
;; line-end 是 exclusive，且不越过换行符
;; ═══════════════════════════════════════════════════════════

(define (find-pos-by-display-col buf line-start line-end target-col)
  ;; line-end 是 exclusive。非最后一行时 line-end = 下一行起始，
  ;; 光标不应越过换行符进入下一行。
  (define tl (gap-buf-total-len buf))
  (define max-pos (if (< line-end tl) (sub1 line-end) line-end))
  (let loop ([pos line-start] [col 0])
    (cond
      [(>= pos max-pos) max-pos]
      [(>= col target-col) pos]
      [else (loop (add1 pos) (+ col (buffer-char-display-width-at buf pos)))])))

;; ═══════════════════════════════════════════════════════════
;; 内部：计算当前位置的 display-width 列
;; ═══════════════════════════════════════════════════════════

(define (compute-display-col buf line-start cursor-pos)
  (let loop ([p line-start] [col 0])
    (if (>= p cursor-pos)
        col
        (loop (add1 p) (+ col (buffer-char-display-width-at buf p))))))

;; ═══════════════════════════════════════════════════════════
;; 公开 API：编辑操作
;; ═══════════════════════════════════════════════════════════

(define (buffer-insert! buf str)
  ;; E04: 空字符串 → no-op
  (unless (equal? str "")
    (define chars-list
      (for/list ([ch (in-string str)])
        (cons ch (char-display-width ch))))
    (define n (length chars-list))
    (ensure-gap! buf n)
    (define gs (gap-buf-gap-start buf))
    (define cs (gap-buf-chars buf))
    (define ws (gap-buf-widths buf))
    (for ([pair (in-list chars-list)] [i (in-naturals)])
      (vector-set! cs (+ gs i) (car pair))
      (vector-set! ws (+ gs i) (cdr pair)))
    (set-gap-buf-gap-start! buf (+ gs n))
    (set-gap-buf-total-len! buf (+ (gap-buf-total-len buf) n))
    ;; 行已变，先失效再重建，更新 pref-col
    (invalidate-lines! buf)
    (define ls (get-lines buf))
    (define li (pos->line ls (gap-buf-gap-start buf)))
    (set-gap-buf-pref-col! buf
      (compute-display-col buf (list-ref ls li) (gap-buf-gap-start buf)))))

(define (buffer-backspace! buf)
  ;; E06, E08: 光标在 0 则 no-op
  ;; 仅递减 gap-start，gap 向左生长 1，吸收左侧字符
  (when (> (gap-buf-gap-start buf) 0)
    (set-gap-buf-gap-start! buf (sub1 (gap-buf-gap-start buf)))
    (set-gap-buf-total-len! buf (sub1 (gap-buf-total-len buf)))
    (invalidate-lines! buf)
    ;; 更新 pref-col
    (define ls (get-lines buf))
    (define li (pos->line ls (gap-buf-gap-start buf)))
    (set-gap-buf-pref-col! buf
      (compute-display-col buf (list-ref ls li) (gap-buf-gap-start buf)))))

(define (buffer-delete! buf)
  ;; E07, E08: 光标在末尾则 no-op
  ;; 仅递增 gap-end，gap 向右生长 1，吸收右侧字符
  (when (< (gap-buf-gap-start buf) (gap-buf-total-len buf))
    (set-gap-buf-gap-end! buf (add1 (gap-buf-gap-end buf)))
    (set-gap-buf-total-len! buf (sub1 (gap-buf-total-len buf)))
    (invalidate-lines! buf)))

;; ═══════════════════════════════════════════════════════════
;; 公开 API：光标移动
;; ═══════════════════════════════════════════════════════════

(define (buffer-move-left buf)
  ;; E12: 位置 0 → no-op
  (when (> (gap-buf-gap-start buf) 0)
    (move-gap! buf (sub1 (gap-buf-gap-start buf)))
    ;; E14: 更新 pref-col
    (define ls (get-lines buf))
    (define li (pos->line ls (gap-buf-gap-start buf)))
    (set-gap-buf-pref-col! buf
      (compute-display-col buf (list-ref ls li) (gap-buf-gap-start buf)))))

(define (buffer-move-right buf)
  ;; E13: 末尾 → no-op
  (when (< (gap-buf-gap-start buf) (gap-buf-total-len buf))
    (move-gap! buf (add1 (gap-buf-gap-start buf)))
    ;; E14: 更新 pref-col
    (define ls (get-lines buf))
    (define li (pos->line ls (gap-buf-gap-start buf)))
    (set-gap-buf-pref-col! buf
      (compute-display-col buf (list-ref ls li) (gap-buf-gap-start buf)))))

(define (buffer-move-up buf)
  ;; E16, E22: 第一行或空缓冲区 → no-op
  (define ls (get-lines buf))
  (define cur (gap-buf-gap-start buf))
  (define li (pos->line ls cur))
  (when (> li 0)
    (define target-line-start (list-ref ls (sub1 li)))
    (define target-line-end (list-ref ls li))
    ;; E18-E21: 用 pref-col 找目标位置（首次用当前列）
    (define target-col (or (gap-buf-pref-col buf)
                           (compute-display-col buf (list-ref ls li) cur)))
    (define new-pos (find-pos-by-display-col buf target-line-start target-line-end target-col))
    (move-gap! buf new-pos)
    ;; pref-col 保持不变
    ))

(define (buffer-move-down buf)
  ;; E17, E22: 最后一行或空缓冲区 → no-op
  (define ls (get-lines buf))
  (define n (length ls))
  (define cur (gap-buf-gap-start buf))
  (define li (pos->line ls cur))
  (when (< (add1 li) n)
    (define target-line-start (list-ref ls (add1 li)))
    (define target-line-end (if (< (+ li 2) n) (list-ref ls (+ li 2)) (gap-buf-total-len buf)))
    ;; E18-E21: 用 pref-col 找目标位置
    (define target-col (or (gap-buf-pref-col buf)
                           (compute-display-col buf (list-ref ls li) cur)))
    (define new-pos (find-pos-by-display-col buf target-line-start target-line-end target-col))
    (move-gap! buf new-pos)
    ;; pref-col 保持不变
    ))

(define (buffer-move-home buf)
  ;; E23, E26
  (define ls (get-lines buf))
  (define cur (gap-buf-gap-start buf))
  (define li (pos->line ls cur))
  (define line-start (list-ref ls li))
  (unless (= cur line-start)
    (move-gap! buf line-start)
    (set-gap-buf-pref-col! buf 0)))

(define (buffer-move-end buf)
  ;; E24, E25, E26
  (define ls (get-lines buf))
  (define n (length ls))
  (define cur (gap-buf-gap-start buf))
  (define li (pos->line ls cur))
  (define tl (gap-buf-total-len buf))
  ;; target: 非最后一行 → 换行符位置 (lines[li+1]-1); 最后一行 → total-len
  (define target
    (if (< (add1 li) n)
        (sub1 (list-ref ls (add1 li)))  ; 换行符位置
        tl))
  (unless (= cur target)
    (move-gap! buf target)
    (set-gap-buf-pref-col! buf
      (compute-display-col buf (list-ref ls li) target))))

(define (buffer-move-to buf pos)
  ;; E27, E28: clamp
  (define tl (gap-buf-total-len buf))
  (define p (max 0 (min pos tl)))
  (unless (= p (gap-buf-gap-start buf))
    (move-gap! buf p)
    ;; 更新 pref-col
    (define ls (get-lines buf))
    (define li (pos->line ls p))
    (set-gap-buf-pref-col! buf
      (compute-display-col buf (list-ref ls li) p))))

;; ═══════════════════════════════════════════════════════════
;; 内部：二进制搜索行号
;; ═══════════════════════════════════════════════════════════

(define (pos->line ls pos)
  (define n (length ls))
  (let loop ([li 0])
    (cond
      [(>= li (sub1 n)) li]
      [(< pos (list-ref ls (add1 li))) li]
      [else (loop (add1 li))])))

;; ═══════════════════════════════════════════════════════════
;; 公开 API：查询
;; ═══════════════════════════════════════════════════════════

(define (buffer-cursor-pos buf)     (gap-buf-gap-start buf))
(define (buffer-total-len buf)      (gap-buf-total-len buf))
(define (buffer-empty? buf)         (zero? (gap-buf-total-len buf)))

(define (buffer-char-at buf pos)
  (define tl (gap-buf-total-len buf))
  (when (or (< pos 0) (>= pos tl))
    (error 'buffer-char-at "position ~a out of range [0, ~a)" pos tl))
  (vector-ref (gap-buf-chars buf) (logic->phys buf pos)))

(define (buffer-char-display-width-at buf pos)
  (define tl (gap-buf-total-len buf))
  (when (or (< pos 0) (>= pos tl))
    (error 'buffer-char-display-width-at "position ~a out of range [0, ~a)" pos tl))
  (vector-ref (gap-buf-widths buf) (logic->phys buf pos)))

(define (buffer-text buf)
  (define tl (gap-buf-total-len buf))
  (define gs (gap-buf-gap-start buf))
  (define ge (gap-buf-gap-end buf))
  (define cs (gap-buf-chars buf))
  (string-append
   (list->string (for/list ([i (in-range gs)]) (vector-ref cs i)))
   (list->string (for/list ([i (in-range ge (+ ge (- tl gs)))]) (vector-ref cs i)))))

;; ── 行查询 ──

(define (buffer-line-count buf)
  (length (get-lines buf)))

(define (buffer-line-start buf line-idx)
  (define ls (get-lines buf))
  (list-ref ls line-idx))

(define (buffer-line-end buf line-idx)
  ;; 返回 exclusive end: 若后面还有行则是下一行起始，否则是 total-len
  (define ls (get-lines buf))
  (define n (length ls))
  (if (< (add1 line-idx) n)
      (list-ref ls (add1 line-idx))
      (gap-buf-total-len buf)))

(define (buffer-cursor-line buf)
  (define ls (get-lines buf))
  (pos->line ls (gap-buf-gap-start buf)))

(define (buffer-cursor-col buf)
  ;; 字符偏移（从行首算起）
  (define ls (get-lines buf))
  (define cur (gap-buf-gap-start buf))
  (define li (pos->line ls cur))
  (- cur (list-ref ls li)))

(define (buffer-cursor-display-col buf)
  ;; display-width 偏移（从行首算起）
  (define ls (get-lines buf))
  (define cur (gap-buf-gap-start buf))
  (define li (pos->line ls cur))
  (compute-display-col buf (list-ref ls li) cur))
