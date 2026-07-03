#lang racket

(require "../ui/main.rkt")

;; ── 内容: 混合 string / out-line / out-fold ──

(define blocks
  (box
   (list
    "=== Agent Session ==="
    ""
    (out-line "  ✓  analysis complete" 'success)
    (out-line "  ⚠  3 warnings found" 'warning)
    (out-line "  ✗  1 error detected" 'error)
    ""
    (out-fold "Warnings"
              (list (out-line "  line 42: unused binding" 'warning)
                    (out-line "  line 88: missing contract" 'warning)
                    (out-line "  line 156: shadowed variable" 'warning))
              #t)
    (out-fold "Error"
              (list (out-line "  line 200: type mismatch" 'error)
                    (out-line "  expected: number" 'info)
                    (out-line "  got: string" 'info))
              #t)
    ""
    "=== Done ===")))

;; ── 流式追加按钮 ──

(define counter (box 0))

(define (append-new!)
  (set-box! counter (add1 (unbox counter)))
  (define new-line
    (out-line (format "  → streamed line #~a" (unbox counter)) 'info))
  ;; 插到 "Done" 之前
  (define bs (unbox blocks))
  (define done-i (index-of bs "=== Done ==="))
  (define before (take bs done-i))
  (define after  (drop bs done-i))
  (set-box! blocks (append before (list new-line) after)))

(define (index-of lst item)
  (for/or ([x lst] [i (in-naturals)]) (and (equal? x item) i)))

;; ── 组件 ──

(define output (make-output #:blocks blocks))
(define btn-append (make-button #:text "Append line"
                                #:on-activate append-new!))

(define (all-expand!)
  (for ([b (unbox blocks)]) (out-fold-expand-all! b))
  (set-box! (component-dirty output) #t))

(define (all-collapse!)
  (for ([b (unbox blocks)]) (out-fold-collapse-all! b))
  (set-box! (component-dirty output) #t))

(define specs
  (list
   (list (make-text #:text "┌────┤ Output + Style + Stream ├──┐" #:style 'title)
         1 1 34 1)
   (list (make-text #:text "│ ↑↓/Pg scroll  click/Enter fold│" #:style 'info)
         1 2 34 1)
   (list (make-text #:text "└────────────────────────────────┘" #:style 'title)
         1 3 34 1)
   (list output 1 4 34 12)
   (list btn-append 1 17 0 0)
   (list (make-button #:text "Expand" #:on-activate all-expand!) 18 17 0 0)
   (list (make-button #:text "Collapse" #:on-activate all-collapse!) 30 17 0 0)))

(run-app specs)
