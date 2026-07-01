#import "AppDelegate.h"

#import "Music.h"
#import "Spotify.h"
#import "TickerView.h"

const NSTimeInterval kPollingInterval = 10.0;
static NSString * const kScrollSpeedDefaultsKey = @"TickerScrollSpeed";
static NSString * const kDisplayWidthDefaultsKey = @"TickerDisplayWidthCharacters";
static const NSInteger kDisplayWidthNarrowCharacters = 20;
static const NSInteger kDisplayWidthNormalCharacters = 30;
static const NSInteger kDisplayWidthWideCharacters = 45;


@interface AppDelegate () <NSMenuDelegate>

@property (nonatomic, retain) NSArray<NSMenuItem *> *scrollSpeedMenuItems;
@property (nonatomic, retain) NSArray<NSMenuItem *> *displayWidthMenuItems;
@property (nonatomic, assign) NSInteger currentDisplayWidthCharacters;

@property (nonatomic, retain) MusicApplication *music;
@property (nonatomic, retain) SpotifyApplication *spotify;

@property (nonatomic, retain) NSStatusItem *statusItem;
@property (nonatomic, retain) NSTimer *timer;
@property (nonatomic, retain) TickerView *tickerView;

@end


@implementation AppDelegate

@synthesize music;
@synthesize spotify;

@synthesize statusItem;
@synthesize statusMenu;
@synthesize timer;

- (void)dealloc
{
    [[NSDistributedNotificationCenter defaultCenter] removeObserver:self name:nil object:nil];

    self.music = nil;
    self.spotify = nil;
    
    self.statusItem = nil;
    self.statusMenu = nil;
    self.tickerView = nil;
    self.scrollSpeedMenuItems = nil;
    self.displayWidthMenuItems = nil;

    [self.timer invalidate];
    self.timer = nil;

    [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    self.timer = [NSTimer scheduledTimerWithTimeInterval:kPollingInterval
                                                  target:self
                                                selector:@selector(timerDidFire:)
                                                userInfo:nil
                                                 repeats:YES];

    // As of February 2021, notifications from Music.app are still coming in through
    // com.apple.iTunes.playerInfo and not com.apple.music.playerInfo.
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self
                                                        selector:@selector(didReceivePlayerNotification:)
                                                            name:@"com.apple.iTunes.playerInfo"
                                                          object:nil];

    [[NSDistributedNotificationCenter defaultCenter] addObserver:self
                                                        selector:@selector(didReceivePlayerNotification:)
                                                            name:@"com.apple.music.playerInfo"
                                                          object:nil];
    
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self
                                                        selector:@selector(didReceivePlayerNotification:)
                                                            name:@"com.spotify.client.PlaybackStateChanged"
                                                          object:nil];
}

- (void)awakeFromNib
{
    self.music = [SBApplication applicationWithBundleIdentifier:@"com.apple.music"];
    self.spotify = [SBApplication applicationWithBundleIdentifier:@"com.spotify.client"];
    
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.menu = self.statusMenu;
    self.statusItem.menu.delegate = self;
    self.statusItem.button.toolTip = @"Menu Bar Ticker";
    self.statusItem.button.title = @"";

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


- (void)updateTrackInfo
{
    id currentTrack = nil;
    
    if ([self.music isRunning] && [self.music playerState] == MusicEPlSPlaying) {
        currentTrack = [self.music currentTrack];
    } else if ([self.spotify isRunning] && [self.spotify playerState] == SpotifyEPlSPlaying) {
        currentTrack = [self.spotify currentTrack];
    }

    self.tickerView.text = currentTrack
        ? [NSString stringWithFormat:@"%@ - %@", [currentTrack artist], [currentTrack name]]
        : @"♫";
}

- (void)timerDidFire:(NSTimer *)theTimer
{
    [self updateTrackInfo];
}

- (void)didReceivePlayerNotification:(NSNotification *)notification
{
    [self updateTrackInfo];
}

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

@end
