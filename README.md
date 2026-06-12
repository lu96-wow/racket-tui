# Racket TUI Library

A terminal user interface library supporting mouse, touchpad, true color, bracketed paste, and window resize events.

## Remote Install

```bash
raco pkg install https://github.com/lu96-wow/racket-tui.git
```

![Demo](a.gif)

## Quick Start

```racket
#lang racket

(require tui)

;; Method 1: Direct output (immediately displayed)
(with-tui
  (screen-clear)
  (cursor-hide)
  (put-rgb-fg 255 100 0 "Hello TUI!")
  (put-at 5 10 "Direct output")
  (sleep 2))

;; Method 2: Batch output (collect then flush at once)
(with-tui
  (screen-clear)
  (define buffer
    (bytes-append
     (format-cursor-move 5 10)
     (format-rgb-fg 0 255 0 "Green text")
     (format-cursor-move 6 10)
     (format-256-fg 46 "Bright green")))
  (put-bytes buffer)  ;; flush once
  (sleep 2))
```

## Output System

### Immediate Output Functions (put- prefix)

Output directly to the terminal, displayed immediately:

```racket
;; Basic output
(put "Hello")
(put-string "text")
(put-bytes #"bytes")
(put-char #\A)
(put-byte 65)
(put-newline)

;; Cursor control
(cursor-up 1)
(cursor-down 1)
(cursor-left 1)
(cursor-right 1)
(cursor-move 5 10)
(cursor-col 20)
(cursor-home)
(cursor-hide)
(cursor-show)

;; Screen control
(screen-clear)
(screen-clear-below)
(screen-clear-above)
(line-clear)
(line-clear-right)
(line-clear-left)
(buffer-alt-enable)
(buffer-alt-disable)

;; Positioned output
(put-at 5 10 "Text")
(put-at! 5 10 "Text")
```

### Color Output (Immediate)

```racket
;; 16-color
(fg-red) (bg-blue)
(put-styled 'error "Error message")

;; True color (RGB)
(put-rgb-fg 255 100 0 "Orange text")
(put-rgb-bg 0 0 255 "Blue background")
(put-rgb-fg-bg 255 255 0 0 0 255 "Yellow text on blue background")

;; 256-color
(put-256-fg 46 "Bright green")
(put-256-bg 124 "Dark red background")

;; Positioned color output
(put-rgb-fg-at 5 10 255 128 0 "Orange text")
(put-rgb-fg-at! 5 10 255 128 0 "Orange text")
```

## Format Functions (format- prefix)

Return byte strings without outputting, used for batch collection:

```racket
(define my-buffer (bytes))

(set! my-buffer (bytes-append my-buffer (format-cursor-move 5 10)))
(set! my-buffer (bytes-append my-buffer (format-cursor-up 2)))
(set! my-buffer (bytes-append my-buffer (format-cursor-home)))

(set! my-buffer (bytes-append my-buffer (format-rgb-fg 255 0 0 "Red")))
(set! my-buffer (bytes-append my-buffer (format-rgb-bg 0 0 255 "Blue")))
(set! my-buffer (bytes-append my-buffer (format-256-fg 46 "Green")))
(set! my-buffer (bytes-append my-buffer (format-rgb-fg-bg 255 255 0 0 0 255 "Yellow/Blue")))

(set! my-buffer (bytes-append my-buffer format-screen-clear))
(set! my-buffer (bytes-append my-buffer format-cursor-hide))

(define style-bytes (call-with-output-bytes
                     (λ (out)
                       (parameterize ([current-output-port out])
                         (clr-red) (attr-bold)))))
(set! my-buffer (bytes-append my-buffer (format-styled style-bytes "Bold Red")))

(put-bytes my-buffer)
```

## Available Format Functions

| Function | Description | Equivalent Output Function |
|------|------|--------------|
| (format-cursor-move row col) | Move cursor | cursor-move |
| (format-cursor-up n) | Cursor up | cursor-up |
| (format-cursor-down n) | Cursor down | cursor-down |
| (format-cursor-left n) | Cursor left | cursor-left |
| (format-cursor-right n) | Cursor right | cursor-right |
| (format-cursor-col n) | Move to column | cursor-col |
| format-cursor-home | Home position | cursor-home |
| format-cursor-hide | Hide cursor | cursor-hide |
| format-cursor-show | Show cursor | cursor-show |
| format-screen-clear | Clear screen | screen-clear |
| format-screen-clear-below | Clear below | screen-clear-below |
| format-screen-clear-above | Clear above | screen-clear-above |
| format-line-clear | Clear line | line-clear |
| format-line-clear-right | Clear right | line-clear-right |
| format-line-clear-left | Clear left | line-clear-left |
| format-buffer-alt-enable | Enable alt buffer | buffer-alt-enable |
| format-buffer-alt-disable | Disable alt buffer | buffer-alt-disable |
| format-reset | Reset styling | style-reset |
| (format-rgb-fg r g b v) | RGB foreground | put-rgb-fg |
| (format-rgb-bg r g b v) | RGB background | put-rgb-bg |
| (format-rgb-fg-bg fr fg fb br bg bb v) | RGB foreground & background | put-rgb-fg-bg |
| (format-256-fg n v) | 256 foreground | put-256-fg |
| (format-256-bg n v) | 256 background | put-256-bg |
| (format-styled style-bytes v) | Styled text | put-styled |

## Style System

```racket
(style-define! 'fancy clr-yellow bclr-blue attr-bold attr-underline)

(put-styled 'fancy "Combined style")

(define fancy-bytes
  (call-with-output-bytes
   (λ (out)
     (parameterize ([current-output-port out])
       (style-apply! 'fancy)))))

(define styled-text (format-styled fancy-bytes "Styled text"))
```

## Input Design

`build-input` is the recommended high-level event dispatch API, simplifying event handling via callback functions.
It encapsulates the event classification logic of the underlying `read-event`, so you only need to declare "what function to call when event X occurs".

### Recommended: build-input

Use `build-input` directly after `(require tui)` — no extra require needed:

```racket
(require tui)

(define handler
  (build-input
    #:char      (lambda (ch) (printf "Key: ~a\n" (integer->char ch)))
    #:up        (lambda ()  (cursor-up 1))
    #:down      (lambda ()  (cursor-down 1))
    #:left      (lambda ()  (cursor-left 1))
    #:right     (lambda ()  (cursor-right 1))
    #:resize    (lambda (rows cols) (printf "Window: ~ax~a\n" rows cols))
    #:mouse-press (lambda (btn x y mods) (printf "Mouse press ~a (~a,~a)\n" btn x y))
    #:any       (lambda (type data mods) (printf "Unhandled: ~a\n" type))))

;; Use in event loop
(let loop ()
  (let-values ([(type data mods) (read-event)])
    (handler type data mods)
    (loop)))
```

All keyword arguments are optional. Supported events:

| Argument | Callback Signature | Description |
|----------|-------------------|-------------|
| `#:char` | `(lambda (ch) ...)` | Regular key, ch is the ASCII value |
| `#:utf-char` | `(lambda (str) ...)` | UTF-8 character |
| `#:ctrl` | `(lambda (ch) ...)` | Ctrl+letter, ch is `#\A`-`#\Z` |
| `#:alt` | `(lambda (ch) ...)` | Alt+letter |
| `#:mod` | `(lambda (ch ctrl? alt?) ...)` | Ctrl+Alt+combination |
| `#:tab` / `#:space` / `#:enter` / `#:backspace` / `#:escape` | `(lambda () ...)` | Special keys |
| `#:up` / `#:down` / `#:left` / `#:right` | `(lambda () ...)` | Arrow keys |
| `#:delete` / `#:insert` / `#:home` / `#:end` / `#:pageup` / `#:pagedown` | `(lambda () ...)` | Function keys |
| `#:mouse-press` | `(lambda (button x y modifiers) ...)` | Mouse press, button is `'left`/`'middle`/`'right` |
| `#:mouse-release` | `(lambda (button x y modifiers) ...)` | Mouse release |
| `#:mouse-move` | `(lambda (x y modifiers) ...)` | Mouse move |
| `#:mouse-scroll` | `(lambda (dir x y modifiers) ...)` | Scroll wheel, dir is `'up`/`'down` |
| `#:paste` | `(lambda (data) ...)` | Bracketed paste, data is bytes |
| `#:resize` | `(lambda (rows cols) ...)` | Window resize |
| `#:null` | `(lambda () ...)` | No input event |
| `#:any` | `(lambda (type data mods) ...)` | Fallback callback |

Priority order (built-in, users don't need to worry): `null > resize > paste > mouse > tab/space/enter/backspace/escape > arrow keys > function keys > ctrl > alt > mod > utf8 > char > any`

### Low-level API (input.rkt)

If you need finer-grained control over event types, you can also use the low-level `read-event` and event predicate functions directly:

```racket
(require tui)

(let-values ([(type data mods) (read-event)])
  (cond
    [(event-touch? type)
     (let-values ([(x y) (get-mouse-pos data)])
       (printf "Mouse ~a,~a" x y))]
    [(event-up? type) (cursor-up 1)]
    [(event-ctrl? type) (printf "Ctrl+~a" (ctrl->char data))]
    [(event-utf8? type) (printf "UTF-8: ~a" (event->string data))]
    [(event-resize? type)
     (printf "~a×~a" (get-resize-rows data) (get-resize-cols data))]
    [(event-paste? type)
     (printf "Pasted: ~a bytes" (bytes-length data))]))
```

## Lifecycle Management

```racket
(with-tui
  (screen-clear)
  (put "Hello")
  (read-event))

(tui-init)
(tui-exit)

(with-tui-nobuffer
  (put "Output in main buffer"))
```

## Buffer

```racket
#lang racket
(require tui)

(with-tui-nobuffer
    (define buffer-content
      (list
       format-screen-clear
       (format-cursor-move 0 0)
       (format-rgb-fg 255 255 0 "=== Demo ===")
       (format-cursor-move 2 0)
       (format-rgb-fg 0 255 0 "Line 1")
       (format-cursor-move 3 0)
       (format-rgb-fg 0 255 0 "Line 2")
       (format-cursor-move 4 0)
       (format-rgb-fg 0 255 0 "Line 3")))

  ;; Concatenate all byte strings
  (define screen (apply bytes-append buffer-content))

  ;; Output all at once
  (put-bytes screen))
```

## Complete Example

```racket
#lang racket

(require tui)

(define (draw-ui)
  (define buffer
    (bytes-append
     format-screen-clear
     (format-cursor-move 0 0)
     (format-rgb-fg 255 255 0 "=== TUI Demo ===")
     (format-cursor-move 2 0)
     (format-rgb-fg 0 255 0 "Press 'q' to quit")
     (format-cursor-move 4 0)
     (format-rgb-fg 255 0 0 "Hello, TUI!")
     (format-cursor-move 6 0)
     (format-256-fg 46 "UTF-8 support: 你好世界")))
  (put-bytes buffer))

(with-tui
    (cursor-hide)
  (define handler
    (build-input
      #:char (lambda (ch)
               (when (= ch (char->integer #\q))
                 (exit)))))  ;; press q to quit
  (let loop ()
    (draw-ui)
    (let-values ([(type data mods) (read-event)])
      (handler type data mods)
      (loop))))
```

More examples can be found in the `test/` directory.

## Flush Mode

```racket
(set-immediate-mode!)    ;; put- functions flush immediately (default)
(set-buffered-mode!)     ;; put- functions buffer output
(flush)                  ;; Manual flush
```

## Prefix / Suffix Conventions

| Prefix | Meaning | Example |
|--------|---------|---------|
| `put-` | Immediate terminal output | `put`, `put-string` |
| `format-` | Return byte string, for use with `put-bytes` | `format-cursor-move` |
| `clr-` | Color setting (16-color) | `clr-red` |
| `attr-` | Attribute setting | `attr-bold` |

| Suffix | Meaning | Example |
|--------|---------|---------|
| `!` | Has side effects (changes cursor position) | `put-at!`, `style-define!` |
| `?` | Predicate, returns boolean | `event-key?`, `terminal?` |
| `-at` | Positioned parameter | `put-at`, `cursor-move` |
| `-at!` | Positioned parameter + side effects | `put-at!` |

> Note: Only tested in xterm / qterminal.