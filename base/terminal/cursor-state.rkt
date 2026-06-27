#lang racket

(require "../ansi/ansi-var.rkt" "base.rkt")

(provide current-cursor-row current-cursor-col
         set-cursor! get-cursor query-cursor!)

(define current-cursor-row ansi-source-row)
(define current-cursor-col ansi-source-col)

(define (set-cursor! row col)
  (set! current-cursor-row row)
  (set! current-cursor-col col))

(define (get-cursor)
  (values current-cursor-row current-cursor-col))

;; 发送 ANSI DSR \e[6n 查询终端实际光标位置
;; 终端回复 \e[row;colR，解析后更新 current-cursor-row/col
(define (query-cursor!)
  (call-with-terminal-reply
    (λ ()
      (define in (current-input-port))
      (flush-output)
      (display "\x1b[6n")
      (flush-output)
      (let loop ()
        (define b (read-byte in))
        (when (and b (= b ESC))
          (define b2 (read-byte in))
          (when (and b2 (= b2 CSI-OPEN))
            (let parse-row ([row 0])
              (define b3 (read-byte in))
              (if (and b3 (<= ASCII-DIGIT-START b3 ASCII-DIGIT-END))
                  (parse-row (+ (* row 10) (- b3 ASCII-DIGIT-START)))
                  (when (and b3 (= b3 CSI-PARAM-SEP))
                    (let parse-col ([col 0])
                      (define b4 (read-byte in))
                      (if (and b4 (<= ASCII-DIGIT-START b4 ASCII-DIGIT-END))
                          (parse-col (+ (* col 10) (- b4 ASCII-DIGIT-START)))
                          (when b4
                            (set! current-cursor-row row)
                            (set! current-cursor-col col))))))))))
      (values current-cursor-row current-cursor-col))))