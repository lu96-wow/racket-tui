#lang racket

(require racket/system
         racket/port
         racket/match
         tui)

;; =========================
;; ffmpeg
;; =========================
(define (open-ffmpeg path width height fps)
  (define cmd
    (format
     "ffmpeg -loglevel error -i ~a \
      -vf \"scale=~a:~a:force_original_aspect_ratio=decrease,fps=~a,\
pad=~a:~a:(ow-iw)/2:(oh-ih)/2\" \
      -f rawvideo -pix_fmt rgb24 -"
     path width height fps width height))
  (match (process cmd)
    [(list stdout stdin pid stderr control)
     (values control stdin stdout stderr)]))

;; =========================
;; frame
;; =========================
(define (read-frame in size)
  (define bs (read-bytes size in))
  (and bs (= (bytes-length bs) size) bs))

;; =========================
;; pixel
;; =========================
(define (pixel bs w x y)
  (define i (* (+ x (* y w)) 3))
  (values (bytes-ref bs i)
          (bytes-ref bs (+ i 1))
          (bytes-ref bs (+ i 2))))

;; =========================
;; render（核心优化）
;; =========================
(define (draw-frame bs w h)
  (define out (open-output-bytes))

  ;; 一帧只做一次 clear/home
  (write-bytes format-cursor-home out)
  (write-bytes format-reset out)

  (for ([y (in-range 0 h 2)])
    (for ([x (in-range w)])

      (define-values (r1 g1 b1) (pixel bs w x y))
      (define-values (r2 g2 b2)
        (if (< (+ y 1) h)
            (pixel bs w x (+ y 1))
            (values 0 0 0)))

      ;; 使用你的 API（关键升级点）
      (write-bytes
       (format-rgb-fg-bg-at!
        (quotient y 2) x
        r1 g1 b1
        r2 g2 b2
        "▀")
       out))

    (write-bytes #"\n" out))

  (put-bytes (get-output-bytes out))
  (flush!))

;; =========================
;; main（mini mpv core）
;; =========================
(define (main path)
  (with-tui
      (cursor-hide)
    (screen-clear)

    (define fps 15) ; ⭐ 控制帧率核心

    ;; terminal size
    (define-values (rows cols) (get-window-size))

    (define width cols)
    (define height (* rows 2))

    (define-values (proc in out err)
      (open-ffmpeg path width height fps))

    ;; avoid stderr block
    (thread (λ () (copy-port err (current-error-port))))

    (define frame-size (* width height 3))

    ;; =========================
    ;; mpv-like loop
    ;; =========================
    (let loop ()
      (define t0 (current-inexact-milliseconds))

      (define frame (read-frame out frame-size))
      (when frame
        (draw-frame frame width height))

      ;; ⭐ FPS limiter
      (define dt (- (current-inexact-milliseconds) t0))
      (define frame-time (/ 1000 fps))
      (define wait (max 0 (- frame-time dt)))

      (sleep (/ wait 1000.0))

      (loop))

    (cursor-show)))

(module+ main
  (main "/home/debian/下载/test.mp4.test"))