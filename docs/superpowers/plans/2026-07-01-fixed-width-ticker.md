# Fixed-Width Scrolling Ticker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the menu bar item occupy a fixed width at all times (idle or playing), scrolling overflow text instead of resizing, with a faint background box and two runtime-adjustable presets (Scroll Speed, Display Width).

**Architecture:** A new `TickerView` (`NSView` subclass) replaces direct `statusItem.button.title` assignment. It owns fixed-width layout, the faint rounded-rect background, static/scrolling text rendering (marquee via `NSTimer`), and a highlight state. `AppDelegate` creates and feeds it, and grows two small preset submenus (Scroll Speed, Display Width) on the existing status menu, persisted via `NSUserDefaults`.

**Tech Stack:** Objective-C, Cocoa/AppKit, manual reference counting (MRC — this codebase does not use ARC; see Global Constraints), Xcode project format (`.pbxproj`), `xcodebuild` CLI.

**Reference spec:** `docs/superpowers/specs/2026-07-01-fixed-width-ticker-design.md`

## Global Constraints

- **No ARC.** This codebase uses manual reference counting (see `AppDelegate.m`'s `dealloc` calling `[super dealloc]`, and `@property (nonatomic, retain) ...`). All new code must do the same: `retain`/`copy` property attributes (never `strong`/`weak`), explicit `[super dealloc]`, `alloc]/autorelease]` for temporaries not held by a property.
- **Deployment target:** macOS 10.15 (`MACOSX_DEPLOYMENT_TARGET = 10.15` in `project.pbxproj`). Don't use APIs newer than that.
- **No new test target.** This GUI app has no unit/UI tests today (confirmed: no `*Tests` target in the project). Per the spec, verification is manual via `xcodebuild` + running the app. Each task's "test" step is a manual build-and-observe check, not an automated test.
- **Indentation:** 4 spaces, matching existing files (`AppDelegate.m`).
- **Build command** (already verified to work on this machine — see project memory):
  ```
  xcodebuild -project "Menu Bar Ticker.xcodeproj" -scheme "Menu Bar Ticker" -configuration Debug build
  ```
  Use `Debug` while iterating (faster, keeps symbols); the app lands in
  `~/Library/Developer/Xcode/DerivedData/Menu_Bar_Ticker-*/Build/Products/Debug/Menu Bar Ticker.app`.
- **Don't touch:** polling/notification logic (`kPollingInterval`, `timerDidFire:`, `didReceivePlayerNotification:`), Music/Spotify integration, `MainMenu.xib` (all new menu items are built programmatically in `AppDelegate.m`, not in the xib — avoids hand-editing Interface Builder XML).
- **Modern AppKit constants:** use `NSControlStateValueOn`/`NSControlStateValueOff` (not the deprecated `NSOnState`/`NSOffState`) — this project has a history of removing deprecated API usage (see git log: "Fix NSStatusItem deprecations").

---

### Task 1: Create `TickerView` and register it with the Xcode project

**Files:**
- Create: `MenubarTicker/TickerView.h`
- Create: `MenubarTicker/TickerView.m`
- Modify: `Menu Bar Ticker.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces (used by all later tasks):
  - `typedef NS_ENUM(NSInteger, TickerScrollSpeed) { TickerScrollSpeedSlow, TickerScrollSpeedNormal, TickerScrollSpeedFast };`
  - `@interface TickerView : NSView`
  - `@property (nonatomic, copy) NSString *text;`
  - `@property (nonatomic, assign) TickerScrollSpeed scrollSpeed;`
  - `@property (nonatomic, assign, getter=isHighlighted) BOOL highlighted;`
  - `@property (nonatomic, readonly) CGFloat fixedWidth;` (current width in points, including padding)
  - `- (instancetype)initWithFont:(NSFont *)font;`
  - `- (void)setFixedWidthInCharacters:(NSInteger)characterCount;` (recomputes `fixedWidth`, resizes `self.frame`, re-evaluates static vs. scrolling)

- [ ] **Step 1: Write `TickerView.h`**

```objc
#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, TickerScrollSpeed) {
    TickerScrollSpeedSlow,
    TickerScrollSpeedNormal,
    TickerScrollSpeedFast,
};

@interface TickerView : NSView

@property (nonatomic, copy) NSString *text;
@property (nonatomic, assign) TickerScrollSpeed scrollSpeed;
@property (nonatomic, assign, getter=isHighlighted) BOOL highlighted;
@property (nonatomic, readonly) CGFloat fixedWidth;

- (instancetype)initWithFont:(NSFont *)font;
- (void)setFixedWidthInCharacters:(NSInteger)characterCount;

@end
```

- [ ] **Step 2: Write `TickerView.m`**

```objc
#import "TickerView.h"

static const CGFloat kTickerHorizontalPadding = 4.0;
static const CGFloat kTickerCornerRadius = 4.0;
static NSString * const kTickerScrollGap = @"      "; // 6 spaces
static const NSTimeInterval kTickerTimerInterval = 1.0 / 30.0;

static const CGFloat kScrollSpeedSlowPointsPerSecond = 20.0;
static const CGFloat kScrollSpeedNormalPointsPerSecond = 40.0;
static const CGFloat kScrollSpeedFastPointsPerSecond = 70.0;

@interface TickerView ()

@property (nonatomic, readwrite) CGFloat fixedWidth;
@property (nonatomic, retain) NSFont *font;
@property (nonatomic, assign) CGFloat scrollOffset;
@property (nonatomic, retain) NSTimer *scrollTimer;
@property (nonatomic, retain) NSString *loopedText;
@property (nonatomic, assign) CGFloat loopedTextCycleWidth;

@end

@implementation TickerView

- (instancetype)initWithFont:(NSFont *)font
{
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        self.font = font;
        _scrollSpeed = TickerScrollSpeedNormal;
    }
    return self;
}

- (void)dealloc
{
    [_scrollTimer invalidate];
    [_scrollTimer release];
    [_font release];
    [_loopedText release];
    [_text release];
    [super dealloc];
}

- (NSView *)hitTest:(NSPoint)point
{
    // Always pass clicks through to the status item button underneath,
    // so the existing click-to-open-menu behavior is untouched.
    return nil;
}

+ (CGFloat)widthInPointsForCharacterCount:(NSInteger)characterCount font:(NSFont *)font
{
    CGFloat glyphWidth = [@"0" sizeWithAttributes:@{NSFontAttributeName: font}].width;
    return (glyphWidth * characterCount) + (kTickerHorizontalPadding * 2.0);
}

- (void)setFixedWidthInCharacters:(NSInteger)characterCount
{
    self.fixedWidth = [TickerView widthInPointsForCharacterCount:characterCount font:self.font];

    NSRect frame = self.frame;
    frame.size.width = self.fixedWidth;
    self.frame = frame;

    [self reevaluateScrolling];
}

- (void)setText:(NSString *)text
{
    if (_text == text || [_text isEqualToString:text]) {
        return;
    }
    _text = [text copy];
    self.scrollOffset = 0;
    [self reevaluateScrolling];
}

- (void)setHighlighted:(BOOL)highlighted
{
    if (_highlighted == highlighted) {
        return;
    }
    _highlighted = highlighted;
    [self setNeedsDisplay:YES];
}

- (CGFloat)scrollSpeedPointsPerSecond
{
    switch (self.scrollSpeed) {
        case TickerScrollSpeedSlow:
            return kScrollSpeedSlowPointsPerSecond;
        case TickerScrollSpeedFast:
            return kScrollSpeedFastPointsPerSecond;
        case TickerScrollSpeedNormal:
            return kScrollSpeedNormalPointsPerSecond;
    }
}

- (void)reevaluateScrolling
{
    NSString *text = self.text ?: @"";
    NSDictionary *attributes = @{NSFontAttributeName: self.font};
    CGFloat textWidth = [text sizeWithAttributes:attributes].width;
    CGFloat availableWidth = self.fixedWidth - (kTickerHorizontalPadding * 2.0);
    BOOL needsScrolling = textWidth > availableWidth;

    if (needsScrolling) {
        self.loopedText = [NSString stringWithFormat:@"%@%@%@", text, kTickerScrollGap, text];
        CGFloat gapWidth = [kTickerScrollGap sizeWithAttributes:attributes].width;
        self.loopedTextCycleWidth = textWidth + gapWidth;
        [self startScrollTimer];
    } else {
        self.loopedText = text;
        self.loopedTextCycleWidth = 0;
        [self stopScrollTimer];
    }

    [self setNeedsDisplay:YES];
}

- (void)startScrollTimer
{
    if (self.scrollTimer) {
        return;
    }
    self.scrollTimer = [NSTimer scheduledTimerWithTimeInterval:kTickerTimerInterval
                                                         target:self
                                                       selector:@selector(scrollTimerDidFire:)
                                                       userInfo:nil
                                                        repeats:YES];
}

- (void)stopScrollTimer
{
    [self.scrollTimer invalidate];
    self.scrollTimer = nil;
    self.scrollOffset = 0;
}

- (void)scrollTimerDidFire:(NSTimer *)timer
{
    self.scrollOffset += [self scrollSpeedPointsPerSecond] * kTickerTimerInterval;
    if (self.loopedTextCycleWidth > 0 && self.scrollOffset >= self.loopedTextCycleWidth) {
        self.scrollOffset -= self.loopedTextCycleWidth;
    }
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];

    if (!self.highlighted) {
        NSBezierPath *backgroundPath = [NSBezierPath bezierPathWithRoundedRect:self.bounds
                                                                        xRadius:kTickerCornerRadius
                                                                        yRadius:kTickerCornerRadius];
        [[NSColor quaternaryLabelColor] setFill];
        [backgroundPath fill];
    }

    NSColor *textColor = self.highlighted ? [NSColor selectedMenuItemTextColor] : [NSColor labelColor];
    NSDictionary *attributes = @{
        NSFontAttributeName: self.font,
        NSForegroundColorAttributeName: textColor,
    };

    NSRectClip(self.bounds);

    NSString *displayString = self.loopedText ?: @"";
    NSSize textSize = [displayString sizeWithAttributes:attributes];
    CGFloat y = (self.bounds.size.height - textSize.height) / 2.0;
    CGFloat x = kTickerHorizontalPadding - self.scrollOffset;

    [displayString drawAtPoint:NSMakePoint(x, y) withAttributes:attributes];
}

@end
```

- [ ] **Step 3: Register the two new files in the Xcode project**

Three fresh, unique 24-character hex IDs to use (already checked for
collisions against the current `project.pbxproj`):

- `D86E0CD16E744073ADF9C61E` — `TickerView.h` file reference
- `A6F6A24CF1BC4FDDBAA7C860` — `TickerView.m` file reference
- `4B9859C16F054B8180035ABB` — `TickerView.m in Sources` build file

Open `Menu Bar Ticker.xcodeproj/project.pbxproj` and make these four edits:

**(a) `PBXBuildFile` section** — add a line right after the `AppDelegate.m in Sources` entry:

```
old:
		4CC719F5157C1FD7008976AD /* AppDelegate.m in Sources */ = {isa = PBXBuildFile; fileRef = 4CC719F4157C1FD7008976AD /* AppDelegate.m */; };
/* End PBXBuildFile section */

new:
		4CC719F5157C1FD7008976AD /* AppDelegate.m in Sources */ = {isa = PBXBuildFile; fileRef = 4CC719F4157C1FD7008976AD /* AppDelegate.m */; };
		4B9859C16F054B8180035ABB /* TickerView.m in Sources */ = {isa = PBXBuildFile; fileRef = A6F6A24CF1BC4FDDBAA7C860 /* TickerView.m */; };
/* End PBXBuildFile section */
```

**(b) `PBXFileReference` section** — add two lines right after the `AppDelegate.m` file reference:

```
old:
		4CC719F4157C1FD7008976AD /* AppDelegate.m */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.objc; path = AppDelegate.m; sourceTree = "<group>"; };
		4CC71A16157C2A59008976AD /* ScriptingBridge.framework */ = ...

new:
		4CC719F4157C1FD7008976AD /* AppDelegate.m */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.objc; path = AppDelegate.m; sourceTree = "<group>"; };
		D86E0CD16E744073ADF9C61E /* TickerView.h */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.h; path = TickerView.h; sourceTree = "<group>"; };
		A6F6A24CF1BC4FDDBAA7C860 /* TickerView.m */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.objc; path = TickerView.m; sourceTree = "<group>"; };
		4CC71A16157C2A59008976AD /* ScriptingBridge.framework */ = ...
```

(Keep the rest of that line — `ScriptingBridge.framework` — unchanged; only inserting the two new lines above it.)

**(c) `PBXGroup` section** — add the two files to the `MenubarTicker` group's `children`:

```
old:
			4CC719E7157C1FD7008976AD /* MenubarTicker */ = {
				isa = PBXGroup;
				children = (
					4CC719F3157C1FD7008976AD /* AppDelegate.h */,
					4CC719F4157C1FD7008976AD /* AppDelegate.m */,
					0005E3B923DE30AE002FC513 /* Music.h */,

new:
			4CC719E7157C1FD7008976AD /* MenubarTicker */ = {
				isa = PBXGroup;
				children = (
					4CC719F3157C1FD7008976AD /* AppDelegate.h */,
					4CC719F4157C1FD7008976AD /* AppDelegate.m */,
					D86E0CD16E744073ADF9C61E /* TickerView.h */,
					A6F6A24CF1BC4FDDBAA7C860 /* TickerView.m */,
					0005E3B923DE30AE002FC513 /* Music.h */,
```

**(d) `PBXSourcesBuildPhase` section** — add the new build file to `files`:

```
old:
				files = (
					4CC719EE157C1FD7008976AD /* main.m in Sources */,
					4CC719F5157C1FD7008976AD /* AppDelegate.m in Sources */,
				);

new:
				files = (
					4CC719EE157C1FD7008976AD /* main.m in Sources */,
					4CC719F5157C1FD7008976AD /* AppDelegate.m in Sources */,
					4B9859C16F054B8180035ABB /* TickerView.m in Sources */,
				);
```

- [ ] **Step 4: Build and verify it compiles**

Run:
```bash
xcodebuild -project "Menu Bar Ticker.xcodeproj" -scheme "Menu Bar Ticker" -configuration Debug build
```
Expected: `** BUILD SUCCEEDED **`. `TickerView` isn't used anywhere yet, so the app's behavior is unchanged from before this task — this step only confirms the new files compile and are correctly wired into the project.

- [ ] **Step 5: Commit**

```bash
git add MenubarTicker/TickerView.h MenubarTicker/TickerView.m "Menu Bar Ticker.xcodeproj/project.pbxproj"
git commit -m "Add TickerView: fixed-width, scrolling, highlightable text view"
```

---

### Task 2: Wire `TickerView` into `AppDelegate` (fixed-width box, static + scrolling text)

**Files:**
- Modify: `MenubarTicker/AppDelegate.m`

**Interfaces:**
- Consumes: `TickerView` from Task 1 (`initWithFont:`, `text`, `fixedWidth`, `setFixedWidthInCharacters:`).
- Produces: `AppDelegate.tickerView` (private property), used by Tasks 3-5.

- [ ] **Step 1: Import `TickerView.h` and add the `tickerView` property**

In `AppDelegate.m`, change:

```objc
old:
#import "AppDelegate.h"

#import "Music.h"
#import "Spotify.h"

new:
#import "AppDelegate.h"

#import "Music.h"
#import "Spotify.h"
#import "TickerView.h"
```

```objc
old:
@property (nonatomic, retain) NSStatusItem *statusItem;
@property (nonatomic, retain) NSTimer *timer;

@end

new:
@property (nonatomic, retain) NSStatusItem *statusItem;
@property (nonatomic, retain) NSTimer *timer;
@property (nonatomic, retain) TickerView *tickerView;

@end
```

- [ ] **Step 2: Release it in `dealloc`**

```objc
old:
    self.statusItem = nil;
    self.statusMenu = nil;
    
    [self.timer invalidate];
    self.timer = nil;
    
    [super dealloc];

new:
    self.statusItem = nil;
    self.statusMenu = nil;
    self.tickerView = nil;
    
    [self.timer invalidate];
    self.timer = nil;
    
    [super dealloc];
```

- [ ] **Step 3: Build and install `TickerView` in `awakeFromNib`**

```objc
old:
- (void)awakeFromNib
{
    self.music = [SBApplication applicationWithBundleIdentifier:@"com.apple.music"];
    self.spotify = [SBApplication applicationWithBundleIdentifier:@"com.spotify.client"];
    
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.menu = self.statusMenu;
    self.statusItem.button.toolTip = @"Menu Bar Ticker";
    
    [self updateTrackInfo];
}

new:
- (void)awakeFromNib
{
    self.music = [SBApplication applicationWithBundleIdentifier:@"com.apple.music"];
    self.spotify = [SBApplication applicationWithBundleIdentifier:@"com.spotify.client"];
    
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.menu = self.statusMenu;
    self.statusItem.button.toolTip = @"Menu Bar Ticker";
    self.statusItem.button.title = @"";

    NSFont *tickerFont = [NSFont menuBarFontOfSize:0];
    self.tickerView = [[[TickerView alloc] initWithFont:tickerFont] autorelease];
    [self.tickerView setFixedWidthInCharacters:30];

    NSRect tickerFrame = NSMakeRect(0, 0, self.tickerView.fixedWidth, self.statusItem.button.bounds.size.height);
    self.tickerView.frame = tickerFrame;
    self.tickerView.autoresizingMask = NSViewHeightSizable;
    [self.statusItem.button addSubview:self.tickerView];

    self.statusItem.length = self.tickerView.fixedWidth;
    
    [self updateTrackInfo];
}
```

- [ ] **Step 4: Feed track text to the ticker instead of the button title**

```objc
old:
    statusItem.button.title = currentTrack
        ? [NSString stringWithFormat:@"%@ - %@", [currentTrack artist], [currentTrack name]]
        : @"♫";

new:
    self.tickerView.text = currentTrack
        ? [NSString stringWithFormat:@"%@ - %@", [currentTrack artist], [currentTrack name]]
        : @"♫";
```

- [ ] **Step 5: Build**

```bash
xcodebuild -project "Menu Bar Ticker.xcodeproj" -scheme "Menu Bar Ticker" -configuration Debug build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Manually verify in the running app**

```bash
open "$HOME/Library/Developer/Xcode/DerivedData/Menu_Bar_Ticker-"*/Build/Products/Debug/"Menu Bar Ticker.app"
```

Check:
- The menu bar item shows a faint rounded-rect box of fixed width, whether idle ("♫") or a track is playing.
- Short "Artist - Title" text sits left-aligned, static, inside the box.
- To see the scrolling behavior without needing a real long track name, temporarily test with a long string: pause the app, or use `lldb`/a temporary one-line edit to set `self.tickerView.text = @"A Very Long Artist Name Indeed - An Extremely Long Song Title For Testing";` in `updateTrackInfo`, rebuild, confirm it scrolls left continuously with a visible gap and loops with no jump, then revert that temporary line before continuing.
- Clicking the item still opens `statusMenu` (highlight styling is fixed in Task 3, not yet — that's fine for this check).

- [ ] **Step 7: Commit**

```bash
git add MenubarTicker/AppDelegate.m
git commit -m "Replace variable-width button title with fixed-width TickerView"
```

---

### Task 3: Preserve native highlight appearance when the status menu opens

**Files:**
- Modify: `MenubarTicker/AppDelegate.m`

**Interfaces:**
- Consumes: `TickerView.highlighted` (Task 1).
- Produces: `AppDelegate` conforms to `NSMenuDelegate`; `statusMenu.delegate == self`. No new symbols consumed by later tasks.

- [ ] **Step 1: Conform to `NSMenuDelegate` and set the delegate**

```objc
old:
@interface AppDelegate ()

@property (nonatomic, retain) MusicApplication *music;

new:
@interface AppDelegate () <NSMenuDelegate>

@property (nonatomic, retain) MusicApplication *music;
```

```objc
old:
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.menu = self.statusMenu;
    self.statusItem.button.toolTip = @"Menu Bar Ticker";
    self.statusItem.button.title = @"";

new:
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.menu = self.statusMenu;
    self.statusItem.menu.delegate = self;
    self.statusItem.button.toolTip = @"Menu Bar Ticker";
    self.statusItem.button.title = @"";
```

- [ ] **Step 2: Add the two delegate methods**

Add before the final `@end` in `AppDelegate.m`:

```objc
- (void)menuWillOpen:(NSMenu *)menu
{
    if (menu == self.statusMenu) {
        self.tickerView.highlighted = YES;
    }
}

- (void)menuDidClose:(NSMenu *)menu
{
    if (menu == self.statusMenu) {
        self.tickerView.highlighted = NO;
    }
}
```

- [ ] **Step 3: Build**

```bash
xcodebuild -project "Menu Bar Ticker.xcodeproj" -scheme "Menu Bar Ticker" -configuration Debug build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manually verify**

Run the app, click the status item to open its menu: the faint background should disappear and the text should switch to a legible, contrasting color while the menu is open. Close the menu (click elsewhere or press Escape): background and text color should revert immediately.

- [ ] **Step 5: Commit**

```bash
git add MenubarTicker/AppDelegate.m
git commit -m "Mimic native highlight appearance in TickerView while status menu is open"
```

---

### Task 4: Add the "Scroll Speed" submenu (Slow/Normal/Fast), persisted

**Files:**
- Modify: `MenubarTicker/AppDelegate.m`

**Interfaces:**
- Consumes: `TickerScrollSpeed` enum and `TickerView.scrollSpeed` (Task 1).
- Produces: `AppDelegate.scrollSpeedMenuItems` (private), `-configureScrollSpeedMenu`, `-selectScrollSpeed:`, `-updateScrollSpeedMenuCheckmarks` — not consumed by later tasks, but Task 5 follows the same pattern for a second submenu, so keep names/shape consistent for a reviewer comparing the two.

- [ ] **Step 1: Add the defaults key constant and the menu items property**

```objc
old:
const NSTimeInterval kPollingInterval = 10.0;


@interface AppDelegate () <NSMenuDelegate>

@property (nonatomic, retain) MusicApplication *music;

new:
const NSTimeInterval kPollingInterval = 10.0;
static NSString * const kScrollSpeedDefaultsKey = @"TickerScrollSpeed";


@interface AppDelegate () <NSMenuDelegate>

@property (nonatomic, retain) NSArray<NSMenuItem *> *scrollSpeedMenuItems;

@property (nonatomic, retain) MusicApplication *music;
```

(This step assumes Task 3 already ran, so `<NSMenuDelegate>` is already present — only the constant line and the `scrollSpeedMenuItems` property are new here.)

- [ ] **Step 2: Release it in `dealloc`**

```objc
old:
    self.statusItem = nil;
    self.statusMenu = nil;
    self.tickerView = nil;

new:
    self.statusItem = nil;
    self.statusMenu = nil;
    self.tickerView = nil;
    self.scrollSpeedMenuItems = nil;
```

- [ ] **Step 3: Read the persisted speed at launch and build the submenu**

```objc
old:
    self.statusItem.length = self.tickerView.fixedWidth;
    
    [self updateTrackInfo];
}

new:
    self.statusItem.length = self.tickerView.fixedWidth;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    TickerScrollSpeed initialScrollSpeed = [defaults objectForKey:kScrollSpeedDefaultsKey]
        ? (TickerScrollSpeed)[defaults integerForKey:kScrollSpeedDefaultsKey]
        : TickerScrollSpeedNormal;
    self.tickerView.scrollSpeed = initialScrollSpeed;
    [self configureScrollSpeedMenu];

    [self updateTrackInfo];
}
```

- [ ] **Step 4: Add the submenu-building, checkmark, and action methods**

Add before the final `@end` in `AppDelegate.m`:

```objc
- (void)configureScrollSpeedMenu
{
    NSMenuItem *slowItem = [[[NSMenuItem alloc] initWithTitle:@"Slow" action:@selector(selectScrollSpeed:) keyEquivalent:@""] autorelease];
    slowItem.target = self;
    slowItem.tag = TickerScrollSpeedSlow;

    NSMenuItem *normalItem = [[[NSMenuItem alloc] initWithTitle:@"Normal" action:@selector(selectScrollSpeed:) keyEquivalent:@""] autorelease];
    normalItem.target = self;
    normalItem.tag = TickerScrollSpeedNormal;

    NSMenuItem *fastItem = [[[NSMenuItem alloc] initWithTitle:@"Fast" action:@selector(selectScrollSpeed:) keyEquivalent:@""] autorelease];
    fastItem.target = self;
    fastItem.tag = TickerScrollSpeedFast;

    self.scrollSpeedMenuItems = @[slowItem, normalItem, fastItem];

    NSMenu *scrollSpeedSubmenu = [[[NSMenu alloc] initWithTitle:@"Scroll Speed"] autorelease];
    for (NSMenuItem *item in self.scrollSpeedMenuItems) {
        [scrollSpeedSubmenu addItem:item];
    }

    NSMenuItem *scrollSpeedParentItem = [[[NSMenuItem alloc] initWithTitle:@"Scroll Speed" action:nil keyEquivalent:@""] autorelease];
    scrollSpeedParentItem.submenu = scrollSpeedSubmenu;

    [self.statusMenu insertItem:[NSMenuItem separatorItem] atIndex:0];
    [self.statusMenu insertItem:scrollSpeedParentItem atIndex:0];

    [self updateScrollSpeedMenuCheckmarks];
}

- (void)updateScrollSpeedMenuCheckmarks
{
    for (NSMenuItem *item in self.scrollSpeedMenuItems) {
        item.state = (item.tag == self.tickerView.scrollSpeed) ? NSControlStateValueOn : NSControlStateValueOff;
    }
}

- (void)selectScrollSpeed:(NSMenuItem *)sender
{
    TickerScrollSpeed speed = (TickerScrollSpeed)sender.tag;
    self.tickerView.scrollSpeed = speed;
    [[NSUserDefaults standardUserDefaults] setInteger:speed forKey:kScrollSpeedDefaultsKey];
    [self updateScrollSpeedMenuCheckmarks];
}
```

This leaves `self.statusMenu` as: `Scroll Speed` submenu, separator, `Quit` (inserting at index 0 puts the submenu above whatever was already there, then the separator is pushed back down to sit directly above `Quit`).

- [ ] **Step 5: Build**

```bash
xcodebuild -project "Menu Bar Ticker.xcodeproj" -scheme "Menu Bar Ticker" -configuration Debug build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Manually verify**

Run the app, open the status menu: confirm a "Scroll Speed" submenu appears above a separator above "Quit", with "Normal" checked. With a long (scrolling) track/test string showing, select "Fast" — the scroll should visibly speed up immediately. Quit and relaunch the app: confirm "Fast" is still checked.

- [ ] **Step 7: Commit**

```bash
git add MenubarTicker/AppDelegate.m
git commit -m "Add Scroll Speed menu (Slow/Normal/Fast), persisted in NSUserDefaults"
```

---

### Task 5: Add the "Display Width" submenu (Narrow/Normal/Wide), persisted

**Files:**
- Modify: `MenubarTicker/AppDelegate.m`

**Interfaces:**
- Consumes: `TickerView.setFixedWidthInCharacters:` and `.fixedWidth` (Task 1); the `defaults` local variable and `awakeFromNib` structure introduced in Task 4 Step 3.
- Produces: `AppDelegate.displayWidthMenuItems`, `.currentDisplayWidthCharacters` (private), `-configureDisplayWidthMenu`, `-selectDisplayWidth:`, `-updateDisplayWidthMenuCheckmarks`. Nothing later depends on these.

- [ ] **Step 1: Add constants and properties**

```objc
old:
const NSTimeInterval kPollingInterval = 10.0;
static NSString * const kScrollSpeedDefaultsKey = @"TickerScrollSpeed";

new:
const NSTimeInterval kPollingInterval = 10.0;
static NSString * const kScrollSpeedDefaultsKey = @"TickerScrollSpeed";
static NSString * const kDisplayWidthDefaultsKey = @"TickerDisplayWidthCharacters";
static const NSInteger kDisplayWidthNarrowCharacters = 20;
static const NSInteger kDisplayWidthNormalCharacters = 30;
static const NSInteger kDisplayWidthWideCharacters = 45;
```

```objc
old:
@property (nonatomic, retain) NSArray<NSMenuItem *> *scrollSpeedMenuItems;

@property (nonatomic, retain) MusicApplication *music;

new:
@property (nonatomic, retain) NSArray<NSMenuItem *> *scrollSpeedMenuItems;
@property (nonatomic, retain) NSArray<NSMenuItem *> *displayWidthMenuItems;
@property (nonatomic, assign) NSInteger currentDisplayWidthCharacters;

@property (nonatomic, retain) MusicApplication *music;
```

- [ ] **Step 2: Release the array in `dealloc`**

```objc
old:
    self.tickerView = nil;
    self.scrollSpeedMenuItems = nil;

new:
    self.tickerView = nil;
    self.scrollSpeedMenuItems = nil;
    self.displayWidthMenuItems = nil;
```

- [ ] **Step 3: Read the persisted width at launch instead of the hardcoded `30`, and build the submenu**

```objc
old:
    NSFont *tickerFont = [NSFont menuBarFontOfSize:0];
    self.tickerView = [[[TickerView alloc] initWithFont:tickerFont] autorelease];
    [self.tickerView setFixedWidthInCharacters:30];

    NSRect tickerFrame = NSMakeRect(0, 0, self.tickerView.fixedWidth, self.statusItem.button.bounds.size.height);
    self.tickerView.frame = tickerFrame;
    self.tickerView.autoresizingMask = NSViewHeightSizable;
    [self.statusItem.button addSubview:self.tickerView];

    self.statusItem.length = self.tickerView.fixedWidth;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    TickerScrollSpeed initialScrollSpeed = [defaults objectForKey:kScrollSpeedDefaultsKey]
        ? (TickerScrollSpeed)[defaults integerForKey:kScrollSpeedDefaultsKey]
        : TickerScrollSpeedNormal;
    self.tickerView.scrollSpeed = initialScrollSpeed;
    [self configureScrollSpeedMenu];

    [self updateTrackInfo];
}

new:
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    self.currentDisplayWidthCharacters = [defaults objectForKey:kDisplayWidthDefaultsKey]
        ? [defaults integerForKey:kDisplayWidthDefaultsKey]
        : kDisplayWidthNormalCharacters;

    NSFont *tickerFont = [NSFont menuBarFontOfSize:0];
    self.tickerView = [[[TickerView alloc] initWithFont:tickerFont] autorelease];
    [self.tickerView setFixedWidthInCharacters:self.currentDisplayWidthCharacters];

    NSRect tickerFrame = NSMakeRect(0, 0, self.tickerView.fixedWidth, self.statusItem.button.bounds.size.height);
    self.tickerView.frame = tickerFrame;
    self.tickerView.autoresizingMask = NSViewHeightSizable;
    [self.statusItem.button addSubview:self.tickerView];

    self.statusItem.length = self.tickerView.fixedWidth;

    TickerScrollSpeed initialScrollSpeed = [defaults objectForKey:kScrollSpeedDefaultsKey]
        ? (TickerScrollSpeed)[defaults integerForKey:kScrollSpeedDefaultsKey]
        : TickerScrollSpeedNormal;
    self.tickerView.scrollSpeed = initialScrollSpeed;
    [self configureScrollSpeedMenu];
    [self configureDisplayWidthMenu];

    [self updateTrackInfo];
}
```

- [ ] **Step 4: Add the submenu-building, checkmark, and action methods**

Add before the final `@end` in `AppDelegate.m`:

```objc
- (void)configureDisplayWidthMenu
{
    NSMenuItem *narrowItem = [[[NSMenuItem alloc] initWithTitle:@"Narrow" action:@selector(selectDisplayWidth:) keyEquivalent:@""] autorelease];
    narrowItem.target = self;
    narrowItem.tag = kDisplayWidthNarrowCharacters;

    NSMenuItem *normalItem = [[[NSMenuItem alloc] initWithTitle:@"Normal" action:@selector(selectDisplayWidth:) keyEquivalent:@""] autorelease];
    normalItem.target = self;
    normalItem.tag = kDisplayWidthNormalCharacters;

    NSMenuItem *wideItem = [[[NSMenuItem alloc] initWithTitle:@"Wide" action:@selector(selectDisplayWidth:) keyEquivalent:@""] autorelease];
    wideItem.target = self;
    wideItem.tag = kDisplayWidthWideCharacters;

    self.displayWidthMenuItems = @[narrowItem, normalItem, wideItem];

    NSMenu *displayWidthSubmenu = [[[NSMenu alloc] initWithTitle:@"Display Width"] autorelease];
    for (NSMenuItem *item in self.displayWidthMenuItems) {
        [displayWidthSubmenu addItem:item];
    }

    NSMenuItem *displayWidthParentItem = [[[NSMenuItem alloc] initWithTitle:@"Display Width" action:nil keyEquivalent:@""] autorelease];
    displayWidthParentItem.submenu = displayWidthSubmenu;

    [self.statusMenu insertItem:displayWidthParentItem atIndex:0];

    [self updateDisplayWidthMenuCheckmarks];
}

- (void)updateDisplayWidthMenuCheckmarks
{
    for (NSMenuItem *item in self.displayWidthMenuItems) {
        item.state = (item.tag == self.currentDisplayWidthCharacters) ? NSControlStateValueOn : NSControlStateValueOff;
    }
}

- (void)selectDisplayWidth:(NSMenuItem *)sender
{
    NSInteger characterCount = sender.tag;
    [self.tickerView setFixedWidthInCharacters:characterCount];
    self.statusItem.length = self.tickerView.fixedWidth;
    self.currentDisplayWidthCharacters = characterCount;
    [[NSUserDefaults standardUserDefaults] setInteger:characterCount forKey:kDisplayWidthDefaultsKey];
    [self updateDisplayWidthMenuCheckmarks];
}
```

Since `configureDisplayWidthMenu` runs after `configureScrollSpeedMenu` and also inserts at index 0, the final menu order is: `Display Width` submenu, `Scroll Speed` submenu, separator, `Quit`.

- [ ] **Step 5: Build**

```bash
xcodebuild -project "Menu Bar Ticker.xcodeproj" -scheme "Menu Bar Ticker" -configuration Debug build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Manually verify**

Run the app, open the status menu: confirm "Display Width" appears above "Scroll Speed", with "Normal" checked. Select "Narrow" while a track that fit at Normal width is showing: the menu bar item should visibly shrink (other menu bar icons shift left to fill the space), and if the text no longer fits, it should switch from static to scrolling. Select "Wide": the item should grow, and previously-scrolling text may become static if it now fits. Quit and relaunch: confirm the selection persisted.

- [ ] **Step 7: Commit**

```bash
git add MenubarTicker/AppDelegate.m
git commit -m "Add Display Width menu (Narrow/Normal/Wide), persisted in NSUserDefaults"
```

---

### Task 6: Full manual QA pass

**Files:** none (verification only).

- [ ] **Step 1: Build a Release configuration**

```bash
xcodebuild -project "Menu Bar Ticker.xcodeproj" -scheme "Menu Bar Ticker" -configuration Release build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 2: Run through the spec's full testing checklist**

Open the built app (`~/Library/Developer/Xcode/DerivedData/Menu_Bar_Ticker-*/Build/Products/Release/Menu Bar Ticker.app`) and confirm, in both Light and Dark mode (toggle via System Settings > Appearance):

1. Idle glyph and short titles sit static, left-aligned, on the faint background, inside the fixed-width box.
2. Long titles scroll left continuously and loop with a visible, evenly spaced gap — no visible jump/reset at the wrap point.
3. The menu bar item's width never changes across idle/short/long text (only via an explicit Display Width menu selection).
4. Changing "Scroll Speed" takes effect immediately on an in-progress scroll; the checkmark reflects the current selection and survives a relaunch.
5. Changing "Display Width" resizes the menu bar item immediately; other menu bar items shift to accommodate; text switches between static/scrolling correctly; the checkmark reflects the current selection and survives a relaunch.
6. Clicking the status item still opens `statusMenu`; while open, text inverts and the faint background is suppressed in favor of the native highlight.
7. Correct appearance in both Light and Dark mode.

- [ ] **Step 3: Note and fix any discrepancies found**

If any check fails, fix it in the relevant file (`TickerView.m` for rendering/animation issues, `AppDelegate.m` for wiring/menu issues), rebuild, and re-check. Commit each fix separately with a message describing what was wrong.
