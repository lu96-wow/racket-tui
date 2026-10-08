#lang racket

;; ════════════════════════════════════════════════════════════════
;; terminal-support/groups.rkt —— 纯数据：查询分组 + profile
;;
;; 目的：不是所有终端都支持所有模式，全查是浪费。调用方按需选组。
;;   · private/ansi 组：DECRQM 要问哪些模式
;;   · special 组      ：非 DECRQM 的查询（身份、XTGETTCAP、kitty、颜色、尺寸）
;; ════════════════════════════════════════════════════════════════

(require racket/list)

(provide private-mode-groups ansi-mode-groups special-groups
         all-private-groups all-ansi-groups all-special-groups
         profile-groups default-profile
         group-private-modes group-ansi-modes group-special?)

;; ── DEC 私有模式分组（合起来 = modes.rkt 的全部 82 个）──
(define private-mode-groups
  '((mouse          . (1000 1002 1003 1006))                          ; 核心：按下/拖拽/移动/SGR
    (mouse-extra    . (9 1001 1005 1007 1010 1011 1014 1015 1016 8452))
    (keyboard       . (1 66 67))                                      ; DECCKM/DECNKM/DECBKM
    (keyboard-extra . (2 1034 1035 1036 1037 1039 1050 1051 1052 1053 1060 1061))
    (focus          . (1004))
    (cursor         . (12 13 14 25))
    (screen         . (3 40 47 80 95 1046 1047 1048 1049 7727))
    (paste          . (2004))
    (paste-extra    . (2005 2006))
    (sync           . (2026))
    (unicode        . (1020 1021 1022 1023 2027))
    (resize         . (2048))
    (selection      . (1040 1041 1042 1043 1044 1045))
    (readline       . (2001 2002 2003))
    (printing       . (18 19))
    (misc           . (4 5 6 7 8 10 30 35 38 41 42 43 44 45 46 69 9001))))

;; ── ANSI(非私有)模式分组 ──
(define ansi-mode-groups
  '((keyboard . (2 12))    ; KAM, SRM
    (editing  . (4 6 7))   ; IRM, ERM, VEM
    (output   . (20))))    ; LNM

;; ── 非 DECRQM 的查询组 ──
(define special-groups '(identity xtgettcap kitty colors sizes))
;;   identity   : DA1/DA2/DA3 + XTVERSION
;;   xtgettcap  : DCS +q 查 terminfo 能力
;;   kitty      : CSI ? u（+ 可选图形 APC）
;;   colors     : OSC 10/11/12 + OSC 4 调色板
;;   sizes      : XTWINOPS 18/14/16 t + DSR

(define all-private-groups (map car private-mode-groups))
(define all-ansi-groups    (map car ansi-mode-groups))
(define all-special-groups special-groups)

;; ── profile：一组组名 ──
(define profile-specs
  '((minimal  . (identity sizes cursor))
    (standard . (identity xtgettcap kitty sizes colors
                 cursor mouse paste screen focus sync keyboard))
    (full     . all)))   ; 'all 特殊标记
(define default-profile 'standard)

(define (profile-groups profile)
  (case profile
    [(full) (remove-duplicates (append all-private-groups all-ansi-groups all-special-groups))]
    [else
     (define spec (or (assoc profile profile-specs)
                      (error 'profile-groups "unknown profile: ~a" profile)))
     (cdr spec)]))

;; ── group → 模式列表（去重：同名组可能同时出现在 private/ansi 里）──
(define (group-private-modes groups)
  (remove-duplicates
   (apply append
          (for/list ([g (in-list groups)])
            (cond [(assoc g private-mode-groups) => cdr] [else '()])))))

(define (group-ansi-modes groups)
  (remove-duplicates
   (apply append
          (for/list ([g (in-list groups)])
            (cond [(assoc g ansi-mode-groups) => cdr] [else '()])))))

(define (group-special? groups g)
  (and (memq g groups) #t))
