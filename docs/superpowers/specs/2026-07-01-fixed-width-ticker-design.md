# Fixed-Width Scrolling Ticker — Design

_Update (same day): added a "Display Width" preset menu alongside "Scroll
Speed" so the fixed width is adjustable at runtime, not just hardcoded._

## Problem

`AppDelegate` currently sets `statusItem.button.title` directly to the
`"<artist> - <title>"` string (`AppDelegate.m:94-96`), with the status item
using `NSVariableStatusItemLength`. The status item's width therefore changes
every time the track changes, shifting every other menu bar item to its
left. Long titles make this worse.

## Goal

The menu bar item should occupy a **fixed width** at all times — idle or
playing, short title or long — so surrounding menu bar items never move.
Text that doesn't fit the fixed width should scroll ("flow") continuously
rather than being truncated.

## Non-goals

- No preferences window. This app has none today, and the new configurable
  values (scroll speed, display width) fit as small menus.
- No change to polling/notification logic, Music/Spotify integration, or
  the app's existing menu structure beyond adding the two new submenus.
- No arbitrary/custom width entry (e.g. a text-entry dialog) for now —
  three presets only. Finer-grained control can be added later if it turns
  out to be wanted.

## Architecture

Replace direct `button.title` assignment with a custom `NSView` subclass,
`TickerView`, embedded inside the status item's button:

- `statusItem.button.title` is cleared (empty string); `TickerView` is added
  as a subview filling the button's bounds.
- `statusItem.length` is set to a fixed pixel value (see "Fixed width"
  below) instead of `NSVariableStatusItemLength`.
- `AppDelegate.updateTrackInfo` sets `tickerView.text = ...` instead of
  `button.title`, once per poll/notification, exactly as today.
- `TickerView` returns `nil` from `-hitTest:` so mouse clicks fall through
  to the underlying button, preserving the existing click-to-open-menu
  behavior unchanged.
- `AppDelegate` becomes the delegate of `statusMenu` and implements
  `-menuWillOpen:` / `-menuDidClose:` to toggle `TickerView.highlighted`,
  so the view can mimic the native highlight appearance (inverted text,
  pill background suppressed) while the menu is open — since we no longer
  get that automatically from `NSButton`'s own title rendering.

### TickerView responsibilities

- **Fixed width**: given at init time as a point value; can be changed
  later at runtime via a `setFixedWidth:` call (see "Display Width" below).
  Changing it resizes the view's frame and re-evaluates whether the current
  `text` now fits or overflows (same logic as when `text` changes: reset
  scroll offset, start/stop the timer accordingly).
- **Background**: draws a faint, rounded-rect, gray fill behind the text
  at all times (idle, static-fit, and scrolling), adapting to light/dark
  mode via a semantic system color. Suppressed while `highlighted == YES`
  (menu open), since the native highlight pill covers the same area.
- **Static case** (text fits within the width): draws once, left-aligned,
  vertically centered. No timer runs.
- **Scrolling case** (text wider than the width): runs an `NSTimer` at
  ~30fps that advances a pixel offset and redraws. The drawn string is the
  text doubled with a fixed-width gap in between
  (`"<text>" + "      " + "<text>"`), and the offset wraps (subtracting
  one full cycle width: text width + gap width) once a complete cycle has
  scrolled past, producing a seamless, gapless-jump loop. Content is
  clipped to the view's bounds.
- **Highlight state**: a `highlighted` BOOL property. When true, text is
  drawn in the inverted/high-contrast color and the background fill is
  skipped; when false, normal `labelColor` text over the faint background.
  Changing `text` or `highlighted` triggers a redraw; changing `text`
  also resets the scroll offset to 0 and starts/stops the timer as needed.
- **Scroll speed**: a `scrollSpeed` property (points/second). Changing it
  takes effect on the next timer tick — no reset of animation state needed.

### AppDelegate changes

- Compute the fixed width once (`awakeFromNib`, after `statusItem` and its
  button exist, since we need the button's font metrics).
- Create and install `TickerView`, sized to that fixed width, as a subview
  of `statusItem.button`.
- Replace the two lines in `updateTrackInfo` that set `button.title` with
  a single `tickerView.text = ...` assignment (same ternary: track info or
  the idle glyph).
- Add a "Scroll Speed" submenu (Slow / Normal / Fast) to `statusMenu`,
  above "Quit", each item toggling a checkmark and writing the choice to
  `NSUserDefaults`; on selection, update `tickerView.scrollSpeed`
  immediately.
- Add a "Display Width" submenu (Narrow / Normal / Wide) the same way,
  writing the chosen character count to `NSUserDefaults`; on selection,
  recompute the pixel width from the button's font metrics, update
  `statusItem.length` and call `tickerView.setFixedWidth:` with the new
  value, applied immediately (no restart).
- Read both persisted values at launch (defaulting to Normal/Normal if
  unset) and apply them before the first `updateTrackInfo` call.
- Set `self.statusMenu.delegate = self` and implement the two
  `NSMenuDelegate` methods described above.

## Concrete defaults

- **Display width presets** (character count): Narrow = 20, Normal = 30,
  Wide = 45. Default: Normal. Pixel width is estimated as
  `characterCount × (width of "0" in the status bar font)`, plus ~4pt
  padding on each side to match the native inset other menu bar items have.
  Starting points to be confirmed/tuned by eye during manual testing.
- **Gap between repeats while scrolling**: 6 spaces worth of width, in the
  same font.
- **Scroll speed presets**: Slow = 20pt/s, Normal = 40pt/s, Fast = 70pt/s.
  Default: Normal. Starting points to be confirmed/tuned by eye during
  manual testing, not hard requirements.
- **Background fill**: faint, semantic gray (e.g. `NSColor.quaternaryLabelColor`
  or similar low-contrast system color, chosen so it works in both
  appearances), rounded-rect with a small corner radius (e.g. 4pt).

## Data flow

Unchanged from today except for the final write target:

```
NSTimer (10s poll) ─┐
                     ├─> updateTrackInfo ─> tickerView.text = "<artist> - <title>" | "♫"
Distributed          │
notifications ───────┘
```

`TickerView` internally owns its own animation timer (independent of the
10s polling timer), started/stopped based on whether the current `text`
overflows the fixed width.

Scroll-speed and display-width menu selections are separate, independent
data paths:

```
User picks Scroll Speed item ─> NSUserDefaults write ─> tickerView.scrollSpeed = preset

User picks Display Width item ─> NSUserDefaults write ─> recompute pixel width
                                  ─> statusItem.length = newWidth
                                  ─> tickerView.setFixedWidth:(newWidth)
```

## Error handling

None needed beyond what exists. This is a purely visual feature with no
new I/O, no new failure modes. `nil`/empty `text` draws nothing (matches
today's behavior when there's no track and no idle glyph would somehow be
missing — doesn't currently happen, and won't after this change either).

## Testing

No existing test target (this is a GUI Cocoa app with no unit/UI tests
today). Verification will be manual, using the project's existing
`xcodebuild` build steps to run the app, checking:

1. Idle glyph and short titles sit static, left-aligned, on the faint
   background, inside the fixed-width box.
2. Long titles scroll left continuously and loop with a visible, evenly
   spaced gap — no visible jump/reset at the wrap point.
3. The menu bar item's width never changes across idle/short/long text.
4. Changing "Scroll Speed" takes effect immediately on an in-progress
   scroll, and the checkmark reflects the current selection and survives
   a relaunch.
5. Changing "Display Width" resizes the menu bar item immediately (no
   restart, no track change needed), other menu bar items shift to
   accommodate the new width, and text that now fits/overflows switches
   between static and scrolling correctly. Checkmark reflects the current
   selection and survives a relaunch.
6. Clicking the status item still opens `statusMenu`; while open, text
   inverts and the faint background is suppressed in favor of the native
   highlight, matching pre-change look-and-feel for the highlighted state.
7. Correct appearance in both Light and Dark mode.
