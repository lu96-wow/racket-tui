#lang racket

;; 平台 / 环境识别（纯 Racket，无 FFI，可在任何平台 require）。
;; 与 base/terminal/platform.rkt 同名同实现 —— char 后端保持同 API。

(provide android? termux? termux-home termux-prefix)

;; Android：Racket BC 在 __ANDROID__ 下把 (system-type 'os*) 报成 'android
;; （src/bc/sconfig.h 的 SCHEME_OS "android" 分支）；Racket CS 则报 'linux。
(define (android?)
  (eq? 'android (system-type 'os*)))

;; Termux：termux-app 注入 TERMUX_VERSION / TERMUX_APP__PACKAGE_NAME，
;; 并把 HOME / PREFIX 指向 /data/data/<pkg>/files/home|usr，故 os* 识别不到时
;; 也能靠环境变量判定。
(define (env-has-termux-pkg? name)
  (define v (getenv name))
  (and v (regexp-match? #rx"com[.]termux" v) #t))

(define (termux?)
  (if (or (getenv "TERMUX_VERSION")
          (getenv "TERMUX_APP__PACKAGE_NAME")
          (env-has-termux-pkg? "PREFIX")
          (env-has-termux-pkg? "HOME"))
      #t #f))

;; Termux 下的可写目录（放配置 / 临时文件用）；非 Termux 返回 #f。
;; 注意：它们不能替代 /proc —— 内核态信号/进程信息只在 procfs 里。
(define (termux-home)   (and (termux?) (getenv "HOME")))
(define (termux-prefix) (and (termux?) (getenv "PREFIX")))
