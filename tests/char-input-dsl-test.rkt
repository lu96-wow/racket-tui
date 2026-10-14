#lang racket

;; char 便捷注入 DSL 测试。
;; 目标：写场景时不用手搓 (key-event ... (mods ...))，直接 "字符串" / 'ctrl / 'paste 就行。

(require rackunit
         "../char.rkt")

(define (drain!)
  ;; 只读，不清空：push! 之后调用
  (let loop ([acc '()])
    (if (char-input-empty?)
        (reverse acc)
        (loop (cons (read-event) acc)))))

(define (keys evs) (map key-event-key evs))
(define (mods-of ev) (key-event-mods ev))

(module+ test

  (test-case "裸字符串 = 逐字符按键，支持 UTF-8"
    (char-input-push! "hi你")
    (define evs (drain!))
    (check-equal? (keys evs) (list #\h #\i #\你))
    (check-true (andmap key-event? evs)))

  (test-case "命名键 / 裸字符 / ASCII 特殊键归一化"
    (char-input-push! 'enter 'up #\tab #\space #\a)
    (check-equal? (keys (drain!)) (list 'enter 'up 'tab #\space #\a)))

  (test-case "粘性修饰键：'ctrl #\\c / 'shift \"ab\" / 'ctrl 'alt #\\x"
    (char-input-push! 'ctrl #\c)
    (let ([e (car (drain!))])
      (check-equal? (key-event-key e) #\c)
      (check-true (mods-ctrl? (mods-of e))))
    (char-input-push! 'shift "ab")
    (let ([es (drain!)])
      (check-equal? (keys es) (list #\a #\b))
      (check-true (andmap (λ (e) (mods-shift? (mods-of e))) es)))
    (char-input-push! 'ctrl 'alt #\x)
    (let ([m (mods-of (car (drain!)))])
      (check-true (mods-ctrl? m))
      (check-true (mods-alt? m))))

  (test-case "'key 显式按键 + 显式/粘性 mods 合并"
    (char-input-push! 'key 'up (mods #f #f #t))
    (let ([e (car (drain!))])
      (check-equal? (key-event-key e) 'up)
      (check-true (mods-shift? (mods-of e))))
    (char-input-push! 'ctrl 'key #\d)
    (check-true (mods-ctrl? (mods-of (car (drain!))))))

  (test-case "'paste / 'resize / 'mouse"
    (char-input-push! 'paste "line1\nline2")
    (let ([e (car (drain!))])
      (check-true (paste-event? e))
      (check-equal? (paste-event-text e) "line1\nline2"))
    (char-input-push! 'resize 40 120)
    (let ([e (car (drain!))])
      (check-true (resize-event? e))
      (check-equal? (resize-event-rows e) 40)
      (check-equal? (resize-event-cols e) 120))
    (char-input-push! 'mouse 'press 'left 3 4)
    (let ([e (car (drain!))])
      (check-true (mouse-event? e))
      (check-equal? (mouse-event-action e) 'press)
      (check-equal? (mouse-event-button e) 'left)
      (check-equal? (mouse-event-x e) 3)
      (check-equal? (mouse-event-y e) 4))
    (char-input-push! 'mouse 'scroll 'up 3 4)
    (check-equal? (mouse-event-button (car (drain!))) 'up))

  (test-case "'utf8 走归一化路径"
    (char-input-push! 'utf8 "你")
    (let ([e (car (drain!))])
      (check-true (key-event? e))
      (check-equal? (key-event-key e) #\你)))

  (test-case "修饰键悬空报错"
    (check-exn exn:fail? (λ () (char-input-push! 'ctrl)))
    (check-exn exn:fail? (λ () (char-input-push! 'ctrl 'alt))))

  (test-case "旧写法保持兼容"
    (char-input-push! (key-event #\y (mods #t #f #f)))
    (check-true (mods-ctrl? (mods-of (car (drain!)))))
    (char-input-push! (list #\a (mods #f #f #t)))
    (check-true (mods-shift? (mods-of (car (drain!)))))
    (char-input-push! '(ctrl #"\x01" #f))
    (let ([e (car (drain!))])
      (check-true (key-event? e))
      (check-true (mods-ctrl? (mods-of e)))))

  (test-case "顺序保持：字符串展开后接命名键"
    (char-input-push! "ab" 'enter 'ctrl "cd")
    (define evs (drain!))
    (check-equal? (keys evs) (list #\a #\b 'enter #\c #\d))
    (check-true (mods-ctrl? (mods-of (list-ref evs 3))))
    (check-true (mods-ctrl? (mods-of (list-ref evs 4))))))
