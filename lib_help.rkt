#lang racket
(require ffi/unsafe ffi/unsafe/define)

;; 优先在系统库路径中查找，再回退到当前目录
(define (find-help-lib)
  (for/or ([name '("ncurses-help"
                   "libncurses-help"
                   "./ncurses-help.so"        ;;在标准路径找不到库会在同目录找，觉得不安全可以删掉
                   "./libncurses-help.so")])
    (with-handlers ([exn:fail? (λ (_) #f)])
      (ffi-lib name #:fail #f))))

(define help-lib
  (or (find-help-lib)
      (error "ncurses-help library not found. Please compile ncurses-help.c and place it in current directory or system library path.")))

(define-ffi-definer define-help help-lib)

(define-help help_get_ALL_MOUSE_EVENTS (_fun -> _ulong))
(define-help help_get_mouse_event_string (_fun -> _string))

(define-help help_get_COLORS (_fun -> _int))
(define-help help_get_COLOR_PAIRS (_fun -> _int))
(define-help help_COLOR_PAIR (_fun _int -> _ulong))

(provide help_get_ALL_MOUSE_EVENTS
         help_get_mouse_event_string
         help_get_COLORS
         help_get_COLOR_PAIRS
         help_COLOR_PAIR)