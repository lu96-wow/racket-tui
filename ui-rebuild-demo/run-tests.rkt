#lang racket

(require racket/runtime-path)

;; UI 测试运行器 — 运行本目录下所有 *-test.rkt / *-tests.rkt
;;
;; 用法（任意目录下均可）:
;;   racket ui-rebuild-demo/run-tests.rkt
;;
;; 每个测试文件独立进程运行，互不影响；退出码非 0 计为失败。

(define-runtime-path test-dir ".")

(define test-files
  (sort
   (for/list ([e (directory-list test-dir)]
              #:when (and (regexp-match? #rx"-(test|tests)\\.rkt$" (path->string e))
                          (not (equal? (path->string e) "run-tests.rkt"))))
     (path->string e))
   string<?))

(printf "running ~a UI test file(s)...\n\n" (length test-files))

(define failed '())
(for ([f (in-list test-files)])
  (printf "=== ~a ===\n" f)
  (flush-output)
  (define ok? (system* (find-executable-path "racket") (build-path test-dir f)))
  (unless ok?
    (set! failed (cons f failed)))
  (newline))

(printf "════════════════════════════════\n")
(if (null? failed)
    (printf "ALL ~a TEST FILE(S) PASSED\n" (length test-files))
    (begin
      (printf "~a/~a TEST FILE(S) FAILED:\n" (length failed) (length test-files))
      (for ([f (in-list (reverse failed))])
        (printf "  - ~a\n" f))
      (exit 1)))
