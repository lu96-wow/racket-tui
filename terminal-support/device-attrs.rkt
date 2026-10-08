#lang racket

;; ════════════════════════════════════════════════════════════════
;; terminal-support/device-attrs.rkt —— 纯数据：设备属性码 ↔ 名称
;; 取自 xterm ctlseqs "Send Device Attributes (Primary/Secondary DA)"。
;; ════════════════════════════════════════════════════════════════

(provide da1-attr-names da1-attr-name
         da1-model-names da1-model-name
         da2-model-names da2-model-name)

;; DA1 回复里的能力码（首位 6x 是型号码，不在本表）
(define da1-attr-names
  '((1  . "132 columns")
    (2  . "printer")
    (3  . "ReGIS graphics")
    (4  . "Sixel graphics")
    (6  . "selective erase")
    (8  . "user-defined keys")
    (9  . "national replacement charsets")
    (15 . "technical characters")
    (16 . "locator port")
    (17 . "terminal state interrogation")
    (18 . "user windows")
    (21 . "horizontal scrolling")
    (22 . "ANSI color")
    (28 . "rectangular editing")
    (29 . "ANSI text locator")))

(define (da1-attr-name n)
  (cond [(assoc n da1-attr-names) => cdr] [else #f]))

;; DA1 首位：VT100 系 / VT2xx+ 的型号码（首位是这些值时，其后才是能力码）
(define da1-model-names
  '((1  . "VT100") (4 . "VT132") (6 . "VT102") (7 . "VT131")
    (12 . "VT125") (61 . "VT510?/VTE") (62 . "VT220") (63 . "VT320")
    (64 . "VT420") (65 . "VT510-525")))

(define (da1-model-name n)
  (cond [(assoc n da1-model-names) => cdr] [(>= n 60) "VT5xx?"] [else #f]))

;; DA2 回复的 Pp（终端类型码）
;; 注：VTE 报 61、tmux 报 84，皆非标准值（notcurses 注释亦提及 tmux 用 84）。
(define da2-model-names
  '((0  . "VT100")
    (1  . "VT220")
    (2  . "VT240/241")
    (18 . "VT330")
    (19 . "VT340")
    (24 . "VT320")
    (32 . "VT382")
    (41 . "VT420")
    (61 . "VT510?/VTE")
    (62 . "VT510")
    (63 . "VT510")
    (64 . "VT420")
    (65 . "VT510-525")
    (84 . "tmux")))

(define (da2-model-name n)
  (cond [(assoc n da2-model-names) => cdr] [else #f]))
