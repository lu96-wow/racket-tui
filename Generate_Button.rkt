#lang racket

;; Generate_Button.rkt —— 生成 button_data.rkt
;; 模拟 ncurses 的 NCURSES_MOUSE_MASK 宏，计算 BUTTON 常量

(require racket/file
         racket/string
         racket/port)

;; ========== 头文件路径 ==========
(define CANDIDATE-PATHS
  '("/usr/include/ncursesw/curses.h"
    "/usr/include/ncursesw/mouse.h"
    "/usr/include/ncurses/curses.h"
    "/usr/include/ncurses/mouse.h"
    "/usr/include/curses.h"
    "/opt/homebrew/include/ncursesw/curses.h"
    "/opt/homebrew/include/ncursesw/mouse.h"
    "/usr/local/include/ncursesw/curses.h"))

(define (find-header)
  (for/or ([p CANDIDATE-PATHS])
    (and (file-exists? p) p)))

(define header (find-header))
(unless header
  (eprintf "错误：未找到 curses.h 或 mouse.h\n")
  (exit 1))

(printf "使用头文件: ~a\n" header)

;; ========== 辅助：解析 C 数字字面量（支持 L/l 后缀）==========
(define (parse-c-literal str)
  (define s (string-trim (regexp-replace #px"[lL]$" str ""))) ; 移除末尾 L/l
  (cond
    [(string-prefix? s "0x") (string->number (substring s 2) 16)]
    [(and (> (string-length s) 1) (string-prefix? s "0")) (string->number s 8)]
    [else (string->number s 10)]))

;; ========== 第一步：收集所有简单 #define ==========
(define simple-defs (make-hash)) ; name -> number

(for ([line (file->lines header)])
  ;; 匹配 #define NAME value（value 是纯数字字面量，可能带 L）
  (define m (regexp-match #px"^#define\\s+([A-Z_][A-Z0-9_]*)\\s+(0x[0-9a-fA-F]+|0[0-7]*|[1-9][0-9]*)[lL]?" line))
  (when m
    (define name (second m))
    (define val-str (third m))
    (define val (parse-c-literal val-str))
    (when val
      (hash-set! simple-defs name val))))

;; ========== 第二步：确定 shift（5 or 6）==========
;; 默认假设 version > 1 → shift = 5（几乎所有现代系统都是如此）
(define shift 5)
(printf "使用 NCURSES_MOUSE_MASK shift = ~a\n" shift)

;; ========== 第三步：宏展开函数 ==========
(define (expand-NCURSES_MOUSE_MASK b m)
  (arithmetic-shift m (* (- b 1) shift)))

;; ========== 第四步：收集 BUTTON 宏（通用模式）==========
(define button-defs (make-hash))

;; 模式1: #define BUTTON... NCURSES_MOUSE_MASK(b, SYMBOL)
(for ([line (file->lines header)])
  (define m (regexp-match #px"^#define\\s+(BUTTON[A-Z0-9_]+)\\s+NCURSES_MOUSE_MASK\\s*\\(\\s*([0-9]+)\\s*,\\s*([A-Z_][A-Z0-9_]*)\\s*\\)" line))
  (when m
    (define btn-name (second m))
    (define b (string->number (third m)))
    (define base-name (fourth m))
    (define base-val (hash-ref simple-defs base-name #f))
    (when base-val
      (define final-val (expand-NCURSES_MOUSE_MASK b base-val))
      (hash-set! button-defs btn-name final-val))))

;; 模式2: #define BUTTON... NCURSES_MOUSE_MASK(b, literal)  ← 用于 BUTTON_CTRL 等
(for ([line (file->lines header)])
  (define m (regexp-match #px"^#define\\s+(BUTTON_CTRL|BUTTON_SHIFT|BUTTON_ALT|REPORT_MOUSE_POSITION)\\s+NCURSES_MOUSE_MASK\\s*\\(\\s*([0-9]+)\\s*,\\s*(0x[0-9a-fA-F]+|0[0-7]+|[0-9]+)[lL]?\\s*\\)" line))
  (when m
    (define btn-name (second m))
    (define b (string->number (third m)))
    (define lit-str (fourth m))
    (define base-val (parse-c-literal lit-str))
    (when base-val
      (define final-val (expand-NCURSES_MOUSE_MASK b base-val))
      (hash-set! button-defs btn-name final-val))))

;; ========== 特殊处理 ALL_MOUSE_EVENTS ==========
;; #define ALL_MOUSE_EVENTS (REPORT_MOUSE_POSITION - 1)
(define report-pos (hash-ref button-defs 'REPORT_MOUSE_POSITION #f))
(when report-pos
  (hash-set! button-defs 'ALL_MOUSE_EVENTS (- report-pos 1)))

;; ========== 排序输出 ==========
(define sorted-button-defs
  (sort (hash->list button-defs) string<? #:key car))

;; ========== 写入 button_data.rkt ==========
(define out-path "button_data.rkt")
(define out (open-output-file out-path #:exists 'replace))
(parameterize ([current-output-port out])
  (printf "#lang racket\n")
  (printf ";; 自动生成自: ~a\n" header)
  (printf ";; 模拟 NCURSES_MOUSE_MASK 宏计算 BUTTON 常量\n\n")

  (for ([pair sorted-button-defs])
    (printf "(define ~a ~a)\n" (car pair) (cdr pair)))

  (newline)
  (printf "(provide (all-defined-out))"))

(close-output-port out)

(printf "已生成 ~a(共 ~a 个 BUTTON 常量）\n"
        out-path (length sorted-button-defs))