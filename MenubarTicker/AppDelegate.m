#import "AppDelegate.h"

#import "Music.h"
#import "Spotify.h"
#import "TickerView.h"

const NSTimeInterval kPollingInterval = 10.0;


@interface AppDelegate ()

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

@end
