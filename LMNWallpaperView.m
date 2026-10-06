#import "LMNWallpaperView.h"
#import <AVFoundation/AVFoundation.h>
#import <notify.h>

#define kDomain @"com.lime.lumen"
#define kReloadNote "com.lime.lumen/reload"

static id LMNPref(NSString *key, id def) {
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)kDomain);
    return v ? CFBridgingRelease(v) : def;
}

static UIColor *HSB(CGFloat h, CGFloat s, CGFloat b) {
    h = h - floor(h);
    return [UIColor colorWithHue:h saturation:s brightness:b alpha:1];
}

// базовый цвет: пресет из настроек или свой HEX
static UIColor *LMNBaseColor(void) {
    NSDictionary *presets = @{ @"lime":   @"CCFF00",
                               @"mint":   @"00FF9C",
                               @"cyan":   @"00CFFF",
                               @"blue":   @"3A6BFF",
                               @"purple": @"9B4DFF",
                               @"pink":   @"FF4DB8",
                               @"orange": @"FF8A00",
                               @"red":    @"FF2D3B" };
    NSString *theme = LMNPref(@"colorTheme", @"lime");
    NSString *hex = [theme isEqualToString:@"custom"] ? LMNPref(@"customColor", @"") : presets[theme];
    hex = [hex stringByReplacingOccurrencesOfString:@"#" withString:@""];
    hex = [hex stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

    unsigned v = 0;
    if (hex.length != 6 || ![[NSScanner scannerWithString:hex] scanHexInt:&v]) v = 0xCCFF00;
    return [UIColor colorWithRed:((v >> 16) & 0xFF) / 255.0
                           green:((v >> 8) & 0xFF) / 255.0
                            blue:(v & 0xFF) / 255.0
                           alpha:1];
}

// палитра из 5 цветов: [0] основной, [1] и [2] соседние оттенки, [3] тёмный, [4] светлый
static NSArray *LMNPalette(void) {
    CGFloat h = 0, s = 0, b = 0, a = 0;
    [LMNBaseColor() getHue:&h saturation:&s brightness:&b alpha:&a];
    b = MAX(b, 0.6);
    return @[ HSB(h, s, b),
              HSB(h + 0.10, s, MAX(b * 0.85, 0.5)),
              HSB(h + 0.22, s, b),
              HSB(h + 0.10, s, 0.24),
              HSB(h, s * 0.45, 1.0) ];
}

static CGFloat R(CGFloat a, CGFloat b) {
    return a + (b - a) * ((CGFloat)arc4random() / (CGFloat)UINT32_MAX);
}

@implementation LMNWallpaperView {
    CALayer *_root;            // контейнер: фон + кружочки (его ставим на паузу)
    CAGradientLayer *_gradient;
    CALayer *_circles;
    AVPlayer *_player;
    AVPlayerLayer *_playerLayer;
    CGSize _builtSize;
    int _reloadToken, _blankToken;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        self.clipsToBounds = YES;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

        __weak typeof(self) weak = self;
        notify_register_dispatch(kReloadNote, &_reloadToken, dispatch_get_main_queue(), ^(int t){
            [weak reload];
        });
        // экран погас/включился - пауза, чтобы не тратить батарею
        notify_register_dispatch("com.apple.springboard.hasBlankedScreen", &_blankToken,
                                 dispatch_get_main_queue(), ^(int t){
            uint64_t state = 0;
            notify_get_state(t, &state);
            if (state) [weak pause]; else [weak play];
        });
        [self reload];
    }
    return self;
}

- (void)dealloc {
    notify_cancel(_reloadToken);
    notify_cancel(_blankToken);
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _root.frame = self.bounds;
    _gradient.frame = self.bounds;
    _playerLayer.frame = self.bounds;
    _circles.frame = self.bounds;

    // размер изменился (поворот и т.п.) - пересоздаём кружочки под новый размер
    if (_circles && !CGSizeEqualToSize(_builtSize, self.bounds.size)) {
        [self setupCircles];
    }
}

#pragma mark - Reload

- (void)reload {
    [self teardown];

    CFPreferencesAppSynchronize((__bridge CFStringRef)kDomain);
    BOOL enabled = [LMNPref(@"enabled", @YES) boolValue];
    self.hidden = !enabled;
    if (!enabled) return;

    _root = [CALayer layer];
    _root.frame = self.bounds;
    [self.layer addSublayer:_root];

    NSString *style = LMNPref(@"style", @"gradient");
    NSString *video = LMNPref(@"videoPath", @"");

    if ([style isEqualToString:@"video"] && video.length &&
        [[NSFileManager defaultManager] fileExistsAtPath:video]) {
        [self setupVideo:[NSURL fileURLWithPath:video]];
    } else {
        [self setupGradient];
    }

    if ([LMNPref(@"circles", @YES) boolValue]) {
        [self setupCircles];
    }
}

- (void)teardown {
    [_player pause];
    [_root removeAllAnimations];
    [_root removeFromSuperlayer];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _root = nil; _gradient = nil; _circles = nil;
    _player = nil; _playerLayer = nil;
    _builtSize = CGSizeZero;
}

#pragma mark - Gradient (по умолчанию)

- (void)setupGradient {
    _gradient = [CAGradientLayer layer];
    _gradient.frame = self.bounds;
    _gradient.startPoint = CGPointMake(0, 0);
    _gradient.endPoint = CGPointMake(1, 1);

    NSArray *pal = LMNPalette();
    UIColor *c1 = pal[0], *c2 = pal[1], *c3 = pal[2], *c4 = pal[3];
    NSArray *a = @[ (id)c1.CGColor, (id)c2.CGColor, (id)c3.CGColor, (id)c4.CGColor ];
    NSArray *b = @[ (id)c3.CGColor, (id)c4.CGColor, (id)c1.CGColor, (id)c2.CGColor ];
    NSArray *c = @[ (id)c4.CGColor, (id)c1.CGColor, (id)c2.CGColor, (id)c3.CGColor ];
    _gradient.colors = a;
    [_root addSublayer:_gradient];

    CAKeyframeAnimation *colors = [CAKeyframeAnimation animationWithKeyPath:@"colors"];
    colors.values = @[a, b, c, a];
    colors.duration = 14;
    colors.repeatCount = HUGE_VALF;
    colors.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [_gradient addAnimation:colors forKey:@"colors"];

    CAKeyframeAnimation *start = [CAKeyframeAnimation animationWithKeyPath:@"startPoint"];
    start.values = @[[NSValue valueWithCGPoint:CGPointMake(0,0)],
                     [NSValue valueWithCGPoint:CGPointMake(1,0)],
                     [NSValue valueWithCGPoint:CGPointMake(1,1)],
                     [NSValue valueWithCGPoint:CGPointMake(0,1)],
                     [NSValue valueWithCGPoint:CGPointMake(0,0)]];
    start.duration = 20; start.repeatCount = HUGE_VALF;
    [_gradient addAnimation:start forKey:@"start"];

    CAKeyframeAnimation *end = [CAKeyframeAnimation animationWithKeyPath:@"endPoint"];
    end.values = @[[NSValue valueWithCGPoint:CGPointMake(1,1)],
                   [NSValue valueWithCGPoint:CGPointMake(0,1)],
                   [NSValue valueWithCGPoint:CGPointMake(0,0)],
                   [NSValue valueWithCGPoint:CGPointMake(1,0)],
                   [NSValue valueWithCGPoint:CGPointMake(1,1)]];
    end.duration = 20; end.repeatCount = HUGE_VALF;
    [_gradient addAnimation:end forKey:@"end"];
}

#pragma mark - Плавающие кружочки

- (void)setupCircles {
    [_circles removeFromSuperlayer];
    CGSize size = self.bounds.size;
    _builtSize = size;
    if (size.width < 1 || size.height < 1 || !_root) return;

    NSInteger count = (NSInteger)lround([LMNPref(@"circleCount", @10) doubleValue]);
    CGFloat speed = [LMNPref(@"circleSpeed", @1) doubleValue];
    count = MAX(1, MIN(count, 30));
    speed = MAX(0.3, MIN(speed, 4));

    _circles = [CALayer layer];
    _circles.frame = self.bounds;
    [_root addSublayer:_circles];

    NSArray *pal = LMNPalette();
    NSArray *palette = @[ pal[0], pal[1], pal[2], pal[4], pal[0] ];

    for (NSInteger i = 0; i < count; i++) {
        CGFloat d = R(44, 170);
        UIColor *col = palette[i % palette.count];

        // мягкий "пузырь": лёгкая заливка, плотнее к краю, затухание наружу
        CAGradientLayer *c = [CAGradientLayer layer];
        c.type = @"radial"; // kCAGradientLayerRadial нет в публичном SDK
        c.bounds = CGRectMake(0, 0, d, d);
        c.startPoint = CGPointMake(0.5, 0.5);
        c.endPoint = CGPointMake(1, 1);
        c.colors = @[ (id)[col colorWithAlphaComponent:0.10].CGColor,
                      (id)[col colorWithAlphaComponent:R(0.28, 0.45)].CGColor,
                      (id)[col colorWithAlphaComponent:0.0].CGColor ];
        c.locations = @[ @0.0, @0.82, @1.0 ];
        c.shouldRasterize = YES;
        c.rasterizationScale = [UIScreen mainScreen].scale;

        CGPoint p0 = CGPointMake(R(0, size.width), R(0, size.height));
        c.position = p0;
        [_circles addSublayer:c];

        // замкнутая плавная траектория через несколько случайных точек
        CGPoint p1 = CGPointMake(R(0, size.width), R(0, size.height));
        CGPoint p2 = CGPointMake(R(0, size.width), R(0, size.height));
        UIBezierPath *path = [UIBezierPath bezierPath];
        [path moveToPoint:p0];
        [path addCurveToPoint:p1
                controlPoint1:CGPointMake(R(0, size.width), R(0, size.height))
                controlPoint2:CGPointMake(R(0, size.width), R(0, size.height))];
        [path addCurveToPoint:p2
                controlPoint1:CGPointMake(R(0, size.width), R(0, size.height))
                controlPoint2:CGPointMake(R(0, size.width), R(0, size.height))];
        [path addCurveToPoint:p0
                controlPoint1:CGPointMake(R(0, size.width), R(0, size.height))
                controlPoint2:CGPointMake(R(0, size.width), R(0, size.height))];

        CAKeyframeAnimation *move = [CAKeyframeAnimation animationWithKeyPath:@"position"];
        move.path = path.CGPath;
        move.duration = R(26, 55) / speed;
        move.repeatCount = HUGE_VALF;
        move.calculationMode = kCAAnimationPaced;
        // случайный сдвиг фазы, чтобы кружочки не стартовали синхронно
        move.timeOffset = R(0, move.duration);
        [c addAnimation:move forKey:@"move"];

        CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        pulse.fromValue = @(R(0.8, 0.95));
        pulse.toValue = @(R(1.05, 1.3));
        pulse.duration = R(4, 9) / speed;
        pulse.autoreverses = YES;
        pulse.repeatCount = HUGE_VALF;
        pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [c addAnimation:pulse forKey:@"pulse"];

        CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
        fade.fromValue = @(R(0.45, 0.7));
        fade.toValue = @1.0;
        fade.duration = R(3, 8) / speed;
        fade.autoreverses = YES;
        fade.repeatCount = HUGE_VALF;
        [c addAnimation:fade forKey:@"fade"];
    }
}

#pragma mark - Video

- (void)setupVideo:(NSURL *)url {
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
    _player = [AVPlayer playerWithPlayerItem:item];
    _player.muted = YES;
    _player.actionAtItemEnd = AVPlayerActionAtItemEndNone;

    _playerLayer = [AVPlayerLayer playerLayerWithPlayer:_player];
    _playerLayer.frame = self.bounds;
    _playerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [_root addSublayer:_playerLayer];

    // зацикливание (AVPlayerLooper есть только с iOS 10)
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(videoEnded:)
        name:AVPlayerItemDidPlayToEndTimeNotification object:item];
    [_player play];
}

- (void)videoEnded:(NSNotification *)n {
    [_player seekToTime:kCMTimeZero];
    [_player play];
}

#pragma mark - Control

- (void)play {
    [_player play];
    if (_root && _root.speed == 0) {
        CFTimeInterval paused = _root.timeOffset;
        _root.speed = 1;
        _root.timeOffset = 0;
        _root.beginTime = 0;
        CFTimeInterval since = [_root convertTime:CACurrentMediaTime() fromLayer:nil] - paused;
        _root.beginTime = since;
    }
}

- (void)pause {
    [_player pause];
    if (_root && _root.speed != 0) {
        CFTimeInterval t = [_root convertTime:CACurrentMediaTime() fromLayer:nil];
        _root.speed = 0;
        _root.timeOffset = t;
    }
}

@end
