#lang racket

(require "../ui/main.rkt")

;; ── 构建可折叠内容 ──

(define blocks
  (box
   (list
    "=== Agent Output ==="
    ""
    (out-fold "Task 1: Analyze code"
              (list "  file: main.rkt"
                    "  lines: 200"
                    "  issues: 3"
                    (out-fold "Issue #1: unused variable"
                              (list "  line 42: define x = 5 (never used)"
                                    "  severity: low")
                              #t)
                    (out-fold "Issue #2: missing type"
                              (list "  line 88: no contract on public API"
                                    "  severity: medium")
                              #t)
                    (out-fold "Issue #3: potential overflow"
                              (list "  line 156: unchecked addition"
                                    "  severity: high")
                              #f))
              #t)
    ""
    (out-fold "Task 2: Run tests"
              (list "  12/12 passed"
                    "  coverage: 87%"
                    "  time: 3.2s")
              #f)
    ""
    (out-fold "Task 3: Deploy"
              (list "  build: success"
                    "  push: success"
                    (out-fold "Details"
                              (list "  commit: abc123"
                                    "  branch: main"
                                    "  tag: v1.2.0")
                              #f))
              #f)
    ""
    "=== Done ===")))

;; ── 组件 ──

(define output
  (make-output #:blocks blocks))

;; 控制按钮: 全部展开 / 全部折叠

(define (all-expand!)
  (for ([b (unbox blocks)])
    (out-fold-expand-all! b))
  (set-box! (component-dirty output) #t))

(define (all-collapse!)
  (for ([b (unbox blocks)])
    (out-fold-collapse-all! b))
  (set-box! (component-dirty output) #t))

(define specs
  (list
   (list (make-text #:text "┌────┤ Output Test ├──────────────┐" #:style 'title)
         1 1 34 1)
   (list (make-text #:text "│ ↑↓ scroll  Enter/click toggle  │" #:style 'info)
         1 2 34 1)
   (list (make-text #:text "└────────────────────────────────┘" #:style 'title)
         1 3 34 1)
   (list output 1 4 34 12)
   (list (make-button #:text "Expand All" #:on-activate all-expand!)  1 17 0 0)
   (list (make-button #:text "Collapse All" #:on-activate all-collapse!) 15 17 0 0)))

(run-app specs)
