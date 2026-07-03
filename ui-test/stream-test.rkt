#lang racket

(require "../ui/main.rkt")

;; ═══════════════════════════════════════════════════════
;; output 逐字流式测试
;; ═══════════════════════════════════════════════════════

;; 三个 out-line, 三个 fold, 各自独立逐字追加

(define line1 (out-line "" 'success))
(define line2 (out-line "" 'warning))
(define line3 (out-line "" 'error))

(define fold (out-fold "" (list line1 line2 line3) #t))
(define blocks (box (list fold "")))
(define output (make-output #:blocks blocks))

(define title-src "Char-by-char streaming demo — click [+] to collapse")
(define src1 "✓  Task 1: analyzing source tree... found 42 files, 3 warnings. Coverage: 87.3%.")
(define src2 "⚠  Task 2: running test suite... 36/37 passed, 1 skipped. Time: 3.24s.")
(define src3 "✗  Task 3: build failed — type mismatch at output.rkt:156.")

;; 线程 0: fold 标题逐字
(thread
  (λ ()
    (let loop ([i 0])
      (sleep 0.6)
      (when (< i (string-length title-src))
        (set-out-fold-title! fold (substring title-src 0 (add1 i)))
        (loop (add1 i))))))

;; 线程 1-3: 三个 out-line 逐字 (各延迟 2s)
(thread
  (λ ()
    (sleep 2.0)
    (let loop ([i 0])
      (sleep 0.06)
      (when (< i (string-length src1))
        (set-out-line-text! line1 (substring src1 0 (add1 i)))
        (loop (add1 i))))))

(thread
  (λ ()
    (sleep 5.0)
    (let loop ([i 0])
      (sleep 0.06)
      (when (< i (string-length src2))
        (set-out-line-text! line2 (substring src2 0 (add1 i)))
        (loop (add1 i))))))

(thread
  (λ ()
    (sleep 3.0)
    (let loop ([i 0])
      (sleep 0.6)
      (when (< i (string-length src3))
        (set-out-line-text! line3 (substring src3 0 (add1 i)))
        (loop (add1 i))))))

(define specs
  (list
    (list (make-text #:text "╔════════════════════════════════════╗" #:style 'title) 1 1 60 1)
    (list (make-text #:text "║  Output char-by-char streaming    ║" #:style 'info) 1 2 60 1)
    (list (make-text #:text "╚════════════════════════════════════╝" #:style 'title) 1 3 60 1)
    (list output 1 4 60 10)))

(run-app-nobuffer specs #:noblock? #t)
