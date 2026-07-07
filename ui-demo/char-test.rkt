#lang racket
;; ui-test/char-test.rkt — 验证 space 是否正确被 #:char 接收
;;
;; 输入任何字符（包括空格），直接显示在输入框中
;; build-input 没有定义 #:space，space 应该落进 #:char

(require "../main.rkt"
         "../ui/run.rkt"
         "../ui/component.rkt"
         "../ui/widgets/input.rkt"
         "../base/io/output.rkt"
         "../base/io/output-styles.rkt")

(define input
  (make-input #:placeholder "type anything (including spaces)..."
              #:on-submit void
              #:on-change void))

(run-app
 (input 1 1 40 1))
