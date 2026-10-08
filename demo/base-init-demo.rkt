#lang racket

;; ════════════════════════════════════════════════════════════════
;; demo/base-init-demo.rkt —— 手动验证 base 的能力门控 init（需要真实 tty）
;;
;;   racket demo/base-init-demo.rkt
;;
;; 进入 TUI：打印探测得到的 features，按任意键退出。
;; 观察点：
;;   · 支持 1049 才切 alt 屏；不支持则留在主屏
;;   · 支持 1006 才开鼠标；支持 2004 才开括号粘贴
;;   · 色深由探测决定（不再读 $TERM）
;; ════════════════════════════════════════════════════════════════

(require "../base/main.rkt")

(define (say s) (put-string (string-append s "\r\n")) (flush!))

(with-tui
 (λ ()
   (define f (current-features))
   (say "base init-demo")
   (say (format "  color        : ~a" (features-color f)))
   (say (format "  mouse?       : ~a" (features-mouse? f)))
   (say (format "  paste?       : ~a" (features-paste? f)))
   (say (format "  alt-screen?  : ~a" (features-alt-screen? f)))
   (say (format "  kitty-keys?  : ~a" (features-kitty-keys? f)))
   (say (format "  sync?        : ~a" (features-sync? f)))
   (say "")
   (say "按任意键退出…")
   (read-event)))
