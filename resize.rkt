#lang racket
(require ffi/unsafe)

(define ioctl (get-ffi-obj 'ioctl (ffi-lib #f) (_fun _int _int _pointer -> _int)))
(define TIOCGWINSZ #x5413)
(define STDOUT_FILENO 1)

(define (get-window-size (fd STDOUT_FILENO))
  (define ws (make-bytes 8 0))
  (if (= (ioctl fd TIOCGWINSZ ws) -1)
      (values #f #f)
      (values (+ (bytes-ref ws 0) (arithmetic-shift (bytes-ref ws 1) 8))
              (+ (bytes-ref ws 2) (arithmetic-shift (bytes-ref ws 3) 8)))))

(provide get-window-size)