#import <UIKit/UIKit.h>
#import "LMNWallpaperView.h"

#define kLumenTag 0x4C554D

@interface SBFWallpaperView : UIView
@end

%hook SBFWallpaperView

- (void)layoutSubviews {
    %orig;

    LMNWallpaperView *lumen = (LMNWallpaperView *)[self viewWithTag:kLumenTag];
    if (!lumen) {
        lumen = [[LMNWallpaperView alloc] initWithFrame:self.bounds];
        lumen.tag = kLumenTag;
        [self addSubview:lumen];
    }
    lumen.frame = self.bounds;
}

%end
