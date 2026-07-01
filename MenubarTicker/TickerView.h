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
