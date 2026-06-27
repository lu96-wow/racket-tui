#lang racket

(require "../main.rkt")


(let-values ([(r c) (query-cursor!)])
  (put-at 8 0 (format "终端报告: row=~a, col=~a" r c))
  (put-at 9 0 (format "库追踪:   row=~a, col=~a" current-cursor-row current-cursor-col)))