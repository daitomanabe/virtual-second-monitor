#import "VSMDisplayManager.h"
#import <dispatch/dispatch.h>
#import <math.h>

const NSUInteger VSMMaximumDisplayCount = 8;

VSMVirtualDisplayConfig VSMDefaultConfig(void) {
  VSMVirtualDisplayConfig config;
  config.width = 1920;
  config.height = 1080;
  config.ppi = 110;
  config.refreshRate = 60.0;
  config.hiDPI = NO;
  config.serialNumber = 0;
  config.vendorID = 505;
  config.productID = 22136;
  config.name = @"Virtual Monitor";
  return config;
}

unsigned int VSMAutoSerialNumber(void) {
  return 200000 + arc4random_uniform(700000);
}

static CGVirtualDisplay *VSMCreateVirtualDisplay(VSMVirtualDisplayConfig config, NSString **errorMessage) API_AVAILABLE(macos(10.14));
static CGVirtualDisplay *VSMCreateVirtualDisplay(VSMVirtualDisplayConfig config, NSString **errorMessage) {
  Class displayClass = NSClassFromString(@"CGVirtualDisplay");
  Class descriptorClass = NSClassFromString(@"CGVirtualDisplayDescriptor");
  Class settingsClass = NSClassFromString(@"CGVirtualDisplaySettings");
  Class modeClass = NSClassFromString(@"CGVirtualDisplayMode");

  if (!displayClass || !descriptorClass || !settingsClass || !modeClass) {
    if (errorMessage) {
      *errorMessage = @"CGVirtualDisplay is not available on this macOS build.";
    }
    return nil;
  }

  if (config.width < 160 || config.height < 120) {
    if (errorMessage) {
      *errorMessage = @"Resolution is too small.";
    }
    return nil;
  }

  if (config.ppi == 0) {
    if (errorMessage) {
      *errorMessage = @"PPI must be greater than zero.";
    }
    return nil;
  }

  if (config.hiDPI && (config.width % 2 != 0 || config.height % 2 != 0)) {
    if (errorMessage) {
      *errorMessage = @"HiDPI requires even width and height.";
    }
    return nil;
  }

  if (!isfinite(config.refreshRate) || config.refreshRate <= 0.0) {
    if (errorMessage) *errorMessage = @"Refresh rate must be a finite positive number.";
    return nil;
  }

  CGVirtualDisplayDescriptor *descriptor = [[CGVirtualDisplayDescriptor alloc] init];
  descriptor.name = config.name.length > 0 ? config.name : @"Virtual Monitor";
  descriptor.maxPixelsWide = config.width;
  descriptor.maxPixelsHigh = config.height;
  descriptor.sizeInMillimeters = CGSizeMake(25.4 * config.width / config.ppi,
                                             25.4 * config.height / config.ppi);
  descriptor.whitePoint = CGPointMake(0.3125, 0.3291);
  descriptor.bluePrimary = CGPointMake(0.1494, 0.0557);
  descriptor.greenPrimary = CGPointMake(0.2559, 0.6983);
  descriptor.redPrimary = CGPointMake(0.6797, 0.3203);
  descriptor.vendorID = config.vendorID;
  descriptor.productID = config.productID;

  unsigned int serialNumber = config.serialNumber > 0 ? config.serialNumber : VSMAutoSerialNumber();
  if ([descriptor respondsToSelector:@selector(setSerialNum:)]) {
    descriptor.serialNum = serialNumber;
  }
  if ([descriptor respondsToSelector:@selector(setSerialNumber:)]) {
    descriptor.serialNumber = serialNumber;
  }
  if ([descriptor respondsToSelector:@selector(setQueue:)]) {
    descriptor.queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
  }
  if ([descriptor respondsToSelector:@selector(setDispatchQueue:)]) {
    [descriptor setDispatchQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0)];
  }
  if ([descriptor respondsToSelector:@selector(setTerminationHandler:)]) {
    descriptor.terminationHandler = ^{};
  }

  CGVirtualDisplay *display = [[CGVirtualDisplay alloc] initWithDescriptor:descriptor];
  if (!display) {
    if (errorMessage) {
      *errorMessage = @"CGVirtualDisplay initWithDescriptor failed.";
    }
    return nil;
  }

  CGVirtualDisplaySettings *settings = [[CGVirtualDisplaySettings alloc] init];
  settings.hiDPI = config.hiDPI ? 1 : 0;
  if ([settings respondsToSelector:@selector(setRotation:)]) {
    settings.rotation = 0;
  }

  unsigned int modeWidth = config.hiDPI ? config.width / 2 : config.width;
  unsigned int modeHeight = config.hiDPI ? config.height / 2 : config.height;
  CGVirtualDisplayMode *mode = [[CGVirtualDisplayMode alloc] initWithWidth:modeWidth
                                                                    height:modeHeight
                                                               refreshRate:config.refreshRate];
  settings.modes = @[ mode ];

  if (![display applySettings:settings]) {
    if (errorMessage) {
      *errorMessage = @"CGVirtualDisplay applySettings failed.";
    }
    return nil;
  }

  return display;
}


@interface VSMManagedDisplay ()
@property(strong, nonatomic) CGVirtualDisplay *display;
@property(readwrite, nonatomic) CGDirectDisplayID displayID;
@property(readwrite, nonatomic) VSMVirtualDisplayConfig config;
@end
@implementation VSMManagedDisplay
@end

@implementation VSMDisplayManager {
  NSMutableArray<VSMManagedDisplay *> *_displays;
}

- (instancetype)init {
  self = [super init];
  if (self) _displays = [NSMutableArray array];
  return self;
}

- (NSArray<VSMManagedDisplay *> *)displays {
  return [_displays copy];
}

- (BOOL)serialIsInUse:(VSMVirtualDisplayConfig)config {
  for (VSMManagedDisplay *entry in _displays) {
    VSMVirtualDisplayConfig existing = entry.config;
    if (existing.serialNumber == config.serialNumber && existing.vendorID == config.vendorID &&
        existing.productID == config.productID) return YES;
  }
  CGDirectDisplayID online[128];
  uint32_t count = 0;
  if (CGGetOnlineDisplayList(128, online, &count) == kCGErrorSuccess) {
    for (uint32_t i = 0; i < count; i++) {
      if (CGDisplaySerialNumber(online[i]) == config.serialNumber &&
          CGDisplayVendorNumber(online[i]) == config.vendorID &&
          CGDisplayModelNumber(online[i]) == config.productID) return YES;
    }
  }
  return NO;
}

- (VSMManagedDisplay *)addDisplayWithConfig:(VSMVirtualDisplayConfig)config error:(NSString **)error {
  if (error) *error = nil;
  if (_displays.count >= VSMMaximumDisplayCount) {
    if (error) *error = @"Maximum of 8 virtual monitors reached. Remove a monitor before adding another.";
    return nil;
  }
  if (config.serialNumber == 0) {
    do { config.serialNumber = VSMAutoSerialNumber(); } while ([self serialIsInUse:config]);
  } else if ([self serialIsInUse:config]) {
    if (error) *error = @"This serial number is already in use. Leave it empty for an automatic serial.";
    return nil;
  }
  if (config.name.length == 0) config.name = @"Virtual Monitor";
  CGVirtualDisplay *display = VSMCreateVirtualDisplay(config, error);
  if (!display) return nil;
  VSMManagedDisplay *entry = [[VSMManagedDisplay alloc] init];
  entry.display = display;
  entry.displayID = display.displayID;
  entry.config = config;
  [_displays addObject:entry];
  return entry;
}

- (BOOL)removeDisplayWithID:(CGDirectDisplayID)displayID {
  NSUInteger index = [_displays indexOfObjectPassingTest:^BOOL(VSMManagedDisplay *entry, NSUInteger idx, BOOL *stop) {
    (void)idx; (void)stop;
    return entry.displayID == displayID;
  }];
  if (index == NSNotFound) return NO;
  _displays[index].display = nil;
  [_displays removeObjectAtIndex:index];
  return YES;
}

- (void)removeAllDisplays {
  for (VSMManagedDisplay *entry in _displays) entry.display = nil;
  [_displays removeAllObjects];
}

- (void)dealloc {
  for (VSMManagedDisplay *entry in _displays) entry.display = nil;
}
@end
