#lang racket
(require "ansi-format.rkt")

(provide make-screen-buffer
         sb-ensure!
         sb-put! sb-put-at! sb-clear!
         sb-flush!
         sb-rows sb-cols)

;; =============================================================================
;; 双缓冲屏幕渲染器
;;
;; 核心思路：
;;   1. 每帧先把内容"画"到 screen-buffer 上（内存操作，极快）
;;   2. flush 时 diff 对比上一帧，只输出变化了的格子
;;   3. resize 时缓冲只增大不缩小，避免反复分配
;; =============================================================================

(struct screen-buffer (rows cols cells prev-cells)
  #:mutable)

(define (make-screen-buffer)
  (screen-buffer 0 0 (vector) (vector)))

(define (sb-rows buf) (screen-buffer-rows buf))
(define (sb-cols buf) (screen-buffer-cols buf))

;; 确保缓冲区至少有 rows×cols 大小（只增大不缩小）
(define (sb-ensure! buf rows cols)
  (define old-rows (vector-length (screen-buffer-cells buf)))
  (define old-cols (if (> old-rows 0)
                       (vector-length (vector-ref (screen-buffer-cells buf) 0))
                       0))
  ;; 需要扩大行
  (when (> rows old-rows)
    (define new-cells (make-vector rows))
    (for ([r (in-range old-rows)])
      (vector-set! new-cells r (vector-ref (screen-buffer-cells buf) r)))
    (for ([r (in-range old-rows rows)])
      (vector-set! new-cells r (make-vector (max cols old-cols) #f)))
    (set-screen-buffer-cells! buf new-cells))
  ;; 需要扩大列
  (when (> cols old-cols)
    (define cells (screen-buffer-cells buf))
    (for ([r (in-range (max rows old-rows))])
      (define old-row (vector-ref cells r))
      (define new-row (make-vector cols #f))
      (for ([c (in-range (min cols old-cols))])
        (vector-set! new-row c (vector-ref old-row c)))
      (vector-set! cells r new-row)))
  ;; 更新尺寸记录
  (set-screen-buffer-rows! buf rows)
  (set-screen-buffer-cols! buf cols))

;; 清除当前帧所有内容（填为空格）
(define (sb-clear! buf)
  (define cells (screen-buffer-cells buf))
  (define rows (screen-buffer-rows buf))
  (define cols (screen-buffer-cols buf))
  (for ([r (in-range rows)])
    (define row (vector-ref cells r))
    (for ([c (in-range cols)])
      (vector-set! row c (bytes 32)))))

;; 在当前位置写入内容
(define (sb-put! buf row col bytes)
  (define cells (screen-buffer-cells buf))
  (when (and (< row (vector-length cells))
             (< col (vector-length (vector-ref cells row))))
    (vector-set! (vector-ref cells row) col bytes)))

;; 绝对位置写入
(define (sb-put-at! buf row col bytes)
  (sb-put! buf row col bytes))

;; =============================================================================
;; flush: diff + 输出
;; =============================================================================

;; 构建单行上连续变化的输出序列
;; 返回 (bytes-append ...) 包含该行所有变化的 cursor-move + cell-bytes
(define (render-row-diff buf prev-cells row cols out)
  (define cells (screen-buffer-cells buf))
  (define row-vec (vector-ref cells row))
  (define prev-row (and prev-cells
                        (< row (vector-length prev-cells))
                        (vector-ref prev-cells row)))

  (let loop ([col 0])
    (when (< col cols)
      (define new-bs (vector-ref row-vec col))
      (define old-bs (and prev-row
                          (< col (vector-length prev-row))
                          (vector-ref prev-row col)))
      (cond
        ;; 新旧相同 → 跳过
        [(and new-bs old-bs (equal? new-bs old-bs))
         (loop (+ col 1))]
        ;; new 为空 → 跳过（不应该发生，cleared 的格子是空格）
        [(not new-bs)
         (loop (+ col 1))]
        ;; 有变化 → 输出 cursor-move + cell bytes
        [else
         (write-bytes (format-cursor-move row col) out)
         (write-bytes new-bs out)
         (loop (+ col 1))]))))

;; 主 flush 函数
(define (sb-flush! buf)
  (define rows (screen-buffer-rows buf))
  (define cols (screen-buffer-cols buf))
  (define prev-cells (screen-buffer-prev-cells buf))

  ;; 第一阶段：收集所有输出到内存 buffer
  (define out (open-output-bytes))
  (write-bytes format-cursor-hide out)

  (for ([r (in-range rows)])
    (render-row-diff buf prev-cells r cols out))

  ;; 第二阶段：一次性写入终端
  (define frame-bytes (get-output-bytes out))
  (close-output-port out)
  (write-bytes frame-bytes)
  (flush-output)

  ;; 第三阶段：保存当前帧作为下次的 prev
  (define new-prev (make-vector rows))
  (define cells (screen-buffer-cells buf))
  (for ([r (in-range rows)])
    (define src-row (vector-ref cells r))
    (define dst-row (make-vector cols))
    (for ([c (in-range cols)])
      (vector-set! dst-row c (vector-ref src-row c)))
    (vector-set! new-prev r dst-row))
  (set-screen-buffer-prev-cells! buf new-prev))
