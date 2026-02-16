#lang racket

(require "lib.rkt"
         "lib_help.rkt")

;; 配置
(define START_COLOR_ID 100)
(define START_PAIR_ID 100)

;; 状态
(define color-name->id (make-hash))
(define pair-name->id (make-hash))
(define next-color-id START_COLOR_ID)
(define next-pair-id START_PAIR_ID)

;; 定义颜色
(define (define-color name r g b)
  
  (when (hash-has-key? color-name->id name)
    (error "颜色已定义" name))
  
  (define max-colors (help_get_COLORS))
  (when (>= next-color-id max-colors)
    (error (format "颜色 ID ~a 超出上限（最大有效 ID: ~a)"
                   next-color-id (sub1 max-colors))))
  
  (init_extended_color next-color-id r g b)
  (hash-set! color-name->id name next-color-id)
  (set! next-color-id (add1 next-color-id))
  (void))

;; 定义颜色对
(define (define-color-pair name fg bg)

  ;; 判断 fg 和 bg 是颜色名称还是标准颜色 ID
  (define (resolve-color color)
    (cond
      [(symbol? color)
       (or (hash-ref color-name->id color #f)
           (error "颜色未定义" color))]
      [(and (integer? color) (>= color 0))
       color]
      [else (error "无效的颜色标识符" color)]))

  (define fg-id (resolve-color fg))
  (define bg-id (resolve-color bg))

  (when (hash-has-key? pair-name->id name)
    (error "颜色对已定义" name))

  (define max-pairs (help_get_COLOR_PAIRS))
  (when (>= next-pair-id max-pairs)
    (error (format "颜色对 ID ~a 超出上限（最大有效 ID: ~a)"
                   next-pair-id (sub1 max-pairs))))

  ;; 根据颜色 ID 的类型选择使用 init_pair 或 init_extended_pair
  (if (and (<= 0 fg-id (sub1 (help_get_COLORS))) 
           (<= 0 bg-id (sub1 (help_get_COLORS))))
      ;; 使用标准颜色
      (init_pair next-pair-id fg-id bg-id)
      ;; 使用扩展颜色
      (init_extended_pair next-pair-id fg-id bg-id))

  (hash-set! pair-name->id name next-pair-id)
  (set! next-pair-id (add1 next-pair-id))
  (void))

;; 查询函数

(define (color-id name)
  (hash-ref color-name->id name #f))

(define (pair-id name)
  (hash-ref pair-name->id name #f))
 
(define (pair pair-name)
         (help_COLOR_PAIR (pair-id pair-name)))

(define (pair-attr pair-name . attrs)
  (apply bitwise-ior 
         (help_COLOR_PAIR (pair-id pair-name))
         attrs))

;; 导出
(provide
 define-color
 define-color-pair
 color-id
 pair-id
 pair-attr
 pair)