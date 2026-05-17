#lang racket

(provide current-cursor-row current-cursor-col
         set-cursor! get-cursor)

(define current-cursor-row 0)
(define current-cursor-col 0)

(define (set-cursor! row col)
  (set! current-cursor-row row)
  (set! current-cursor-col col))

(define (get-cursor)
  (values current-cursor-row current-cursor-col))