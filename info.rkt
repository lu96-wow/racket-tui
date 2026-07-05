#lang info

(define name "tui")
(define version "0.0.1")
(define description "Terminal UI library for Racket")
(define authors '("lu96-wow"))
(define license "MIT")

(define collection "tui")
(define depends '("base"))
(define build-deps '("racket-lib"))
(define compile-omit-paths '("test" "ui-test"))