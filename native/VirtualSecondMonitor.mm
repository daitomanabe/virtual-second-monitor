#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <signal.h>
#import <stdlib.h>

#import "VSMDisplayManager.h"
#import <math.h>

static unsigned int displayCount = 1;

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
  printf("  --name <name>      Display name. Default: Virtual Monitor\n");
  printf("  --serial <number>  First display serial. Default: automatic\n");
  printf("  --vendor <number>  Vendor ID. Default: 505\n");
  printf("  --product <number> Product ID. Default: 22136\n");
  printf("  --count <1-8>      Number of virtual monitors. Default: 1\n");
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
  if (end == value || *end != '\0' || !isfinite(parsed) || parsed <= 0.0) {
    fprintf(stderr, "Invalid %s: %s\n", name, value);
    exit(2);
  }
  return parsed;
}

static BOOL listOnly = NO;

static VSMVirtualDisplayConfig ParseArguments(int argc, const char *argv[]) {
  VSMVirtualDisplayConfig config = VSMDefaultConfig();

  for (int i = 1; i < argc; i++) {
    NSString *arg = [NSString stringWithUTF8String:argv[i]];

    if ([arg isEqualToString:@"--help"]) {
      PrintUsage(argv[0]);
      exit(0);
    } else if ([arg isEqualToString:@"--list"]) {
      listOnly = YES;
    } else if ([arg isEqualToString:@"--hidpi"]) {
      config.hiDPI = YES;
    } else if ([arg isEqualToString:@"--count"] && i + 1 < argc) {
      displayCount = ParseUInt(argv[++i], "count");
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

  if (displayCount < 1 || displayCount > VSMMaximumDisplayCount) {
    fprintf(stderr, "Count must be between 1 and 8.\n");
    exit(2);
  }
  if (config.serialNumber > UINT_MAX - (displayCount - 1)) {
    fprintf(stderr, "Serial range exceeds the maximum serial number.\n");
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

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    VSMVirtualDisplayConfig config = ParseArguments(argc, argv);

    if (listOnly) {
      PrintDisplayList("Displays");
      return 0;
    }

    signal(SIGINT, HandleSignal);
    signal(SIGTERM, HandleSignal);

    PrintDisplayList("Before");

    VSMDisplayManager *manager = [[VSMDisplayManager alloc] init];
    for (unsigned int i = 0; i < displayCount && keepRunning; i++) {
      @autoreleasepool {
        VSMVirtualDisplayConfig next = config;
        if (displayCount > 1) next.name = [NSString stringWithFormat:@"%@ %u", config.name, i + 1];
        if (config.serialNumber > 0) next.serialNumber += i;
        NSString *error = nil;
        VSMManagedDisplay *display = [manager addDisplayWithConfig:next error:&error];
        if (!display) {
          fprintf(stderr, "Could not create monitor %u: %s\n", i + 1, error.UTF8String);
          [manager removeAllDisplays];
          return 1;
        }
        printf("Created virtual monitor %u: id=%u name=%s physical=%ux%u serial=%u hidpi=%s\n",
               i + 1, display.displayID, next.name.UTF8String, next.width, next.height,
               display.config.serialNumber, next.hiDPI ? "yes" : "no");
      }
    }
    printf("\nPress Ctrl-C to remove all monitors created by this process.\n\n");
    fflush(stdout);

    [NSThread sleepForTimeInterval:0.8];
    PrintDisplayList("After");

    while (keepRunning) {
      @autoreleasepool {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
      }
    }

    printf("\nRemoving %lu virtual monitors\n", (unsigned long)manager.displays.count);
    [manager removeAllDisplays];
  }

  return 0;
}
