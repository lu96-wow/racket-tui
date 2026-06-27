#lang racket

(require "ansi-var.rkt")

(provide current-cursor-row current-cursor-col
         set-cursor! get-cursor)

(define current-cursor-row ansi-source-row)
(define current-cursor-col ansi-source-col)

(define (set-cursor! row col)
  (set! current-cursor-row row)
  (set! current-cursor-col col))

(define (get-cursor)
  (values current-cursor-row current-cursor-col))