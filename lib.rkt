#lang racket

(require ffi/unsafe
         ffi/unsafe/define)

;; ---------- 加载库 ----------
(define (find-ncurses-lib)
  (define candidates
    '("libncursesw.so.6" "libncursesw.so.5" "libncursesw"
      "libncurses.so.6" "libncurses.so.5" "libncurses"
      "ncursesw" "ncurses"))
  (for/or ([name candidates])
    (with-handlers ([exn:fail? (lambda (_) #f)])
      (ffi-lib name #:fail #f))))

(define ncurses-lib
  (or (find-ncurses-lib)
      (error "ncurses library not found. Please install libncursesw-dev or equivalent.")))

;; ---------- 类型 ----------
(define _WINDOW _pointer)

;; ---------- FFI 绑定 ----------
(define-ffi-definer define-ncurses ncurses-lib)

;; 初始化与退出
(define-ncurses initscr     (_fun -> _WINDOW))
(define-ncurses endwin      (_fun -> _int))

;; 输出控制
(define-ncurses refresh     (_fun -> _int))
(define-ncurses wrefresh    (_fun _WINDOW -> _int))
(define-ncurses doupdate    (_fun -> _int))
(define-ncurses wnoutrefresh (_fun _WINDOW -> _int)) ;; 屏幕内存更新（不立即输出到终端）

;; 清屏
(define-ncurses clear       (_fun -> _int))
(define-ncurses wclear      (_fun _WINDOW -> _int))
(define-ncurses erase       (_fun -> _int))
(define-ncurses werase      (_fun _WINDOW -> _int))

;; 光标
(define-ncurses move        (_fun _int _int -> _int))
(define-ncurses wmove       (_fun _WINDOW _int _int -> _int))
(define-ncurses getcurx     (_fun _WINDOW -> _int))
(define-ncurses getcury     (_fun _WINDOW -> _int))
(define-ncurses curs_set    (_fun _int -> _int))

;; 输入模式
(define-ncurses noecho      (_fun -> _int))
(define-ncurses echo        (_fun -> _int))
(define-ncurses cbreak      (_fun -> _int))
(define-ncurses nocbreak    (_fun -> _int))
(define-ncurses raw         (_fun -> _int))
(define-ncurses noraw       (_fun -> _int))
(define-ncurses nodelay     (_fun _WINDOW _bool -> _int))
(define-ncurses keypad      (_fun _WINDOW _bool -> _int))

;; 字符/字符串输出
(define-ncurses addch       (_fun _int -> _int))
(define-ncurses waddch      (_fun _WINDOW _int -> _int))
(define-ncurses addstr      (_fun _string -> _int))
(define-ncurses waddstr     (_fun _WINDOW _string -> _int))
(define-ncurses mvaddch     (_fun _int _int _int -> _int))
(define-ncurses mvaddstr    (_fun _int _int _string -> _int))
(define-ncurses mvwaddch    (_fun _WINDOW _int _int _int -> _int))
(define-ncurses mvwaddstr   (_fun _WINDOW _int _int _string -> _int))
(define-ncurses addnstr     (_fun _bytes _int -> _int))
(define-ncurses waddnstr    (_fun _WINDOW _bytes _int -> _int))
(define-ncurses mvaddnstr   (_fun _int _int _bytes _int -> _int))
(define-ncurses mvwaddnstr  (_fun _WINDOW _int _int _bytes _int -> _int))

;; 插入字符
(define-ncurses insch     (_fun _int -> _int))
(define-ncurses winsch    (_fun _WINDOW _int -> _int))
(define-ncurses mvinsch   (_fun _int _int _int -> _int))
(define-ncurses mvwinsch  (_fun _WINDOW _int _int _int -> _int))

;; 清除到行尾/底部
(define-ncurses clrtoeol  (_fun -> _int))
(define-ncurses wclrtoeol (_fun _WINDOW -> _int))
(define-ncurses clrtobot  (_fun -> _int))
(define-ncurses wclrtobot (_fun _WINDOW -> _int))

;; 辅助反馈
(define-ncurses beep      (_fun -> _int))
(define-ncurses flash     (_fun -> _int))

;; 滚动
(define-ncurses scrollok  (_fun _WINDOW _bool -> _int))
(define-ncurses scroll    (_fun _WINDOW -> _int))

;; 属性
(define-ncurses attron      (_fun _int -> _int))
(define-ncurses attroff     (_fun _int -> _int))
(define-ncurses attrset     (_fun _int -> _int))
(define-ncurses standout    (_fun -> _int))
(define-ncurses standend    (_fun -> _int))
(define-ncurses wattron     (_fun _WINDOW _int -> _int))
(define-ncurses wattroff    (_fun _WINDOW _int -> _int))

;; 颜色
(define-ncurses has_colors  (_fun -> _int))
(define-ncurses start_color (_fun -> _int))
(define-ncurses init_pair   (_fun _short _short _short -> _int))
;; 注意：COLOR_PAIR 是宏，在color.rkt绑定
;; 真彩色支持（ncurses 6.1+）
(define-ncurses use_default_colors    (_fun -> _int))
(define-ncurses init_extended_color   (_fun _int _int _int _int -> _int)) ; color, r, g, b (0-1000)
(define-ncurses init_extended_pair    (_fun _int _int _int -> _int))       ; pair, fg, bg

;; 输入
(define-ncurses getch       (_fun -> _int))
(define-ncurses wgetch      (_fun _WINDOW -> _int))
(define-ncurses ungetch     (_fun _int -> _int))

;; 窗口
(define-ncurses newwin      (_fun _int _int _int _int -> _WINDOW))
(define-ncurses delwin      (_fun _WINDOW -> _int))
(define-ncurses subwin      (_fun _WINDOW _int _int _int _int -> _WINDOW))

;; 窗口尺寸
(define-ncurses getmaxy     (_fun _WINDOW -> _int))
(define-ncurses getmaxx     (_fun _WINDOW -> _int))

(define-ncurses timeout (_fun _int -> _int))

;;鼠标
(define-ncurses mousemask   (_fun _ulong _pointer -> _ulong))

(provide
  ;; 初始化与退出
  initscr endwin

  ;; 输出控制
  refresh wrefresh doupdate wnoutrefresh

  ;; 清屏
  clear wclear erase werase

  ;; 光标
  move wmove getcurx getcury curs_set

  ;; 输入模式
  noecho echo cbreak nocbreak raw noraw nodelay keypad

  ;; 字符/字符串输出
  addch waddch addstr waddstr
  mvaddch mvaddstr mvwaddch mvwaddstr
  addnstr waddnstr mvaddnstr mvwaddnstr

  ;; 插入字符
  insch winsch mvinsch mvwinsch

  ;; 清除到行尾/底部
  clrtoeol wclrtoeol clrtobot wclrtobot

  ;; 辅助反馈
  beep flash

  ;; 滚动
  scrollok scroll

  ;; 属性
  attron attroff attrset standout standend
  wattron wattroff

  ;; 颜色
  has_colors start_color init_pair
  use_default_colors
  init_extended_color
  init_extended_pair
  ;; 输入
  getch wgetch ungetch

  ;; 窗口
  newwin delwin subwin

  ;; 窗口尺寸
  getmaxy getmaxx

  ;; 超时
  timeout

  ;; 鼠标
  mousemask

  ;; 类型
  _WINDOW
)