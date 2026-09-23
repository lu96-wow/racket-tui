#lang info

(define collection "tui")
(define version "0.0.1")
(define deps '("base"))
(define build-deps '("rackunit-lib" "scribble-lib" "racket-doc"))
(define scribblings '(("index.scrbl" ())))
(define pkg-desc "Terminal UI library for Racket (Linux / Android-Termux)")
(define pkg-authors '("lu96-wow"))
(define license 'MIT)
(define compile-omit-paths '("demo"))
