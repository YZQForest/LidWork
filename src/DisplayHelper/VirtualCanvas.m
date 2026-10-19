#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <IOKit/pwr_mgt/IOPMLib.h>

@interface CGVirtualDisplayDescriptor : NSObject
@property(nonatomic) unsigned int vendorID, productID, serialNum;
@property(nonatomic) unsigned int maxPixelsWide, maxPixelsHigh;
@property(nonatomic) CGSize sizeInMillimeters;
@property(nonatomic) CGPoint redPrimary, greenPrimary, bluePrimary, whitePoint;
@property(nonatomic, copy) NSString *name;
@property(nonatomic, strong) dispatch_queue_t queue;
@end
@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(unsigned int)width height:(unsigned int)height refreshRate:(double)rate;
@end
@interface CGVirtualDisplaySettings : NSObject
@property(nonatomic) unsigned int hiDPI;
@property(nonatomic, strong) NSArray *modes;
@end
@interface CGVirtualDisplay : NSObject
@property(nonatomic, readonly) unsigned int displayID;
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@end

static CGVirtualDisplay *canvas;
static IOPMAssertionID awakeAssertion;

static void mirrorToCanvas(void) {
    CGDirectDisplayID displays[16];
    uint32_t count = 0;
    if (CGGetOnlineDisplayList(16, displays, &count) != kCGErrorSuccess) return;
    CGDirectDisplayID target = CGMainDisplayID();
    if (target == canvas.displayID) {
        for (uint32_t i = 0; i < count; i++) {
            if (CGDisplayIsBuiltin(displays[i])) { target = displays[i]; break; }
        }
        for (uint32_t i = 0; i < count; i++) {
            if (CGDisplayVendorNumber(displays[i]) == 0x6161706c && CGDisplayModelNumber(displays[i]) == 0x69506164) { target = displays[i]; break; }
        }
    }
    if (target == canvas.displayID || CGDisplayMirrorsDisplay(canvas.displayID) == target) return;
    CGDisplayConfigRef config = NULL;
    if (CGBeginDisplayConfiguration(&config) != kCGErrorSuccess || !config) return;
    CGError error = kCGErrorSuccess;
    if (CGDisplayMirrorsDisplay(target) == canvas.displayID) error = CGConfigureDisplayMirrorOfDisplay(config, target, kCGNullDirectDisplay);
    if (error == kCGErrorSuccess) error = CGConfigureDisplayMirrorOfDisplay(config, canvas.displayID, target);
    if (error == kCGErrorSuccess) error = CGCompleteDisplayConfiguration(config, kCGConfigureForSession);
    else CGCancelDisplayConfiguration(config);
    printf("mirror_configuration=%d\n", error);
    fflush(stdout);
}

int main(void) {
    @autoreleasepool {
        if (!NSClassFromString(@"CGVirtualDisplay")) { fprintf(stderr, "Virtual display unavailable.\n"); return 1; }
        CGVirtualDisplayDescriptor *descriptor = [CGVirtualDisplayDescriptor new];
        descriptor.name = @"合盖镜像画布";
        descriptor.queue = dispatch_get_main_queue();
        descriptor.vendorID = 0x4c57;
        descriptor.productID = 1;
        descriptor.serialNum = 2;
        descriptor.maxPixelsWide = 2940;
        descriptor.maxPixelsHigh = 1912;
        descriptor.sizeInMillimeters = CGSizeMake(300, 195);
        descriptor.whitePoint = CGPointMake(0.3127, 0.3290);
        descriptor.redPrimary = CGPointMake(0.64, 0.33);
        descriptor.greenPrimary = CGPointMake(0.30, 0.60);
        descriptor.bluePrimary = CGPointMake(0.15, 0.06);
        canvas = [[CGVirtualDisplay alloc] initWithDescriptor:descriptor];
        if (!canvas) { fprintf(stderr, "Could not create virtual display.\n"); return 1; }
        CGVirtualDisplaySettings *settings = [CGVirtualDisplaySettings new];
        settings.hiDPI = 1;
        settings.modes = @[[[CGVirtualDisplayMode alloc] initWithWidth:1470 height:956 refreshRate:60]];
        if (![canvas applySettings:settings]) { fprintf(stderr, "Could not set virtual display mode.\n"); return 1; }
        if (IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep, kIOPMAssertionLevelOn, CFSTR("LidWork display and Sidecar keeper"), &awakeAssertion) != kIOReturnSuccess) {
            fprintf(stderr, "Could not prevent display idle sleep.\n"); return 1;
        }
        printf("virtual_display_id=%u pid=%d\n", canvas.displayID, getpid());
        fflush(stdout);
        [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer) { mirrorToCanvas(); }];
        [[NSRunLoop mainRunLoop] run];
    }
    return 0;
}
