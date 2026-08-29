#lang scribble/manual

@(require (for-label "main.rkt"))

@title{tui: Terminal UI for Racket}
@author["lu96-wow"]

@defmodule[tui]

A small terminal UI library for Linux: raw-mode terminal control, mouse and
true-color support, bracketed paste, and window-resize events.

@bold{Linux only.} This library binds directly to Linux @tt{termios},
@tt{signalfd} and @tt{ioctl}. Loading @racketmodname[tui] on other operating
systems raises an error, because the FFI symbols do not exist. Only
@tt{xterm} / @tt{qterminal} have been tested.

@table-of-contents[]

@section{Installation}

Install from the package index:

@verbatim{
raco pkg install tui
}

or directly from GitHub:

@verbatim{
raco pkg install https://github.com/lu96-wow/racket-tui.git
}

@section{Quick Start}

@racketblock[
(require tui)

(with-tui
 (λ ()
   (screen-clear)
   (cursor-hide)
   (put-rgb-fg 255 100 0 "Hello TUI!")
   (put-at 5 10 "Direct output")
   (sleep 2)))
]

@section{API Conventions}

The whole API follows two naming tables (prefix, suffix) and three rules
(@tt{put}/@tt{format} symmetry, argument order, three color tiers). Once these
are known, most function names and signatures can be derived without looking
them up.

@subsection{Prefix: behavior}

@tabular[#:sep @hspace[1]
         (list (list @bold{Prefix} @bold{Meaning} @bold{Example})
               (list @racket[put-] "Immediate terminal output (flushes by default)" @racket[put-string])
               (list @racket[format-] "Return bytes without outputting; batch with @racket[put-bytes]" @racket[format-cursor-move])
               (list @elem{@racket[cursor-] @racket[screen-] @racket[line-] @racket[buffer-]} "Cursor / screen / line / alt-buffer operations (immediate)" @racket[cursor-move])
               (list @racket[clr-] "16-color foreground constructor (shorthand for @racket[(color-fg n)])" @racket[clr-red])
               (list @racket[bclr-] "16-color background constructor" @racket[bclr-blue])
               (list @racket[attr-] "SGR attribute constructor (thunk that emits the escape sequence)" @racket[attr-bold])
               (list @elem{@racket[color-] @racket[color256-] @racket[color-rgb-]} "Color constructors (thunks, for @racket[style-define!])" @racket[color256-fg])
               (list @racket[style-] "Style system" @racket[style-define!])
               (list @racket[event-] "Input-event predicates and accessors" @racket[event-key?])
               (list @racket[current-] "Parameters or tracked cursor variables" @racket[current-cursor-row]))]

@subsection{Suffix: side effects}

@tabular[#:sep @hspace[1]
         (list (list @bold{Suffix} @bold{Meaning} @bold{Example})
               (list @racket[!] "Side effects: updates the tracked cursor / terminal mode" @racket[put-at!])
               (list @racket[?] "Predicate, returns boolean" @racket[terminal?])
               (list @racket[-at] "Positioned (@racket[row] @racket[col] first); DECSC/DECRC so the tracked cursor is untouched" @racket[put-fg-at])
               (list @racket[-at!] "Positioned and updates the tracked cursor" @racket[put-fg-at!])
               (list @racket[-base] "Escape sequence only: no content, no reset" @racket[put-fg-base]))]

@subsection{Rule 1: put / format symmetry}

Almost every capability has both a @tt{put-} form (immediate output) and a
@tt{format-} form (returns bytes), @bold{with identical arguments}:

@racketblock[
(put-fg 1 "x")                  ; = (put-bytes (format-fg 1 "x"))
(put-rgb-fg-at 1 1 255 0 0 "x") ; = (put-bytes (format-rgb-fg-at 1 1 255 0 0 "x"))
(put-cursor-save)               ; = (put-bytes format-cursor-save)
]

Exceptions (by design):

@itemize[
  @item{@racket[put-at] corresponds to @racket[format-content-at] (the
        @tt{-at} name is the content form).}
  @item{@racket[format-styled*] exists only in the @tt{format-} form, for
        batching where one trailing @racket[format-reset] is appended.}
  @item{Output entry points such as @racket[put] and @racket[put-bytes] have
        no @tt{format-} twin; @racket[format-content] does the conversion.}
]

@subsection{Rule 2: argument order}

@itemize[
  @item{The content @racket[v] (string / bytes / char / number) is always the
        @bold{last} argument.}
  @item{Positioned functions take @racket[row] @racket[col] @bold{first}.}
  @item{Color arguments come in the middle: @racket[n] for 16/256 colors;
        @racket[r g b] for RGB; @racket[fr fg fb br bg bb] (foreground then
        background) for foreground+background.}
]

@racketblock[
(put-rgb-fg-bg-at row col fr fg fb br bg bb v)  ; the full shape
]

@subsection{Rule 3: three color tiers are isomorphic}

The 16-color, 256-color and RGB tiers are same-named and same-shaped; only
the color argument differs (@racket[n] / @racket[n] / @racket[r g b]):

@racketblock[
(put-fg n v)           (put-256-fg n v)           (put-rgb-fg r g b v)
(put-fg-at r c n v)    (put-256-fg-at r c n v)    (put-rgb-fg-at r c r g b v)
(put-fg-base n)        (put-256-fg-base n)        (put-rgb-fg-base r g b)
]

Knowing any one tier, the other two can be derived.

@subsection{Standard API categories}

@tabular[#:sep @hspace[1]
         (list (list @bold{Category} @bold{Representative functions})
               (list "Lifecycle" @elem{@racket[with-tui] @racket[tui-init] @racket[enable-mouse!]})
               (list "Basic output" @elem{@racket[put] @racket[put-bytes] @racket[put-newline]})
               (list "Positioned output" @elem{@racket[put-at] @racket[put-at!]})
               (list "Cursor" @elem{@racket[cursor-move] @racket[put-cursor-save]})
               (list "Screen / line / buffer" @elem{@racket[screen-clear] @racket[line-clear] @racket[buffer-alt-enable]})
               (list "Colors" @elem{@racket[put-fg] @racket[put-rgb-fg] @racket[put-256-fg]})
               (list "Styles" @elem{@racket[style-define!] @racket[put-styled] @racket[color-fg]})
               (list "Format (returns bytes)" @elem{@racket[format-fg] @racket[format-cursor-move]})
               (list "Input" @elem{@racket[read-event] @racket[build-input] @racket[loop-input]})
               (list "Terminal" @elem{@racket[terminal?] @racket[enter-raw-mode!] @racket[get-window-size]})
               (list "Cursor tracking" @elem{@racket[current-cursor-row] @racket[set-cursor!] @racket[update-cursor!]})
               (list "Config constants" @elem{@racket[ESCDELAY] @racket[PASTE-MAX-BYTES]}))]

@section{Lifecycle}

All three @tt{with-tui} entry points are @emph{plain functions} taking a
thunk. They use @racket[dynamic-wind] internally, so the terminal is always
restored whether the body returns normally or raises an exception. Exceptions
from the body propagate outward; they are never swallowed.

@defproc[(with-tui [body (-> any)]) any]{
Enters raw mode with the alternate screen buffer, runs @racket[body], then
restores the terminal (raw mode off, alt buffer disabled, mouse and bracketed
paste off, cursor shown, colors reset).
}

@defproc[(with-tui-nobuffer [body (-> any)]) any]{
Like @racket[with-tui], but stays in the main screen buffer (no alternate
buffer), so output is visible after the program exits.
}

@defproc[(with-tui-nobuffer-echo [body (-> any)]) any]{
Like @racket[with-tui-nobuffer], but keeps terminal echo enabled. Useful when
the terminal must display typed input while the program reads keys.
}

@defproc[(tui-init) void?]
Initializes the terminal in raw mode with the alternate screen buffer.
Raises an error if the current input port is not a terminal. If initialization
fails partway, already-changed terminal state is rolled back before the error
is re-raised.

@defproc[(tui-exit) void?]
Restores the terminal to its pre-@racket[tui-init] state. Idempotent: each
cleanup step is defensive, so one failing step prints a warning without
stopping the remaining cleanup.

@defproc[(tui-init-no-buffer) void?]
@defproc[(tui-exit-no-buffer) void?]
Like @racket[tui-init] / @racket[tui-exit], but without the alternate screen
buffer.

@defproc[(tui-init-no-buffer-echo) void?]
@defproc[(tui-exit-no-buffer-echo) void?]
Like @racket[tui-init-no-buffer], but keeps terminal echo enabled.

@defproc[(enable-mouse!) void?]
Enables mouse event tracking (SGR mode).
@defproc[(disable-mouse!) void?]
Disables mouse event tracking.
@defproc[(enable-bracketed-paste!) void?]
Enables bracketed paste mode.
@defproc[(disable-bracketed-paste!) void?]
Disables bracketed paste mode.

@margin-note{
Do not call @racket[(exit)] inside a @tt{with-tui} body: it terminates the
process without running cleanup, leaving the terminal in raw mode. Use a
@racket[running?] flag plus @racket[loop-input/stop] instead.
}

@section{Output}

All @tt{put-} functions write to the current output port immediately
(one flush per call) by default; use @racket[set-buffered-mode!] to batch.

@defproc[(put [v any/c]) void?]
Prints @racket[v] using @racket[~a] formatting.

@defproc[(put-string [s string?]) void?]
@defproc[(put-bytes [bs bytes?]) void?]
@defproc[(put-byte [b byte?]) void?]
@defproc[(put-char [c char?]) void?]
@defproc[(put-newline) void?]
Prints the terminal newline (CRLF in raw mode, LF otherwise).

@defproc[(put-format-bytes [part bytes?] ...) void?]
Concatenates byte-string parts (typically values of @tt{format-} functions)
and writes them in one call.

@defproc[(format-newline) bytes?]
Returns the terminal newline as a byte string.

@defproc[(put-at [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [v any/c]) void?]
Prints @racket[v] at @racket[row]×@racket[col] without disturbing the tracked
cursor position (the terminal saves and restores the cursor).
@defproc[(put-at! [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [v any/c]) void?]
Like @racket[put-at], but updates the tracked cursor position to
@racket[row]×@racket[col].

@subsection{Cursor}

@defproc[(cursor-up [n exact-nonnegative-integer?]) void?]
@defproc[(cursor-down [n exact-nonnegative-integer?]) void?]
@defproc[(cursor-left [n exact-nonnegative-integer?]) void?]
@defproc[(cursor-right [n exact-nonnegative-integer?]) void?]
@defproc[(cursor-move [row exact-nonnegative-integer?] [col exact-nonnegative-integer?]) void?]
@defproc[(cursor-col [n exact-nonnegative-integer?]) void?]
@defproc[(cursor-home) void?]
@defproc[(cursor-hide) void?]
@defproc[(cursor-show) void?]
@defproc[(put-cursor-save) void?]
Saves the cursor position (DECSC).
@defproc[(put-cursor-restore) void?]
Restores the saved cursor position (DECRC).

@subsection{Screen and lines}

@defproc[(screen-clear) void?]
@defproc[(screen-clear-below) void?]
@defproc[(screen-clear-above) void?]
@defproc[(line-clear) void?]
@defproc[(line-clear-right) void?]
@defproc[(line-clear-left) void?]
@defproc[(buffer-alt-enable) void?]
@defproc[(buffer-alt-disable) void?]

@subsection{Flush mode}

@defproc[(set-immediate-mode!) void?]
Every @tt{put-} call flushes immediately (the default).
@defproc[(set-buffered-mode!) void?]
@tt{put-} calls only buffer output; flush manually with @racket[flush!].
@defproc[(flush!) void?]
Flushes buffered output.

@section{Colors}

Colors come in three flavors: 16-color ANSI, 256-color, and true color
(RGB). The @tt{put-} variants print content in that color and reset after.

@defproc[(put-fg [n (integer-in 0 15)] [v any/c]) void?]
@defproc[(put-bg [n (integer-in 0 15)] [v any/c]) void?]
@defproc[(put-rgb-fg [r byte?] [g byte?] [b byte?] [v any/c]) void?]
@defproc[(put-rgb-bg [r byte?] [g byte?] [b byte?] [v any/c]) void?]
@defproc[(put-rgb-fg-bg [fr byte?] [fg byte?] [fb byte?] [br byte?] [bg byte?] [bb byte?] [v any/c]) void?]
@defproc[(put-256-fg [n (integer-in 0 255)] [v any/c]) void?]
@defproc[(put-256-bg [n (integer-in 0 255)] [v any/c]) void?]
@defproc[(put-reset) void?]
Resets all styling (the @tt{put-} counterpart of @racket[format-reset]).

@subsection{Positioned colors}

The @tt{-at} variants print in color at a fixed position. Like
@racket[put-at], they use DECSC/DECRC so the tracked cursor is untouched;
the @tt{-at!} variants update the tracked cursor position instead.

@defproc[(put-fg-at [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [n (integer-in 0 15)] [v any/c]) void?]
@defproc[(put-fg-at! [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [n (integer-in 0 15)] [v any/c]) void?]
@defproc[(put-bg-at [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [n (integer-in 0 15)] [v any/c]) void?]
@defproc[(put-bg-at! [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [n (integer-in 0 15)] [v any/c]) void?]
@defproc[(put-rgb-fg-at [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [r byte?] [g byte?] [b byte?] [v any/c]) void?]
@defproc[(put-rgb-fg-at! [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [r byte?] [g byte?] [b byte?] [v any/c]) void?]
@defproc[(put-rgb-bg-at [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [r byte?] [g byte?] [b byte?] [v any/c]) void?]
@defproc[(put-rgb-bg-at! [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [r byte?] [g byte?] [b byte?] [v any/c]) void?]
@defproc[(put-rgb-fg-bg-at [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [fr byte?] [fg byte?] [fb byte?] [br byte?] [bg byte?] [bb byte?] [v any/c]) void?]
@defproc[(put-rgb-fg-bg-at! [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [fr byte?] [fg byte?] [fb byte?] [br byte?] [bg byte?] [bb byte?] [v any/c]) void?]
@defproc[(put-256-fg-at [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [n (integer-in 0 255)] [v any/c]) void?]
@defproc[(put-256-fg-at! [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [n (integer-in 0 255)] [v any/c]) void?]
@defproc[(put-256-bg-at [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [n (integer-in 0 255)] [v any/c]) void?]
@defproc[(put-256-bg-at! [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [n (integer-in 0 255)] [v any/c]) void?]

@subsection{Escape-only variants}

The @tt{-base} variants emit only the escape sequence, without content or
reset; the attribute variants emit the corresponding SGR sequence:

@defproc[(put-fg-base [n (integer-in 0 15)]) void?]
@defproc[(put-bg-base [n (integer-in 0 15)]) void?]
@defproc[(put-rgb-fg-base [r byte?] [g byte?] [b byte?]) void?]
@defproc[(put-rgb-bg-base [r byte?] [g byte?] [b byte?]) void?]
@defproc[(put-rgb-fg-bg-base [fr byte?] [fg byte?] [fb byte?] [br byte?] [bg byte?] [bb byte?]) void?]
@defproc[(put-256-fg-base [n (integer-in 0 255)]) void?]
@defproc[(put-256-bg-base [n (integer-in 0 255)]) void?]
@defproc[(put-bold) void?]
@defproc[(put-dim) void?]
@defproc[(put-italic) void?]
@defproc[(put-underline) void?]
@defproc[(put-blink) void?]
@defproc[(put-reverse) void?]

@section{Styles}

Styles are named bundles of color and attribute thunks. Define them once,
then apply by name. @racket[style-define!] registers every style in both a
256-color and a 16-color registry; the active registry is selected by
@racket[current-registry] (see @racket[use-color-auto!]).

@subsection{Usage}

@racketblock[
;; define: colors + attributes in any combination, applied in order
(style-define! 'fancy clr-yellow bclr-blue attr-bold attr-underline)

(put-styled 'fancy "Combined style")     ; styled text, auto reset
(put-styled-at  5 10 'fancy "fixed")     ; cursor untouched (DECSC/DECRC)
(put-styled-at! 5 10 'fancy "cursor")    ; updates tracked cursor

;; batching: each format-styled carries its own reset
(put-format-bytes
 (format-styled 'title "Title")
 (format-styled 'info "body text"))
]

The two registries give automatic 256/16-color fallback: plain
@racket[color-fg]/@racket[attr-bold] register the same value in both, while
@racket[color-fg*] and @racket[color-bg*] take separate values for each:

@racketblock[
(style-define! 'status (color-fg* 46 2) attr-bold)  ; 256: bright green / 16: green
]

@racket[style->bytes] returns the precomputed escape bytes for a style; it is
what @racket[format-styled] uses internally. An undefined style name is a
no-op: it produces empty bytes without raising an error.

@defproc[(style-define! [name symbol?] [spec procedure?] ...) void?]
Registers @racket[name] from color/attribute thunks such as @racket[color-fg],
@racket[color-bg], @racket[attr-bold], or @racket[color-fg*].

@defproc[(style-apply! [name symbol?]) void?]
Applies the style currently registered under @racket[name] (no-op if unknown).
@defproc[(style-reset) void?]
Resets all styling.
@defproc[(style->bytes [name symbol?]) bytes?]
Returns the escape-sequence bytes for @racket[name].

@defproc[(put-styled [name symbol?] [v any/c]) void?]
Prints @racket[v] in style @racket[name], then resets.
@defproc[(put-styled-at [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [name symbol?] [v any/c]) void?]
@defproc[(put-styled-at! [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [name symbol?] [v any/c]) void?]

@defproc[(put-styled-bold [v any/c]) void?]
@defproc[(put-styled-bold-at [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [v any/c]) void?]
@defproc[(put-styled-bold-at! [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [v any/c]) void?]
@defproc[(put-styled-dim [v any/c]) void?]
@defproc[(put-styled-dim-at [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [v any/c]) void?]
@defproc[(put-styled-dim-at! [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [v any/c]) void?]
@defproc[(put-styled-italic [v any/c]) void?]
@defproc[(put-styled-italic-at [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [v any/c]) void?]
@defproc[(put-styled-italic-at! [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [v any/c]) void?]
@defproc[(put-styled-underline [v any/c]) void?]
@defproc[(put-styled-underline-at [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [v any/c]) void?]
@defproc[(put-styled-underline-at! [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [v any/c]) void?]
@defproc[(put-styled-blink [v any/c]) void?]
@defproc[(put-styled-blink-at [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [v any/c]) void?]
@defproc[(put-styled-blink-at! [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [v any/c]) void?]
@defproc[(put-styled-reverse [v any/c]) void?]
@defproc[(put-styled-reverse-at [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [v any/c]) void?]
@defproc[(put-styled-reverse-at! [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [v any/c]) void?]
Attribute-styled output: bold, dim, italic, underline, blink, reverse, each with
@tt{-at} (fixed position, cursor untouched) and @tt{-at!} (updates tracked
cursor) variants. The @tt{put-} counterparts of @racket[format-styled-bold]
and friends.

@subsection{Color and attribute constructors}

@defproc[(color-fg [n (integer-in 0 15)]) procedure?]
@defproc[(color-bg [n (integer-in 0 15)]) procedure?]
@defproc[(color256-fg [n (integer-in 0 255)]) procedure?]
@defproc[(color256-bg [n (integer-in 0 255)]) procedure?]
@defproc[(color-rgb-fg [r byte?] [g byte?] [b byte?]) procedure?]
@defproc[(color-rgb-bg [r byte?] [g byte?] [b byte?]) procedure?]

@defproc[(color-fg* [c256 (integer-in 0 255)] [c16 (integer-in 0 15)]) color-thunk?]
A two-registry color: uses @racket[c256] when the 256-color registry is
active, @racket[c16] otherwise.
@defproc[(color-bg* [c256 (integer-in 0 255)] [c16 (integer-in 0 15)]) color-thunk?]

@defproc[(attr-bold) void?]
@defproc[(attr-dim) void?]
@defproc[(attr-italic) void?]
@defproc[(attr-underline) void?]
@defproc[(attr-blink) void?]
@defproc[(attr-reverse) void?]

@subsection{Color mode}

@defproc[(use-256color!) void?]
Selects the 256-color style registry.
@defproc[(use-16color!) void?]
Selects the 16-color style registry.
@defproc[(use-color-auto!) void?]
Selects the registry based on the @envvar{COLORTERM} / @envvar{TERM}
environment variables. Called automatically by @racket[tui-init].

@subsection{Built-in styles}

The following styles are pre-registered by the library:

@itemize[
  @item{Basic: @racket['red] @racket['green] @racket['blue] @racket['yellow]
        @racket['cyan] @racket['magenta] @racket['white]}
  @item{Levels: @racket['error] @racket['warning] @racket['info] @racket['success]}
  @item{Text: @racket['title] @racket['subtitle] @racket['heading] @racket['border]
        @racket['border-bold]}
  @item{Widgets: @racket['button] @racket['button-hover] @racket['button-pressed]
        @racket['button-disabled]}
  @item{Menus: @racket['menu-item] @racket['menu-selected] @racket['menu-key]
        @racket['menu-shortcut]}
  @item{Lists: @racket['list-item] @racket['list-selected] @racket['list-alternate]}
  @item{Dialogs: @racket['dialog-title] @racket['dialog-body] @racket['dialog-button]
        @racket['dialog-highlight]}
  @item{Status: @racket['status-bar] @racket['status-good] @racket['status-warning]
        @racket['status-bad]}
  @item{Input: @racket['input-normal] @racket['input-focus] @racket['input-error]}
  @item{Misc: @racket['cursor] @racket['selection] @racket['scroll-track]
        @racket['scroll-thumb]}
]

@section{Format functions}

The @tt{format-} functions return byte strings without writing anything.
They are meant to be collected and written in one batch with
@racket[put-format-bytes] or @racket[put-bytes]. Each value-taking variant
appends content and a style reset, so @racket[format-reset] is only needed
once at the end of a batch.

@defproc[(format-cursor-move [row exact-nonnegative-integer?] [col exact-nonnegative-integer?]) bytes?]
@defproc[(format-cursor-up [n exact-nonnegative-integer?]) bytes?]
@defproc[(format-cursor-down [n exact-nonnegative-integer?]) bytes?]
@defproc[(format-cursor-left [n exact-nonnegative-integer?]) bytes?]
@defproc[(format-cursor-right [n exact-nonnegative-integer?]) bytes?]
@defproc[(format-cursor-col [n exact-nonnegative-integer?]) bytes?]
@defproc[(format-cursor-home) bytes?]
@defproc[(format-cursor-hide) bytes?]
@defproc[(format-cursor-show) bytes?]
@defproc[(format-cursor-save) bytes?]
@defproc[(format-cursor-restore) bytes?]
@defproc[(format-screen-clear) bytes?]
@defproc[(format-screen-clear-below) bytes?]
@defproc[(format-screen-clear-above) bytes?]
@defproc[(format-line-clear) bytes?]
@defproc[(format-line-clear-right) bytes?]
@defproc[(format-line-clear-left) bytes?]
@defproc[(format-buffer-alt-enable) bytes?]
@defproc[(format-buffer-alt-disable) bytes?]
@defproc[(format-reset) bytes?]
@defproc[(format-bold) bytes?]
@defproc[(format-dim) bytes?]
@defproc[(format-italic) bytes?]
@defproc[(format-underline) bytes?]
@defproc[(format-blink) bytes?]
@defproc[(format-reverse) bytes?]

@defproc[(format-content [v any/c]) bytes?]
Converts @racket[v] to a byte string (bytes pass through, strings become
UTF-8, other values use @racket[~a]).

@defproc[(format-fg [n (integer-in 0 15)] [v any/c]) bytes?]
@defproc[(format-bg [n (integer-in 0 15)] [v any/c]) bytes?]
@defproc[(format-rgb-fg [r byte?] [g byte?] [b byte?] [v any/c]) bytes?]
@defproc[(format-rgb-bg [r byte?] [g byte?] [b byte?] [v any/c]) bytes?]
@defproc[(format-rgb-fg-bg [fr byte?] [fg byte?] [fb byte?] [br byte?] [bg byte?] [bb byte?] [v any/c]) bytes?]
@defproc[(format-256-fg [n (integer-in 0 255)] [v any/c]) bytes?]
@defproc[(format-256-bg [n (integer-in 0 255)] [v any/c]) bytes?]
@defproc[(format-fg-base [n (integer-in 0 15)]) bytes?]
@defproc[(format-bg-base [n (integer-in 0 15)]) bytes?]
@defproc[(format-rgb-fg-base [r byte?] [g byte?] [b byte?]) bytes?]
@defproc[(format-rgb-bg-base [r byte?] [g byte?] [b byte?]) bytes?]
@defproc[(format-rgb-fg-bg-base [fr byte?] [fg byte?] [fb byte?] [br byte?] [bg byte?] [bb byte?]) bytes?]
@defproc[(format-256-fg-base [n (integer-in 0 255)]) bytes?]
@defproc[(format-256-bg-base [n (integer-in 0 255)]) bytes?]

@defproc[(format-styled [name symbol?] [v any/c]) bytes?]
@defproc[(format-styled* [name symbol?] [v any/c]) bytes?]
Like @racket[format-styled], but without the trailing reset.
@defproc[(format-styled-at [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [name symbol?] [v any/c]) bytes?]
@defproc[(format-styled-at! [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [name symbol?] [v any/c]) bytes?]
@defproc[(format-styled-bold [v any/c]) bytes?]
@defproc[(format-styled-bold-at [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [v any/c]) bytes?]
@defproc[(format-styled-bold-at! [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [v any/c]) bytes?]
@defproc[(format-styled-dim [v any/c]) bytes?]
@defproc[(format-styled-dim-at [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [v any/c]) bytes?]
@defproc[(format-styled-dim-at! [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [v any/c]) bytes?]
@defproc[(format-styled-italic [v any/c]) bytes?]
@defproc[(format-styled-italic-at [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [v any/c]) bytes?]
@defproc[(format-styled-italic-at! [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [v any/c]) bytes?]
@defproc[(format-styled-underline [v any/c]) bytes?]
@defproc[(format-styled-underline-at [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [v any/c]) bytes?]
@defproc[(format-styled-underline-at! [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [v any/c]) bytes?]
@defproc[(format-styled-blink [v any/c]) bytes?]
@defproc[(format-styled-blink-at [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [v any/c]) bytes?]
@defproc[(format-styled-blink-at! [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [v any/c]) bytes?]
@defproc[(format-styled-reverse [v any/c]) bytes?]
@defproc[(format-styled-reverse-at [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [v any/c]) bytes?]
@defproc[(format-styled-reverse-at! [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [v any/c]) bytes?]

@defproc[(format-content-at [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [v any/c]) bytes?]
@defproc[(format-content-at! [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [v any/c]) bytes?]
@defproc[(format-fg-at [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [n (integer-in 0 15)] [v any/c]) bytes?]
@defproc[(format-fg-at! [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [n (integer-in 0 15)] [v any/c]) bytes?]
@defproc[(format-bg-at [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [n (integer-in 0 15)] [v any/c]) bytes?]
@defproc[(format-bg-at! [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [n (integer-in 0 15)] [v any/c]) bytes?]
@defproc[(format-rgb-fg-at [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [r byte?] [g byte?] [b byte?] [v any/c]) bytes?]
@defproc[(format-rgb-fg-at! [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [r byte?] [g byte?] [b byte?] [v any/c]) bytes?]
@defproc[(format-rgb-bg-at [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [r byte?] [g byte?] [b byte?] [v any/c]) bytes?]
@defproc[(format-rgb-bg-at! [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [r byte?] [g byte?] [b byte?] [v any/c]) bytes?]
@defproc[(format-256-fg-at [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [n (integer-in 0 255)] [v any/c]) bytes?]
@defproc[(format-256-fg-at! [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [n (integer-in 0 255)] [v any/c]) bytes?]
@defproc[(format-256-bg-at [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [n (integer-in 0 255)] [v any/c]) bytes?]
@defproc[(format-256-bg-at! [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [n (integer-in 0 255)] [v any/c]) bytes?]
@defproc[(format-rgb-fg-bg-at [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [fr byte?] [fg byte?] [fb byte?] [br byte?] [bg byte?] [bb byte?]) bytes?]
@defproc[(format-rgb-fg-bg-at! [row exact-nonnegative-integer?] [col exact-nonnegative-integer?] [fr byte?] [fg byte?] [fb byte?] [br byte?] [bg byte?] [bb byte?]) bytes?]

@section{Input}

@subsection{High-level: build-input and event loops}

@defproc[(build-input
          [#:char on-char (or/c (-> integer? any) #f) #f]
          [#:utf-char on-utf-char (or/c (-> string? any) #f) #f]
          [#:ctrl on-ctrl (or/c (-> char? any) #f) #f]
          [#:alt on-alt (or/c (-> char? any) #f) #f]
          [#:mod on-mod (or/c (-> char? boolean? boolean? boolean? any) #f) #f]
          [#:tab on-tab (or/c (-> any) #f) #f]
          [#:backtab on-backtab (or/c (-> any) #f) #f]
          [#:space on-space (or/c (-> any) #f) #f]
          [#:enter on-enter (or/c (-> any) #f) #f]
          [#:backspace on-backspace (or/c (-> any) #f) #f]
          [#:escape on-escape (or/c (-> any) #f) #f]
          [#:up on-up (or/c (-> any) #f) #f]
          [#:down on-down (or/c (-> any) #f) #f]
          [#:left on-left (or/c (-> any) #f) #f]
          [#:right on-right (or/c (-> any) #f) #f]
          [#:delete on-delete (or/c (-> any) #f) #f]
          [#:insert on-insert (or/c (-> any) #f) #f]
          [#:home on-home (or/c (-> any) #f) #f]
          [#:end on-end (or/c (-> any) #f) #f]
          [#:pageup on-pageup (or/c (-> any) #f) #f]
          [#:pagedown on-pagedown (or/c (-> any) #f) #f]
          [#:mouse-press on-mouse-press (or/c (-> symbol? exact-nonnegative-integer? exact-nonnegative-integer? (listof symbol?) any) #f) #f]
          [#:mouse-release on-mouse-release (or/c (-> symbol? exact-nonnegative-integer? exact-nonnegative-integer? (listof symbol?) any) #f) #f]
          [#:mouse-move on-mouse-move (or/c (-> exact-nonnegative-integer? exact-nonnegative-integer? (listof symbol?) any) #f) #f]
          [#:mouse-scroll on-mouse-scroll (or/c (-> symbol? exact-nonnegative-integer? exact-nonnegative-integer? (listof symbol?) any) #f) #f]
          [#:paste on-paste (or/c (-> bytes? any) #f) #f]
          [#:resize on-resize (or/c (-> exact-positive-integer? exact-positive-integer? any) #f) #f]
          [#:null on-null (or/c (-> any) #f) #f]
          [#:any on-any (or/c (-> symbol? bytes? (or/c #f (list/c boolean? boolean? boolean?)) any) #f) #f])
         (-> symbol? bytes? (or/c #f (list/c boolean? boolean? boolean?)) any)]{
Builds an event handler from callback keywords. Every keyword is optional;
events without a handler fall through to @racket[#:any], or are ignored.
The returned function has the signature @racket[(type data mods) ...] and can
be passed to @racket[loop-input] or called directly.

Event dispatch priority (built in): @tt{null} > @tt{resize} > @tt{paste} >
@tt{mouse} > tab/backtab/space/enter/backspace/escape > arrows > function
keys > @tt{ctrl} > @tt{alt} > @tt{mod-seq} > @tt{utf8} > @tt{char} >
@tt{any}.
}

@defform[(loop-input handler ...)]{
Reads events forever and calls each @racket[handler] function with
@racket[(values type data mods)] per event. Macro that expands to a loop.
}

@defform[(loop-input-noblock handler ...)]{
Like @racket[loop-input], using @racket[read-event-noblock].
}

@defform[(loop-input/stop stop-expr handler ...)]{
Like @racket[loop-input], but re-evaluates @racket[stop-expr] after each
event and stops when it is true.
}

@defform[(loop-input-noblock/stop stop-expr handler ...)]{
Like @racket[loop-input/stop], using @racket[read-event-noblock].
}

@subsection{Low-level: read-event}

@defproc[(read-event) (values symbol? bytes? (or/c #f (list/c boolean? boolean? boolean?)))]{
Reads one input event from the terminal, blocking until input arrives.
Returns @racket[(values type data mods)]:

@itemize[
  @item{@racket[type] --- a symbol (see the predicates below).}
  @item{@racket[data] --- event payload: key byte, UTF-8 bytes, mouse detail
        list, paste bytes, or @racket[(rows . cols)] for resize.}
  @item{@racket[mods] --- @racket[#f] (no modifiers) or
        @racket[(list ctrl? alt? shift?)] for modified keys and mouse
        events.}
]
}

@defproc[(read-event-noblock) (values symbol? bytes? (or/c #f (list/c boolean? boolean? boolean?)))]
Like @racket[read-event], but returns immediately with @racket['null] when no
input is available.

@defproc[(event-null? [type symbol?]) boolean?]
@defproc[(event-key? [type symbol?]) boolean?]
@defproc[(event-utf8? [type symbol?]) boolean?]
@defproc[(event-seq? [type symbol?]) boolean?]
@defproc[(event-ctrl? [type symbol?]) boolean?]
@defproc[(event-alt? [type symbol?]) boolean?]
@defproc[(event-mod-seq? [type symbol?]) boolean?]
@defproc[(event-resize? [type symbol?]) boolean?]
@defproc[(event-up? [type symbol?]) boolean?]
@defproc[(event-down? [type symbol?]) boolean?]
@defproc[(event-left? [type symbol?]) boolean?]
@defproc[(event-right? [type symbol?]) boolean?]
@defproc[(event-del? [type symbol?]) boolean?]
@defproc[(event-insert? [type symbol?]) boolean?]
@defproc[(event-home? [type symbol?]) boolean?]
@defproc[(event-end? [type symbol?]) boolean?]
@defproc[(event-pageup? [type symbol?]) boolean?]
@defproc[(event-pagedown? [type symbol?]) boolean?]
@defproc[(event-backtab? [type symbol?]) boolean?]
@defproc[(event-touch? [type symbol?]) boolean?]
@defproc[(event-mouse? [type symbol?]) boolean?]
@defproc[(event-paste? [type symbol?]) boolean?]
Predicates on the event @racket[type] returned by @racket[read-event].

@defproc[(event-tab? [type symbol?] [data bytes?]) boolean?]
@defproc[(event-space? [type symbol?] [data bytes?]) boolean?]
@defproc[(event-backspace? [type symbol?] [data bytes?]) boolean?]
@defproc[(event-enter? [type symbol?] [data bytes?]) boolean?]
@defproc[(event-escape? [type symbol?] [data bytes?]) boolean?]
Predicates that also check the key byte in @racket[data].

@defproc[(ctrl->char [data bytes?]) (or/c char? #f)]
Returns the letter of a Ctrl+letter event.
@defproc[(alt->char [data bytes?]) (or/c char? #f)]
Returns the character of an Alt+character event.
@defproc[(mod-seq->char [data bytes?]) (or/c char? #f)]
Returns the character of a Ctrl+Alt+character event.

@defproc[(event->string [data bytes?]) string?]
Decodes UTF-8 event data to a string.
@defproc[(event->byte [data bytes?]) byte?]
Extracts a single byte from event data.

@subsection{Mouse}

@defproc[(mouse-press? [detail list?]) boolean?]
@defproc[(mouse-release? [detail list?]) boolean?]
@defproc[(mouse-move? [detail list?]) boolean?]
@defproc[(mouse-scroll? [detail list?]) boolean?]
@defproc[(mouse-left? [detail list?]) boolean?]
@defproc[(mouse-middle? [detail list?]) boolean?]
@defproc[(mouse-right? [detail list?]) boolean?]
@defproc[(scroll-up? [detail list?]) boolean?]
@defproc[(scroll-down? [detail list?]) boolean?]
Predicates on the mouse @racket[detail] list carried in @racket[data].

@defproc[(mouse-x [detail list?]) exact-nonnegative-integer?]
@defproc[(mouse-y [detail list?]) exact-nonnegative-integer?]
@defproc[(get-mouse-pos [detail list?]) (values exact-nonnegative-integer? exact-nonnegative-integer?)]
@defproc[(mouse-modifiers [detail list?]) (listof symbol?)]

@subsection{Resize}

@defproc[(get-resize-rows [data (cons/c exact-positive-integer? exact-positive-integer?)]) exact-positive-integer?]
@defproc[(get-resize-cols [data (cons/c exact-positive-integer? exact-positive-integer?)]) exact-positive-integer?]
@defproc[(get-resize-size [data (cons/c exact-positive-integer? exact-positive-integer?)]) (values exact-positive-integer? exact-positive-integer?)]

@section{Terminal}

@defproc[(terminal?) boolean?]
True when the current input port is a terminal (@tt{isatty}).

@defproc[(enter-raw-mode!) void?]
Turns off canonical mode and echo, disables signal generation, and enables
extended input processing. Used internally by @racket[tui-init].
@defproc[(exit-raw-mode!) void?]
Restores the saved terminal state.
@defproc[(enter-raw-mode-keep-echo!) void?]
Raw mode but keeps echo on. Used internally by
@racket[tui-init-no-buffer-echo].

@defproc[(call-with-terminal-reply [thunk (-> any)]) any]
Runs @racket[thunk] with a timeout such that a terminal reply (for example
from a DSR query) can be read without hanging.

@defproc[(make-stdin-evt) evt?]
A synchronizable event that is ready when stdin has input.

@defproc[(get-window-size [fd exact-integer? 1]) (values (or/c exact-positive-integer? #f) (or/c exact-positive-integer? #f))]
Returns the terminal size as @racket[(values rows cols)], or
@racket[(values #f #f)] if the ioctl fails. @racket[fd] defaults to stdout.

@defproc[(resize-monitor-start) void?]
Starts a background thread watching for SIGWINCH; resizes are reported as
@racket['resize] events by @racket[read-event].
@defproc[(resize-monitor-stop) void?]
Stops the resize monitor.
@defproc[(make-resize-evt) evt?]
A synchronizable event that is ready when the terminal has been resized.

@section{Cursor state}

The library tracks the cursor position in two parameters; @tt{-at} functions
update it.

@defthing[current-cursor-row exact-nonnegative-integer?]{
The tracked cursor row (1-based).}
@defthing[current-cursor-col exact-nonnegative-integer?]{
The tracked cursor column (1-based).}

@defproc[(set-cursor! [row exact-nonnegative-integer?] [col exact-nonnegative-integer?]) void?]
@defproc[(get-cursor) (values exact-nonnegative-integer? exact-nonnegative-integer?)]
@defproc[(update-cursor!) (values exact-nonnegative-integer? exact-nonnegative-integer?)]
Sends a DSR query (@tt{ESC[6n}) and parses the terminal's reply to refresh
the tracked cursor position.

@section{Configuration constants}

@defthing[ESCDELAY real?]{
Timeout between bytes of an escape sequence (seconds), used to distinguish a
lone @tt{ESC} key press from a control sequence. Default @racket[0.05].}

@defthing[CSI-MAX-BYTES exact-positive-integer?]{
Maximum CSI sequence length before truncation. Default @racket[32].}

@defthing[PASTE-MAX-BYTES exact-positive-integer?]{
Maximum bracketed-paste length. Default @racket[1048576] (1 MiB).}

@defthing[UTF8-READ-TIMEOUT real?]{
Timeout for reading UTF-8 continuation bytes. Default @racket[0.5].}

@defthing[PASTE-READ-TIMEOUT real?]{
Timeout between bytes while reading a paste. Default @racket[1.0].}

@section{Complete example}

@racketblock[
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
     (format-256-fg 46 "UTF-8 support: 你好世界") format-reset))
  (put-bytes buffer))

(with-tui
 (λ ()
   (cursor-hide)
   (define running? #t)
   (define handler
     (build-input
      #:char (lambda (ch)
               (when (= ch (char->integer #\q))
                 (set! running? #f)))))
   (define (render-and-handle type data mods)
     (handler type data mods)
     (draw-ui))
   (loop-input/stop (not running?) render-and-handle)))
]

@section{Implementation notes}

The @tt{termios} struct layout and flag constants in
@tt{base/terminal/base.rkt} are hardcoded (previously generated by compiling
a C program). The values come from the kernel's @tt{asm-generic/termbits.h}
and are identical across mainstream Linux architectures (x86, arm, aarch64,
riscv, ppc, mips, sparc). @tt{TERMIOS-SIZE} is fixed at 60, which is safe for
both glibc and musl. The only exception is the alpha architecture, which is
not supported.
