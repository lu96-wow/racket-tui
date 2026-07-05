# racket-tui

A terminal UI library for Racket — mouse, true color, bracketed paste, window resize.

![Demo](a.gif)

## Install

```bash
raco pkg install https://github.com/lu96-wow/racket-tui.git
```

包名由 `info.rkt` 指定为 `tui`，安装后：

```racket
(require tui)
```

## Uninstall

```bash
raco pkg uninstall racket-tui
```

## Development

```bash
git clone https://github.com/lu96-wow/racket-tui.git
cd racket-tui
raco pkg install --link
```

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

;; Method 2: Batch output with put-format-bytes (auto collect + flush)
;; format-reset only needs to be called once at the end
(with-tui
  (screen-clear)
  (put-format-bytes
   (format-cursor-move 5 10)
   (format-rgb-fg 0 255 0) #"Green text"
   (format-cursor-move 6 10)
   (format-256-fg 46) #"Bright green"
   format-reset)
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
;; Use put-format-bytes for one-shot collection + output
;; format-reset only needed once at the end
(put-format-bytes
 format-screen-clear
 format-cursor-hide
 (format-cursor-move 5 10)
 (format-cursor-up 2)
 (format-cursor-home)

 (format-rgb-fg 255 0 0) #"Red"
 (format-rgb-bg 0 0 255) #"Blue"
 (format-256-fg 46) #"Green"
 (format-rgb-fg-bg 255 255 0 0 0 255) #"Yellow/Blue"

 (format-styled (style->bytes 'error) "Bold Red")
 format-reset)
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
| (format-rgb-fg r g b v) | RGB foreground bytes | put-rgb-fg |
| (format-rgb-bg r g b v) | RGB background bytes | put-rgb-bg |
| (format-rgb-fg-bg fr fg fb br bg bb v) | RGB fg+bg bytes | put-rgb-fg-bg |
| (format-256-fg n v) | 256 foreground bytes | put-256-fg |
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

;; One-line event loop
(loop-input handler)
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
       (format-rgb-fg 255 255 0) #"=== Demo ===" format-reset
       (format-cursor-move 2 0)
       (format-rgb-fg 0 255 0) #"Line 1" format-reset
       (format-cursor-move 3 0)
       (format-rgb-fg 0 255 0) #"Line 2" format-reset
       (format-cursor-move 4 0)
       (format-rgb-fg 0 255 0) #"Line 3" format-reset))

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
     (format-rgb-fg 255 255 0) #"=== TUI Demo ===" format-reset
     (format-cursor-move 2 0)
     (format-rgb-fg 0 255 0) #"Press 'q' to quit" format-reset
     (format-cursor-move 4 0)
     (format-rgb-fg 255 0 0) #"Hello, TUI!" format-reset
     (format-cursor-move 6 0)
     (format-256-fg 46) #"UTF-8 support: 你好世界" format-reset))
  (put-bytes buffer))

(with-tui
    (cursor-hide)
  (define handler
    (build-input
      #:char (lambda (ch)
               (when (= ch (char->integer #\q))
                 (exit)))))  ;; press q to quit
  ;; Wrap handler to render before each event
  (define (render-and-handle type data mods)
    (handler type data mods)
    (draw-ui))
  (loop-input render-and-handle))
```

More examples can be found in the `test/` directory.

## UI Framework

A component-based UI framework built on top of the terminal abstraction. See [ui/README.md](ui/README.md) for detailed documentation.

```racket
(require tui/ui
         tui/base/io/output-color)

(style-define! 'bg-title  (color256-bg 237) (color256-fg 255))
(style-define! 'bg-body   (color256-bg 235) (color256-fg 250))
(style-define! 'bg-footer (color256-bg 240) (color256-fg 255))

(define t-title  (make-text #:text " Demo " #:style 'bg-title))
(define t-body   (make-text #:text " body " #:style 'bg-body))
(define t-footer (make-text #:text " q to quit " #:style 'bg-footer))

(run-app
 (screen
  (t-title 1)
  (t-body 6)
  (t-footer 1)))
```

Components: `make-text`, `make-input`, `make-button`, `make-bool-button`, `make-output`, `make-border`.

Layout: `screen`, `layout-row`, `layout-col`, `border`, `space`.

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

## Cross-Architecture

`base/base.rkt` contains `struct termios` layout and constants obtained from the system at build time. To regenerate for a different architecture (e.g., ARM, 32-bit), run:

```bash
racket base/env-build-base/build-base.rkt
```

This compiles a small C program (`base/env-build-base/dump-termios.c`) that outputs `sizeof(struct termios)`, field offsets, and flag values, then generates `base/base.rkt` from `base/env-build-base/base.rkt.template`.

> Note: Only tested in xterm / qterminal.