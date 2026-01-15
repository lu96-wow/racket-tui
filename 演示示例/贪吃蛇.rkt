#lang racket

(require "../lib_extern.rkt"
         "../lib.rkt"
         "../key.rkt"
         "../mouse.rkt"
         "../color.rkt")

;; 辅助函数：生成 [0, n) 范围内的随机整数（n > 0）
(define (random-in-range n)
  (if (<= n 1)
      0
      (random n)))

;; 主游戏函数
(define (run-snake-game)
  (with-ncurses-stdscr #:timeout 0
    (lambda (win)
      (curs_set 0)

      ;; 初始化颜色（只在支持时定义）
      (when (has_colors)
        (define-color 'red 1000 0 0)
        (define-color 'green 0 1000 0)
        (define-color 'black 0 0 0)
        (define-color-pair 'snake 'green 'black)
        (define-color-pair 'food 'red 'black))

      ;; 初始尺寸
      (define width (getmaxx win))
      (define height (getmaxy win))

      ;; 初始蛇（居中）
      (define init-y (quotient height 2))
      (define init-x (quotient width 2))
      (define snake (list (cons init-y init-x)))
      (define direction '(0 . 1)) ; 向右
      (define food (cons (random-in-range height) (random-in-range width)))
      (define running? #t)
      (define blink-state #f)

      ;; 确保食物在 [0, height) × [0, width) 范围内
      (define (ensure-food-in-bounds)
        (set! food (cons (random-in-range height)
                         (random-in-range width))))

      ;; 绘制单个对象
      (define (draw-object obj char color-pair-name)
        (let ([y (car obj)]
              [x (cdr obj)])
          (when (and (<= 0 y (- height 1))
                     (<= 0 x (- width 1)))
            (if (has_colors)
                (mvwaddstr/xy win x y (string char) (pair-attr color-pair-name))
                (mvwaddch win y x (char->integer char))))))

      ;; 绘制整个游戏画面
      (define (draw-game)
        (clear)
        ;; 蛇身
        (for-each (lambda (part) (draw-object part #\* 'snake)) snake)
        ;; 食物（闪烁）
        (draw-object food #\O (if blink-state 'food 'snake))
        (refresh))

      ;; 处理输入
      (define (handle-input)
        (define key (get-key))
        (cond
          [(eq? key 'up)     (set! direction '(-1 . 0))]
          [(eq? key 'down)   (set! direction '(1 . 0))]
          [(eq? key 'left)   (set! direction '(0 . -1))]
          [(eq? key 'right)  (set! direction '(0 . 1))]
          [(eq? key 'esc)    (set! running? #f)]
          [(eq? key 'resize)
           ;; 更新尺寸并确保食物在新窗口内
           (set! height (getmaxy win))
           (set! width (getmaxx win))
           (ensure-food-in-bounds)
           (draw-game)]
          [(eq? key 'mouse)
           (with-handlers ([exn:fail? void])
             (get-mouse-event))]
          [else void]))

      ;; 更新游戏逻辑
      (define (update-game)
        (define head-y (caar snake))
        (define head-x (cdar snake))
        (define dy (car direction))
        (define dx (cdr direction))
        (define new-head (cons (+ head-y dy) (+ head-x dx)))

        ;; 检测碰撞（边界或自身）
        (when (or (< (car new-head) 0)
                  (>= (car new-head) height)
                  (< (cdr new-head) 0)
                  (>= (cdr new-head) width)
                  (member new-head (cdr snake)))
          (set! running? #f))

        ;; 移动蛇
        (set! snake (cons new-head snake))

        ;; 检查是否吃到食物
        (if (equal? new-head food)
            (begin
              (ensure-food-in-bounds))  ; 生成新食物（已在边界内）
            (set! snake (reverse (cdr (reverse snake))))) ; 删除尾部

        (set! blink-state (not blink-state)))

      ;; 主循环
      (let loop ()
        (when running?
          (handle-input)
          (update-game)
          (draw-game)
          (sleep 0.2)
          (loop)))

      ;; 注意：此处自然返回，触发 endwin
      ))

  ;; 在普通终端打印结束信息（此时 ncurses 已关闭）
  (displayln "Game over. Thanks for playing!"))

;; 启动游戏
(run-snake-game)