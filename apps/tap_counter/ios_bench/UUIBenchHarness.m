/**
 * Cross-framework counter benchmark harness — Valdi's iOS cell
 * (universal_ui/docs/benchmarks.md#ios). Protocol-compatible with the UUI
 * cells' harness: armed by the UUI_BENCH=1 environment (devicectl:
 * DEVICECTL_CHILD_UUI_BENCH=1), writes Documents/bench.json
 * {run, startupMs, launchToContentMs, taps, tapMedianMs, tapMeanMs}.
 *
 * Startup anchor: process start (sysctl p_starttime, dyld included) → the
 * completion of the CA commit that first contains BOTH the counter label
 * (SCValdiLabel is a UILabel: text prefix "Tapped ") and the #5A57D6 button —
 * detected by a main-runloop observer (order 0, ahead of Core Animation's
 * commit observer at 2,000,000) so the CATransaction completion attaches to
 * exactly that commit. Matches the UUI/RN cells' commit-anchored semantics.
 *
 * Tap anchor: trigger → completion of the commit containing the label update.
 * The trigger invokes the button's SCValdiTapGestureRecognizer
 * `triggerAtLocation:forState:` (state = ended) via NSInvocation — the same
 * native→JS→setState→render→native-view round trip a real touch performs.
 *
 * Pure runtime introspection (no Valdi headers), linked in with alwayslink so
 * the constructor always boots.
 */

#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <sys/sysctl.h>

static double UUIMsSinceProcessStart(void)
{
    struct kinfo_proc info;
    size_t size = sizeof(info);
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    if (sysctl(mib, 4, &info, &size, NULL, 0) != 0) {
        return -1;
    }
    struct timeval start = info.kp_proc.p_starttime;
    double startSec = (double)start.tv_sec + (double)start.tv_usec / 1e6;
    return ([NSDate date].timeIntervalSince1970 - startSec) * 1000.0;
}

@interface UUIBenchHarness : NSObject
@end

@implementation UUIBenchHarness {
    CFTimeInterval _launchedAt;
    double _startupMs;
    double _launchToContentMs;
    NSMutableArray<NSNumber *> *_taps;
    CFTimeInterval _pendingTapStart;
    NSString *_lastLabelText;
    NSInteger _tapsRemaining;
    CFRunLoopObserverRef _observer;
    BOOL _finished;
}

static UUIBenchHarness *sharedHarness;

+ (void)installIfRequested
{
    if (![[NSProcessInfo processInfo].environment[@"UUI_BENCH"] isEqualToString:@"1"]) {
        return;
    }
    // A fresh run must never be confused with a previous launch's file.
    NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory
                                                             inDomains:NSUserDomainMask].firstObject;
    [NSFileManager.defaultManager removeItemAtURL:[documents URLByAppendingPathComponent:@"bench.json"]
                                            error:NULL];
    sharedHarness = [[UUIBenchHarness alloc] init];
    [sharedHarness start];
}

- (void)start
{
    _launchedAt = CACurrentMediaTime();
    _startupMs = -1;
    _launchToContentMs = -1;
    _taps = [NSMutableArray array];
    _pendingTapStart = 0;
    _tapsRemaining = 15;

    __weak UUIBenchHarness *weakSelf = self;
    // Order 0 runs before CA's commit observer (2,000,000) in the same
    // before-waiting pass, so a completion block attached here belongs to the
    // commit that publishes what we just detected.
    _observer = CFRunLoopObserverCreateWithHandler(
        kCFAllocatorDefault, kCFRunLoopBeforeWaiting, true, 0,
        ^(CFRunLoopObserverRef obs, CFRunLoopActivity activity) {
            [weakSelf runLoopTick];
        });
    CFRunLoopAddObserver(CFRunLoopGetMain(), _observer, kCFRunLoopCommonModes);
}

- (UIWindow *)keyWindow
{
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            for (UIWindow *window in windowScene.windows) {
                if (window.isKeyWindow) {
                    return window;
                }
            }
            if (windowScene.windows.count > 0) {
                return windowScene.windows.firstObject;
            }
        }
    }
    return UIApplication.sharedApplication.windows.firstObject;
}

- (NSString *)findLabelIn:(UIView *)view
{
    if ([view isKindOfClass:[UILabel class]]) {
        NSString *text = ((UILabel *)view).text;
        if ([text hasPrefix:@"Tapped "]) {
            return text;
        }
    }
    for (UIView *sub in view.subviews) {
        NSString *found = [self findLabelIn:sub];
        if (found) {
            return found;
        }
    }
    return nil;
}

- (UIView *)findButtonIn:(UIView *)view
{
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (view.backgroundColor && [view.backgroundColor getRed:&r green:&g blue:&b alpha:&a]) {
        // #5A57D6-family.
        if (fabs(r - 90.0 / 255) < 0.1 && fabs(g - 87.0 / 255) < 0.1 && b > 0.7 && a > 0.9) {
            return view;
        }
    }
    for (UIView *sub in view.subviews) {
        UIView *found = [self findButtonIn:sub];
        if (found) {
            return found;
        }
    }
    return nil;
}

- (void)runLoopTick
{
    if (_finished) {
        return;
    }
    UIWindow *window = [self keyWindow];
    if (!window) {
        return;
    }
    if (_startupMs < 0) {
        NSString *label = [self findLabelIn:window];
        if (!label || ![self findButtonIn:window]) {
            return;
        }
        _lastLabelText = label;
        __weak UUIBenchHarness *weakSelf = self;
        [CATransaction setCompletionBlock:^{
            UUIBenchHarness *strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            strongSelf->_startupMs = UUIMsSinceProcessStart();
            strongSelf->_launchToContentMs = (CACurrentMediaTime() - strongSelf->_launchedAt) * 1000;
            NSLog(@"[bench] content frame: startup=%.1fms launch->content=%.1fms",
                  strongSelf->_startupMs, strongSelf->_launchToContentMs);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ [weakSelf tap]; });
        }];
        return;
    }
    if (_pendingTapStart > 0) {
        NSString *label = [self findLabelIn:window];
        if (label && ![label isEqualToString:_lastLabelText]) {
            _lastLabelText = label;
            CFTimeInterval t0 = _pendingTapStart;
            _pendingTapStart = 0;
            __weak UUIBenchHarness *weakSelf = self;
            [CATransaction setCompletionBlock:^{
                UUIBenchHarness *strongSelf = weakSelf;
                if (!strongSelf) {
                    return;
                }
                [strongSelf->_taps addObject:@((CACurrentMediaTime() - t0) * 1000)];
                if (strongSelf->_tapsRemaining > 0) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)),
                                   dispatch_get_main_queue(), ^{ [weakSelf tap]; });
                } else {
                    [strongSelf finish];
                }
            }];
        }
    }
}

- (void)tap
{
    if (_finished) {
        return;
    }
    UIWindow *window = [self keyWindow];
    UIView *button = window ? [self findButtonIn:window] : nil;
    if (!button) {
        NSLog(@"[bench] no button to tap");
        [self finish];
        return;
    }
    UIGestureRecognizer *tapRecognizer = nil;
    for (UIGestureRecognizer *recognizer in button.gestureRecognizers) {
        if ([recognizer isKindOfClass:[UITapGestureRecognizer class]]) {
            tapRecognizer = recognizer;
            break;
        }
    }
    SEL trigger = NSSelectorFromString(@"triggerAtLocation:forState:");
    if (!tapRecognizer || ![tapRecognizer respondsToSelector:trigger]) {
        NSLog(@"[bench] no triggerable tap recognizer (found=%@)", tapRecognizer);
        [self finish];
        return;
    }
    _tapsRemaining -= 1;
    _pendingTapStart = CACurrentMediaTime();
    NSMethodSignature *signature = [tapRecognizer methodSignatureForSelector:trigger];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = tapRecognizer;
    invocation.selector = trigger;
    CGPoint location = CGPointMake(CGRectGetMidX(button.bounds), CGRectGetMidY(button.bounds));
    NSInteger state = UIGestureRecognizerStateEnded;
    [invocation setArgument:&location atIndex:2];
    [invocation setArgument:&state atIndex:3];
    [invocation invoke];
    // Watchdog: a lost update must not stall the run.
    __weak UUIBenchHarness *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        UUIBenchHarness *strongSelf = weakSelf;
        if (strongSelf && strongSelf->_pendingTapStart > 0) {
            strongSelf->_pendingTapStart = 0;
            [strongSelf finish];
        }
    });
}

- (void)finish
{
    if (_finished) {
        return;
    }
    _finished = YES;
    if (_observer) {
        CFRunLoopRemoveObserver(CFRunLoopGetMain(), _observer, kCFRunLoopCommonModes);
    }
    NSArray<NSNumber *> *sorted = [_taps sortedArrayUsingSelector:@selector(compare:)];
    double median = sorted.count ? sorted[sorted.count / 2].doubleValue : 0;
    double mean = 0;
    for (NSNumber *tap in _taps) {
        mean += tap.doubleValue;
    }
    mean = _taps.count ? mean / _taps.count : 0;
    NSMutableArray *rounded = [NSMutableArray array];
    for (NSNumber *tap in _taps) {
        [rounded addObject:@(round(tap.doubleValue * 10) / 10)];
    }
    NSDictionary *payload = @{
        @"run" : [NSProcessInfo processInfo].environment[@"UUI_BENCH_RUN"] ?: @"",
        @"startupMs" : @(_startupMs),
        @"launchToContentMs" : @(_launchToContentMs),
        @"taps" : rounded,
        @"tapMedianMs" : @(round(median * 10) / 10),
        @"tapMeanMs" : @(round(mean * 10) / 10),
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:NULL];
    NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory
                                                             inDomains:NSUserDomainMask].firstObject;
    [data writeToURL:[documents URLByAppendingPathComponent:@"bench.json"] atomically:YES];
    NSLog(@"[bench] done: %@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
}

@end

__attribute__((constructor)) static void UUIBenchBoot(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [UUIBenchHarness installIfRequested];
    });
}
