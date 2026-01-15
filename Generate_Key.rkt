#lang racket

;; Generate_Key.rkt —— 生成 key_data.rkt：
;;   - 定义 KEY_XXX 常量（如 KEY_UP = 259）
;;   - 生成 KEYCODE->SYMBOL : 整数 → 符号（如 259 → up）

(require racket/file
         racket/string)

;; ========== 搜索头文件路径 ==========
(define CANDIDATE-PATHS
  '("/usr/include/ncursesw/curses.h"
    "/usr/include/ncursesw/ncurses.h"
    "/usr/include/ncurses/curses.h"
    "/usr/include/ncurses/ncurses.h"
    "/usr/include/curses.h"
    "/usr/include/ncurses.h"
    "/opt/homebrew/include/ncursesw/curses.h"
    "/opt/homebrew/include/curses.h"
    "/usr/local/include/ncursesw/curses.h"
    "/usr/local/include/curses.h"
    "/usr/local/include/ncurses/ncurses.h"))

(define (find-curses-header)
  (for/or ([path CANDIDATE-PATHS])
    (and (file-exists? path) path)))

;; ========== 主流程 ==========
(define header-path (find-curses-header))

(unless header-path
  (eprintf "错误：未找到 curses.h 或 ncurses.h\n")
  (eprintf "请安装开发包，例如：\n")
  (eprintf "  Ubuntu/Debian/Kali: sudo apt install libncursesw5-dev\n")
  (eprintf "  Fedora/RHEL:        sudo dnf install ncurses-devel\n")
  (eprintf "  Arch:               sudo pacman -S ncurses\n")
  (eprintf "  macOS (Homebrew):   brew install ncurses\n")
  (exit 1))

(printf "找到头文件: ~a\n" header-path)

;; ========== 解析纯 KEY_ 常量 ==========
(define key-values (make-hash))

(for ([line (file->lines header-path)])
  (define m (regexp-match #px"^#define\\s+(KEY_[A-Z0-9_]+)\\s+0([0-7]+)" line))
  (when m
    (define name (second m))
    (define oct-digits (third m))
    (define dec-val (string->number oct-digits 8))
    (hash-set! key-values name dec-val)))

;; 补全 F1–F12（如果 KEY_F0 存在）
(define KEY_F0 (hash-ref key-values "KEY_F0" #f))
(when KEY_F0
  (for ([i (in-range 1 13)])
    (hash-set! key-values (format "KEY_F~a" i) (+ KEY_F0 i))))

;; ========== 辅助：C 名称转目标符号（KEY_UP → up）==========
(define (key-name->symbol c-name)
  (cond
    ;; 特殊映射（可选，但通常不需要，因为 KEY_DC/IC 已被包含）
    [(string=? c-name "KEY_BACKSPACE") 'backspace]
    [(string=? c-name "KEY_ENTER")     'enter]
    [(string=? c-name "KEY_DC")        'delete]
    [(string=? c-name "KEY_IC")        'insert]
    ;; 通用规则：去掉 KEY_，转小写
    [(string-prefix? c-name "KEY_")
     (string->symbol
      (string-downcase (substring c-name 4)))]
    [else #f]))

;; 收集 (value . symbol) 对
(define value->symbol-pairs
  (for/list ([(c-name val) (in-hash key-values)]
             #:when (string-prefix? c-name "KEY_"))
    (define sym (key-name->symbol c-name))
    (cons val sym)))

;; 去重（理论上不会重复，但安全起见）
(define unique-pairs
  (remove-duplicates value->symbol-pairs #:key car))

;; 按值排序（可读性）
(define sorted-pairs
  (sort unique-pairs < #:key car))

;; ========== 写入 key_data.rkt ==========
(define out (open-output-file "key_data.rkt" #:exists 'replace))
(parameterize ([current-output-port out])
  (printf "#lang racket\n")
  (printf ";; 自动生成自: ~a\n" header-path)
  (printf ";; 包含 KEY_XXX 常量 和 keycode → symbol 的映射\n\n")

  ;; 1. 输出 (define KEY_XXX value)
  (define bindings
    (for/list ([(c-name val) (in-hash key-values)]
               #:when (string-prefix? c-name "KEY_"))
      (cons (string->symbol c-name) val)))
  (define sorted-bindings
    (sort bindings symbol<? #:key car))
  (for ([b sorted-bindings])
    (printf "(define ~a ~a)\n" (car b) (cdr b)))

  (newline)

  ;; 2. 输出 KEYCODE->SYMBOL 哈希表：整数 → 符号
  (printf "(define KEYCODE->SYMBOL\n  #hash(")
  (for ([pair (in-list sorted-pairs)]
        [i (in-naturals)])
    (when (> i 0) (printf "                      "))
    (printf "(~a . ~a)" (car pair) (cdr pair))
    (unless (= i (- (length sorted-pairs) 1))
      (printf "\n")))
  (printf "))\n\n")

  (printf "(provide (all-defined-out))"))
(close-output-port out)

(printf "已生成 key_data.rkt(共 ~a 个 keycode 映射）\n" (length sorted-pairs))