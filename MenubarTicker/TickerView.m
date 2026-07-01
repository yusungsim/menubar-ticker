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

        // Status item subviews don't reliably receive
        // -viewDidChangeEffectiveAppearance when the system Light/Dark
        // setting changes, so fall back to the system notification
        // that's long been the standard workaround for this.
        [[NSDistributedNotificationCenter defaultCenter] addObserver:self
                                                             selector:@selector(interfaceThemeDidChange:)
                                                                 name:@"AppleInterfaceThemeChangedNotification"
                                                               object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSDistributedNotificationCenter defaultCenter] removeObserver:self name:nil object:nil];
    [_scrollTimer invalidate];
    [_scrollTimer release];
    [_font release];
    [_loopedText release];
    [_text release];
    [super dealloc];
}

- (void)interfaceThemeDidChange:(NSNotification *)notification
{
    [self setNeedsDisplay:YES];
}

- (NSView *)hitTest:(NSPoint)point
{
    // Always pass clicks through to the status item button underneath,
    // so the existing click-to-open-menu behavior is untouched.
    return nil;
}

- (void)viewDidChangeEffectiveAppearance
{
    [super viewDidChangeEffectiveAppearance];
    // drawRect: only re-resolves the dynamic system colors when it runs;
    // without this, a static (non-scrolling) ticker keeps showing stale
    // pixels from before a Light/Dark mode switch.
    [self setNeedsDisplay:YES];
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

    NSBezierPath *backgroundPath = [NSBezierPath bezierPathWithRoundedRect:self.bounds
                                                                    xRadius:kTickerCornerRadius
                                                                    yRadius:kTickerCornerRadius];
    NSColor *backgroundColor = self.highlighted ? [NSColor selectedContentBackgroundColor] : [NSColor quaternaryLabelColor];
    [backgroundColor setFill];
    [backgroundPath fill];

    NSColor *textColor = self.highlighted ? [NSColor alternateSelectedControlTextColor] : [NSColor labelColor];
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
