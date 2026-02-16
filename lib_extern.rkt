#lang racket

;;这是对ncurese库的二次封装拓展

(require "lib.rkt"
         "lib_help.rkt"
         "key.rkt"
         "mouse.rkt")

(require (for-syntax syntax/parse))

(define-syntax-rule (reverse-var-subwin win x y width height)
  (subwin win height width y x))

(define-syntax-rule (addstr-attr str attr)
  (begin (attron attr) (addstr str) (attroff attr)))

(define-syntax-rule (addch-attr ch attr)
  (begin (attron attr) (addch ch) (attroff attr)))

(define-syntax-rule (mvaddstr-attr y x str attr)
  (begin (attron attr) (mvaddstr y x str) (attroff attr)))

(define-syntax-rule (mvaddch-attr y x ch attr)
  (begin (attron attr) (mvaddch y x ch) (attroff attr)))

(define-syntax-rule (addnstr-attr str-bytes n attr)
  (begin (attron attr) (addnstr str-bytes n) (attroff attr)))

(define-syntax-rule (mvaddnstr-attr y x str-bytes n attr)
  (begin (attron attr) (mvaddnstr y x str-bytes n) (attroff attr)))

(define-syntax-rule (waddch-attr win ch attr)
  (begin (wattron win attr) (waddch win ch) (wattroff win attr)))

(define-syntax-rule (mvwaddch-attr win y x ch attr)
  (begin (wattron win attr) (mvwaddch win y x ch) (wattroff win attr)))

(define-syntax-rule (mvwaddstr-attr win y x str attr)
  (begin (wattron win attr) (mvwaddstr win y x str) (wattroff win attr)))

(define-syntax-rule (waddstr-attr win str attr)
  (begin (wattron win attr) (waddstr win str) (wattroff win attr)))

(define-syntax-rule (waddnstr-attr win str-bytes n attr)
  (begin (wattron win attr) (waddnstr win str-bytes n) (wattroff win attr)))

(define-syntax-rule (mvwaddnstr-attr win y x str-bytes n attr)
  (begin (wattron win attr) (mvwaddnstr win y x str-bytes n) (wattroff win attr)))

(define-syntax-rule (waddch-wattr win ch attr)
  (begin (wattron win attr) (waddch win ch) (wattroff win attr)))

(define-syntax-rule (mvwaddch-wattr win y x ch attr)
  (begin (wattron win attr) (mvwaddch win y x ch) (wattroff win attr)))

(define-syntax-rule (waddstr-wattr win str attr)
  (begin (wattron win attr) (waddstr win str) (wattroff win attr)))

(define-syntax-rule (mvwaddstr-wattr win y x str attr)
  (begin (wattron win attr) (mvwaddstr win y x str) (wattroff win attr)))

(define-syntax-rule (waddnstr-wattr win str-bytes n attr)
  (begin (wattron win attr) (waddnstr win str-bytes n) (wattroff win attr)))

(define-syntax-rule (mvwaddnstr-wattr win y x str-bytes n attr)
  (begin (wattron win attr) (mvwaddnstr win y x str-bytes n) (wattroff win attr)))

;;为了支持可选参数，这个不用宏了
;; 设置通用 ncurses 状态，支持可选 timeout（毫秒）
;; timeout = -1 → 阻塞（默认）
;; timeout = 0  → 完全非阻塞
;; timeout > 0  → 最多等待 timeout 毫秒
(define (setup-common-ncurses #:timeout [timeout-ms -1])
  (define stdscr (initscr))
  (cbreak)
  (noecho)
  (keypad stdscr #t)
  (mousemask (help_get_ALL_MOUSE_EVENTS) #f)
  (timeout timeout-ms)
  (current-input-timeout timeout-ms)
  (when (> (has_colors) 0)
    (start_color)
    (use_default_colors)    ;;为了ncurses兼容启用
  )
  stdscr)

(define (with-ncurses proc #:timeout [timeout-ms -1])
  (define stdscr (setup-common-ncurses #:timeout timeout-ms))
  (dynamic-wind
    void
    (λ () (proc))
    (λ () (endwin))))

(define (with-ncurses-stdscr proc #:timeout [timeout-ms -1])
  (define stdscr (setup-common-ncurses #:timeout timeout-ms))
  (dynamic-wind
    void
    (λ () (proc stdscr))
    (λ () (endwin))))

;; 全局字符串（无坐标）
;;虽然不需要/xy 避免与绑定冲突，还是用/xy /xy代表风格
(define-syntax (addstr/xy stx)
  (syntax-parse stx
    [(addstr/xy str:expr)
     #'(addstr str)]
    [(addstr/xy str:expr attr:expr)
     #'(addstr-attr str attr)]))

(define-syntax (addch/xy stx)
  (syntax-parse stx
    [(addch/xy ch:expr)
     #'(addch ch)]
    [(addch/xy ch:expr attr:expr)
     #'(addch-attr ch attr)]))

(define-syntax (mvaddstr/xy stx)
  (syntax-parse stx
    [(mvaddstr/xy x:expr y:expr str:expr)
     #'(mvaddstr y x str)]
    [(mvaddstr/xy x:expr y:expr str:expr attr:expr)
     #'(mvaddstr-attr y x str attr)]))

(define-syntax (mvaddch/xy stx)
  (syntax-parse stx
    [(mvaddch/xy x:expr y:expr ch:expr)
     #'(mvaddch y x ch)]
    [(mvaddch/xy x:expr y:expr ch:expr attr:expr)
     #'(mvaddch-attr y x ch attr)]))

(define-syntax (mvaddnstr/xy stx)
  (syntax-parse stx
    [(mvaddnstr/xy x:expr y:expr str:expr n:expr)
     #'(mvaddnstr y x str n)]
    [(mvaddnstr/xy x:expr y:expr str:expr n:expr attr:expr)
     #'(mvaddnstr-attr y x str n attr)]))

(define-syntax (waddstr/xy stx)
  (syntax-parse stx
    [(waddstr/xy win:expr str:expr)
     #'(waddstr win str)]
    [(waddstr/xy win:expr str:expr attr:expr)
     #'(waddstr-attr win str attr)]))

(define-syntax (waddch/xy stx)
  (syntax-parse stx
    [(waddch/xy win:expr ch:expr)
     #'(waddch win ch)]
    [(waddch/xy win:expr ch:expr attr:expr)
     #'(waddch-attr win ch attr)]))

(define-syntax (mvwaddstr/xy stx)
  (syntax-parse stx
    [(mvwaddstr/xy win:expr x:expr y:expr str:expr)
     #'(mvwaddstr win y x str)]
    [(mvwaddstr/xy win:expr x:expr y:expr str:expr attr:expr)
     #'(mvwaddstr-attr win y x str attr)]))

(define-syntax (mvwaddch/xy stx)
  (syntax-parse stx
    [(mvwaddch/xy win:expr x:expr y:expr ch:expr)
     #'(mvwaddch win y x ch)]
    [(mvwaddch/xy win:expr x:expr y:expr ch:expr attr:expr)
     #'(mvwaddch-attr win y x ch attr)]))

(define-syntax (waddnstr/xy stx)
  (syntax-parse stx
    [(waddnstr/xy win:expr str:expr n:expr)
     #'(waddnstr win str n)]
    [(waddnstr/xy win:expr str:expr n:expr attr:expr)
     #'(waddnstr-attr win str n attr)]))

(define-syntax (mvwaddnstr/xy stx)
  (syntax-parse stx
    [(mvwaddnstr/xy win:expr x:expr y:expr str:expr n:expr)
     #'(mvwaddnstr win y x str n)]
    [(mvwaddnstr/xy win:expr x:expr y:expr str:expr n:expr attr:expr)
     #'(mvwaddnstr-attr win y x str n attr)]))

(define-syntax (waddstr/wxy stx)
  (syntax-parse stx
    [(waddstr/wxy win:expr str:expr)
     #'(waddstr win str)]
    [(waddstr/wxy win:expr str:expr attr:expr)
     #'(waddstr-wattr win str attr)]))

(define-syntax (waddch/wxy stx)
  (syntax-parse stx
   [(waddch/wxy win:expr ch:expr)
     #'(waddch win ch)]
    [(waddch/wxy win:expr ch:expr attr:expr)
     #'(waddch-wattr win ch attr)]))

(define-syntax (mvwaddstr/wxy stx)
  (syntax-parse stx
    [(mvwaddstr/wxy win:expr x:expr y:expr str:expr)
     #'(mvwaddstr win y x str)]
    [(mvwaddstr/wxy win:expr x:expr y:expr str:expr attr:expr)
     #'(mvwaddstr-wattr win y x str attr)]))

(define-syntax (mvwaddch/wxy stx)
  (syntax-parse stx
    [(mvwaddch/wxy win:expr x:expr y:expr ch:expr)
     #'(mvwaddch win y x ch)]
    [(mvwaddch/wxy win:expr x:expr y:expr ch:expr attr:expr)
     #'(mvwaddch-wattr win y x ch attr)]))

(define-syntax (waddnstr/wxy stx)
  (syntax-parse stx
   [(waddnstr/wxy win:expr str:expr n:expr)
     #'(waddnstr win str n)]
    [(waddnstr/wxy win:expr str:expr n:expr attr:expr)
     #'(waddnstr-wattr win str n attr)]))

(define-syntax (mvwaddnstr/wxy stx)
  (syntax-parse stx
    [(mvwaddnstr/wxy win:expr x:expr y:expr str:expr n:expr)
     #'(mvwaddnstr win y x str n)]
    [(mvwaddnstr/wxy win:expr x:expr y:expr str:expr n:expr attr:expr)
     #'(mvwaddnstr-wattr win y x str n attr)]))

;; 创建新窗口，参数顺序: x y width height
(define-syntax-rule (newwin/xy x y width height)
  (newwin height width y x))

;; 创建子窗口，参数顺序: win x y width height
(define-syntax-rule (subwin/xy win x y width height)
  (subwin win height width y x))

;; 导出
(provide (all-defined-out))