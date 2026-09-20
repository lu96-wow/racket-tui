#lang racket

;; 复用 base 的输入超时/上限常量（纯数据，无副作用）

(require (only-in "../../base/terminal/config.rkt"
                  ESCDELAY CSI-MAX-BYTES PASTE-MAX-BYTES
                  UTF8-READ-TIMEOUT PASTE-READ-TIMEOUT))

(provide ESCDELAY CSI-MAX-BYTES PASTE-MAX-BYTES
         UTF8-READ-TIMEOUT PASTE-READ-TIMEOUT)
