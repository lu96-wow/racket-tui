#lang racket

;; build-base.rkt — 编译 dump-termios.c, 运行获取架构常量, 生成 base/base.rkt

(define src  "dump-termios.c")
(define exe  "dump-termios")
(define tmpl "base.rkt.template")
(define out  "../base.rkt")

;; 切换到脚本所在目录
(current-directory
 (path-only (normalize-path (find-system-path 'run-file))))

;; 1. 编译 C 程序
(printf "cc ~a -o ~a ...\n" src exe)
(void (system (format "cc ~a -o ~a" src exe)))

;; 2. 运行 C 程序, 解析输出 (通过临时文件)
(printf "./~a ...\n" exe)
(define tmp-out "dump-termios.out")
(void (system (format "./~a > ~a" exe tmp-out)))
(define values (make-hash))
(for ([line (in-lines (open-input-file tmp-out))])
  (define parts (regexp-split #rx" " line))
  (when (= (length parts) 2)
    (hash-set! values (car parts) (cadr parts))))
(delete-file tmp-out)

;; 3. 验证必须的键
(for ([key '("TERMIOS-SIZE" "IFLAG-OFFSET" "OFLAG-OFFSET" "LFLAG-OFFSET"
             "CC-OFFSET" "VMIN" "VTIME" "TCSAFLUSH"
             "ICANON" "ECHO" "ISIG" "IEXTEN"
             "IXON" "OPOST" "ICRNL" "INLCR" "IGNCR" "OCRNL" "ONLCR")])
  (unless (hash-has-key? values key)
    (error "build-base: missing key ~a" key)))

;; 4. 读取模板, 替换占位符, 写入 base.rkt
(define content (file->string tmpl))
(for ([(key val) (in-hash values)])
  (set! content (string-replace content (format "@~a@" key) val)))

;; 验证没有残留占位符
(when (regexp-match #rx"@[A-Z-]+@" content)
  (printf "Warning: unresolved placeholders remain\n"))

(display-to-file content out #:exists 'replace)
(printf "Wrote ~a\n" out)

;; 5. 清理
(delete-file exe)
