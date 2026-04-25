#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <signal.h>
#import <stdlib.h>

API_AVAILABLE(macos(10.14))
@interface CGVirtualDisplayMode : NSObject
@property(readonly, nonatomic) unsigned int width;
@property(readonly, nonatomic) unsigned int height;
@property(readonly, nonatomic) double refreshRate;
- (id)initWithWidth:(unsigned int)width height:(unsigned int)height refreshRate:(double)refreshRate;
@end

API_AVAILABLE(macos(10.14))
@interface CGVirtualDisplaySettings : NSObject
@property(strong, nonatomic) NSArray *modes;
@property(nonatomic) unsigned int hiDPI;
@property(nonatomic) unsigned int rotation;
- (id)init;
@end

API_AVAILABLE(macos(10.14))
@interface CGVirtualDisplayDescriptor : NSObject
@property(nonatomic) unsigned int vendorID;
@property(nonatomic) unsigned int productID;
@property(nonatomic) unsigned int serialNum;
@property(nonatomic) unsigned int serialNumber;
@property(strong, nonatomic) NSString *name;
@property(nonatomic) CGSize sizeInMillimeters;
@property(nonatomic) unsigned int maxPixelsWide;
@property(nonatomic) unsigned int maxPixelsHigh;
@property(nonatomic) CGPoint redPrimary;
@property(nonatomic) CGPoint greenPrimary;
@property(nonatomic) CGPoint bluePrimary;
@property(nonatomic) CGPoint whitePoint;
@property(retain, nonatomic) id queue;
@property(copy, nonatomic) id terminationHandler;
- (id)init;
- (void)setDispatchQueue:(id)queue;
@end

API_AVAILABLE(macos(10.14))
@interface CGVirtualDisplay : NSObject
@property(readonly, nonatomic) unsigned int displayID;
@property(readonly, nonatomic) unsigned int vendorID;
@property(readonly, nonatomic) unsigned int productID;
@property(readonly, nonatomic) unsigned int serialNum;
@property(readonly, nonatomic) NSString *name;
@property(readonly, nonatomic) NSArray *modes;
@property(readonly, nonatomic) unsigned int hiDPI;
- (id)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@end

typedef struct {
  unsigned int width;
  unsigned int height;
  unsigned int ppi;
  double refreshRate;
  BOOL hiDPI;
  unsigned int serialNumber;
  unsigned int vendorID;
  unsigned int productID;
  NSString *name;
  BOOL listOnly;
} VirtualDisplayConfig;

static volatile sig_atomic_t keepRunning = 1;

static void HandleSignal(int signalNumber) {
  (void)signalNumber;
  keepRunning = 0;
}

static void PrintUsage(const char *binaryName) {
  printf("Usage:\n");
  printf("  %s [options]\n\n", binaryName);
  printf("Options:\n");
  printf("  --width <px>       Physical width. Default: 1920\n");
  printf("  --height <px>      Physical height. Default: 1080\n");
  printf("  --ppi <ppi>        Size metadata. Default: 110\n");
  printf("  --refresh <hz>     Refresh rate. Default: 60\n");
  printf("  --hidpi            Use HiDPI backing scale. Mode is width/2 x height/2.\n");
  printf("  --name <name>      Display name. Default: Debug Second Display\n");
  printf("  --serial <number>  Display serial. Default: process-derived value\n");
  printf("  --vendor <number>  Vendor ID. Default: 505\n");
  printf("  --product <number> Product ID. Default: 22136\n");
  printf("  --list             Print online displays and exit\n");
  printf("  --help             Print this help\n\n");
  printf("The virtual display exists only while this process is running.\n");
}

static unsigned int ParseUInt(const char *value, const char *name) {
  char *end = NULL;
  unsigned long parsed = strtoul(value, &end, 10);
  if (end == value || *end != '\0' || parsed > UINT_MAX) {
    fprintf(stderr, "Invalid %s: %s\n", name, value);
    exit(2);
  }
  return (unsigned int)parsed;
}

static double ParseDouble(const char *value, const char *name) {
  char *end = NULL;
  double parsed = strtod(value, &end);
  if (end == value || *end != '\0' || parsed <= 0.0) {
    fprintf(stderr, "Invalid %s: %s\n", name, value);
    exit(2);
  }
  return parsed;
}

static VirtualDisplayConfig DefaultConfig(void) {
  VirtualDisplayConfig config;
  config.width = 1920;
  config.height = 1080;
  config.ppi = 110;
  config.refreshRate = 60.0;
  config.hiDPI = NO;
  config.serialNumber = 100000 + (unsigned int)(getpid() % 899999);
  config.vendorID = 505;
  config.productID = 22136;
  config.name = @"Debug Second Display";
  config.listOnly = NO;
  return config;
}

static VirtualDisplayConfig ParseArguments(int argc, const char *argv[]) {
  VirtualDisplayConfig config = DefaultConfig();

  for (int i = 1; i < argc; i++) {
    NSString *arg = [NSString stringWithUTF8String:argv[i]];

    if ([arg isEqualToString:@"--help"]) {
      PrintUsage(argv[0]);
      exit(0);
    } else if ([arg isEqualToString:@"--list"]) {
      config.listOnly = YES;
    } else if ([arg isEqualToString:@"--hidpi"]) {
      config.hiDPI = YES;
    } else if ([arg isEqualToString:@"--width"] && i + 1 < argc) {
      config.width = ParseUInt(argv[++i], "width");
    } else if ([arg isEqualToString:@"--height"] && i + 1 < argc) {
      config.height = ParseUInt(argv[++i], "height");
    } else if ([arg isEqualToString:@"--ppi"] && i + 1 < argc) {
      config.ppi = ParseUInt(argv[++i], "ppi");
    } else if ([arg isEqualToString:@"--refresh"] && i + 1 < argc) {
      config.refreshRate = ParseDouble(argv[++i], "refresh");
    } else if ([arg isEqualToString:@"--serial"] && i + 1 < argc) {
      config.serialNumber = ParseUInt(argv[++i], "serial");
    } else if ([arg isEqualToString:@"--vendor"] && i + 1 < argc) {
      config.vendorID = ParseUInt(argv[++i], "vendor");
    } else if ([arg isEqualToString:@"--product"] && i + 1 < argc) {
      config.productID = ParseUInt(argv[++i], "product");
    } else if ([arg isEqualToString:@"--name"] && i + 1 < argc) {
      config.name = [NSString stringWithUTF8String:argv[++i]];
    } else {
      fprintf(stderr, "Unknown or incomplete option: %s\n", argv[i]);
      PrintUsage(argv[0]);
      exit(2);
    }
  }

  if (config.width < 160 || config.height < 120) {
    fprintf(stderr, "Resolution is too small: %ux%u\n", config.width, config.height);
    exit(2);
  }

  if (config.hiDPI && (config.width % 2 != 0 || config.height % 2 != 0)) {
    fprintf(stderr, "HiDPI mode requires even width and height.\n");
    exit(2);
  }

  if (config.ppi == 0) {
    fprintf(stderr, "PPI must be greater than zero.\n");
    exit(2);
  }

  return config;
}

static void PrintDisplayList(const char *title) {
  enum { maxDisplays = 32 };
  CGDirectDisplayID displays[maxDisplays];
  uint32_t displayCount = 0;
  CGError error = CGGetOnlineDisplayList(maxDisplays, displays, &displayCount);

  if (error != kCGErrorSuccess) {
    fprintf(stderr, "CGGetOnlineDisplayList failed: %d\n", error);
    return;
  }

  printf("%s (%u online)\n", title, displayCount);
  for (uint32_t i = 0; i < displayCount; i++) {
    CGDirectDisplayID displayID = displays[i];
    CGRect bounds = CGDisplayBounds(displayID);
    size_t pixelsWide = CGDisplayPixelsWide(displayID);
    size_t pixelsHigh = CGDisplayPixelsHigh(displayID);
    printf("  id=%u bounds=%.0fx%.0f pixels=%zux%zu vendor=%u model=%u serial=%u main=%s builtin=%s\n",
           displayID,
           bounds.size.width,
           bounds.size.height,
           pixelsWide,
           pixelsHigh,
           CGDisplayVendorNumber(displayID),
           CGDisplayModelNumber(displayID),
           CGDisplaySerialNumber(displayID),
           CGDisplayIsMain(displayID) ? "yes" : "no",
           CGDisplayIsBuiltin(displayID) ? "yes" : "no");
  }
}

static CGVirtualDisplay *CreateVirtualDisplay(VirtualDisplayConfig config) API_AVAILABLE(macos(10.14));
static CGVirtualDisplay *CreateVirtualDisplay(VirtualDisplayConfig config) {
  Class displayClass = NSClassFromString(@"CGVirtualDisplay");
  Class descriptorClass = NSClassFromString(@"CGVirtualDisplayDescriptor");
  Class settingsClass = NSClassFromString(@"CGVirtualDisplaySettings");
  Class modeClass = NSClassFromString(@"CGVirtualDisplayMode");

  if (!displayClass || !descriptorClass || !settingsClass || !modeClass) {
    fprintf(stderr, "CGVirtualDisplay API is not available on this macOS build.\n");
    return nil;
  }

  CGVirtualDisplayDescriptor *descriptor = [[CGVirtualDisplayDescriptor alloc] init];
  descriptor.name = config.name;
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

  if ([descriptor respondsToSelector:@selector(setSerialNum:)]) {
    descriptor.serialNum = config.serialNumber;
  }
  if ([descriptor respondsToSelector:@selector(setSerialNumber:)]) {
    descriptor.serialNumber = config.serialNumber;
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
    fprintf(stderr, "CGVirtualDisplay initWithDescriptor failed.\n");
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
    fprintf(stderr, "CGVirtualDisplay applySettings failed.\n");
    return nil;
  }

  return display;
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    VirtualDisplayConfig config = ParseArguments(argc, argv);

    if (config.listOnly) {
      PrintDisplayList("Displays");
      return 0;
    }

    signal(SIGINT, HandleSignal);
    signal(SIGTERM, HandleSignal);

    PrintDisplayList("Before");

    CGVirtualDisplay *display = CreateVirtualDisplay(config);
    if (!display) {
      return 1;
    }

    printf("\nCreated virtual display\n");
    printf("  id=%u\n", display.displayID);
    printf("  name=%s\n", [config.name UTF8String]);
    printf("  physical=%ux%u\n", config.width, config.height);
    printf("  mode=%ux%u @ %.2fHz\n",
           config.hiDPI ? config.width / 2 : config.width,
           config.hiDPI ? config.height / 2 : config.height,
           config.refreshRate);
    printf("  hidpi=%s\n", config.hiDPI ? "yes" : "no");
    printf("\nPress Ctrl-C to remove the virtual display.\n\n");
    fflush(stdout);

    [NSThread sleepForTimeInterval:0.8];
    PrintDisplayList("After");

    while (keepRunning) {
      @autoreleasepool {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
      }
    }

    CGDirectDisplayID removedDisplayID = display.displayID;
    printf("\nExiting; macOS will remove virtual display id=%u\n", removedDisplayID);
    display = nil;
  }

  return 0;
}
