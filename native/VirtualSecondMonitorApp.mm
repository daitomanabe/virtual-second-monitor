#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
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
} VSMVirtualDisplayConfig;

static VSMVirtualDisplayConfig VSMDefaultConfig(void) {
  VSMVirtualDisplayConfig config;
  config.width = 1920;
  config.height = 1080;
  config.ppi = 110;
  config.refreshRate = 60.0;
  config.hiDPI = NO;
  config.serialNumber = 0;
  config.vendorID = 505;
  config.productID = 22136;
  config.name = @"Debug Second Display";
  return config;
}

static unsigned int VSMAutoSerialNumber(void) {
  return 200000 + arc4random_uniform(700000);
}

static NSString *VSMErrorString(NSString *message) {
  return message ?: @"Unknown error";
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

  CGVirtualDisplayDescriptor *descriptor = [[CGVirtualDisplayDescriptor alloc] init];
  descriptor.name = config.name.length > 0 ? config.name : @"Debug Second Display";
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

static NSString *VSMDisplayListText(void) {
  enum { maxDisplays = 32 };
  CGDirectDisplayID displays[maxDisplays];
  uint32_t displayCount = 0;
  CGError error = CGGetOnlineDisplayList(maxDisplays, displays, &displayCount);

  if (error != kCGErrorSuccess) {
    return [NSString stringWithFormat:@"CGGetOnlineDisplayList failed: %d", error];
  }

  NSMutableString *result = [NSMutableString stringWithFormat:@"%u online display%@\n",
                             displayCount,
                             displayCount == 1 ? @"" : @"s"];
  for (uint32_t i = 0; i < displayCount; i++) {
    CGDirectDisplayID displayID = displays[i];
    CGRect bounds = CGDisplayBounds(displayID);
    size_t pixelsWide = CGDisplayPixelsWide(displayID);
    size_t pixelsHigh = CGDisplayPixelsHigh(displayID);
    [result appendFormat:@"id=%u  bounds=%.0fx%.0f  pixels=%zux%zu  vendor=%u  model=%u  serial=%u%@%@\n",
                         displayID,
                         bounds.size.width,
                         bounds.size.height,
                         pixelsWide,
                         pixelsHigh,
                         CGDisplayVendorNumber(displayID),
                         CGDisplayModelNumber(displayID),
                         CGDisplaySerialNumber(displayID),
                         CGDisplayIsMain(displayID) ? @"  main" : @"",
                         CGDisplayIsBuiltin(displayID) ? @"  builtin" : @""];
  }
  return result;
}

typedef CGImageRef (*VSMCGDisplayCreateImageFunction)(CGDirectDisplayID displayID);
typedef CGImageRef (*VSMCGWindowListCreateImageFunction)(CGRect screenBounds,
                                                         CGWindowListOption listOption,
                                                         CGWindowID windowID,
                                                         CGWindowImageOption imageOption);
typedef bool (*VSMCGPreflightScreenCaptureAccessFunction)(void);

static CGImageRef VSMCopyDisplayImage(CGDirectDisplayID displayID) {
  static VSMCGDisplayCreateImageFunction createImage = NULL;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    void *handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY);
    if (handle) {
      createImage = (VSMCGDisplayCreateImageFunction)dlsym(handle, "CGDisplayCreateImage");
    }
  });

  if (!createImage) {
    return NULL;
  }
  return createImage(displayID);
}

static CGImageRef VSMCopyWindowCompositeImage(CGDirectDisplayID displayID) {
  static VSMCGWindowListCreateImageFunction createImage = NULL;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    void *handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY);
    if (handle) {
      createImage = (VSMCGWindowListCreateImageFunction)dlsym(handle, "CGWindowListCreateImage");
    }
  });

  if (!createImage) {
    return NULL;
  }

  CGRect displayBounds = CGDisplayBounds(displayID);
  if (CGRectIsEmpty(displayBounds) || CGRectIsNull(displayBounds)) {
    return NULL;
  }

  return createImage(displayBounds,
                     kCGWindowListOptionOnScreenOnly,
                     kCGNullWindowID,
                     kCGWindowImageDefault | kCGWindowImageBestResolution);
}

static CGImageRef VSMCopyPreviewImage(CGDirectDisplayID displayID) {
  CGImageRef compositeImage = VSMCopyWindowCompositeImage(displayID);
  if (compositeImage) {
    return compositeImage;
  }

  return VSMCopyDisplayImage(displayID);
}

static BOOL VSMScreenCaptureAccessGranted(void) {
  static VSMCGPreflightScreenCaptureAccessFunction preflight = NULL;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    void *handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY);
    if (handle) {
      preflight = (VSMCGPreflightScreenCaptureAccessFunction)dlsym(handle, "CGPreflightScreenCaptureAccess");
    }
  });

  if (!preflight) {
    return YES;
  }
  return preflight() ? YES : NO;
}

@interface VSMPreviewView : NSView
@property(strong, nonatomic) NSImage *image;
@property(copy, nonatomic) NSString *message;
@property(nonatomic) CGSize displaySize;
@property(nonatomic) BOOL showGrid;
@end

@implementation VSMPreviewView

- (BOOL)isFlipped {
  return YES;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _displaySize = CGSizeMake(1920, 1080);
    _message = @"Create a virtual display to preview it here.";
    _showGrid = YES;
    self.wantsLayer = YES;
    self.layer.cornerRadius = 10.0;
    self.layer.masksToBounds = YES;
  }
  return self;
}

- (void)setImage:(NSImage *)image {
  _image = image;
  [self setNeedsDisplay:YES];
}

- (void)setMessage:(NSString *)message {
  _message = [message copy];
  [self setNeedsDisplay:YES];
}

- (void)setDisplaySize:(CGSize)displaySize {
  _displaySize = displaySize;
  [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
  (void)dirtyRect;
  [[NSColor colorWithCalibratedRed:0.055 green:0.062 blue:0.074 alpha:1.0] setFill];
  NSRectFill(self.bounds);

  CGFloat width = MAX(self.displaySize.width, 16.0);
  CGFloat height = MAX(self.displaySize.height, 9.0);
  CGFloat padding = 28.0;
  CGFloat scale = MIN((NSWidth(self.bounds) - padding * 2.0) / width,
                      (NSHeight(self.bounds) - padding * 2.0) / height);
  scale = MAX(scale, 0.02);

  NSSize previewSize = NSMakeSize(width * scale, height * scale);
  NSRect previewRect = NSMakeRect((NSWidth(self.bounds) - previewSize.width) / 2.0,
                                  (NSHeight(self.bounds) - previewSize.height) / 2.0,
                                  previewSize.width,
                                  previewSize.height);

  [[NSColor blackColor] setFill];
  NSRectFill(previewRect);

  if (self.image) {
    [self.image drawInRect:previewRect
                  fromRect:NSZeroRect
                 operation:NSCompositingOperationSourceOver
                  fraction:1.0
            respectFlipped:YES
                     hints:nil];
  }

  if (self.showGrid) {
    [[NSColor colorWithCalibratedWhite:1.0 alpha:0.14] setStroke];
    NSBezierPath *grid = [NSBezierPath bezierPath];
    CGFloat columns = 8.0;
    CGFloat rows = 4.5;
    for (int i = 1; i < columns; i++) {
      CGFloat x = NSMinX(previewRect) + NSWidth(previewRect) * i / columns;
      [grid moveToPoint:NSMakePoint(x, NSMinY(previewRect))];
      [grid lineToPoint:NSMakePoint(x, NSMaxY(previewRect))];
    }
    for (int i = 1; i < rows; i++) {
      CGFloat y = NSMinY(previewRect) + NSHeight(previewRect) * i / rows;
      [grid moveToPoint:NSMakePoint(NSMinX(previewRect), y)];
      [grid lineToPoint:NSMakePoint(NSMaxX(previewRect), y)];
    }
    [grid stroke];
  }

  [[NSColor colorWithCalibratedWhite:1.0 alpha:0.28] setStroke];
  NSBezierPath *border = [NSBezierPath bezierPathWithRoundedRect:previewRect xRadius:4.0 yRadius:4.0];
  border.lineWidth = 1.5;
  [border stroke];

  if (!self.image && self.message.length > 0) {
    NSDictionary *attrs = @{
      NSFontAttributeName: [NSFont systemFontOfSize:15.0 weight:NSFontWeightMedium],
      NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:1.0 alpha:0.72]
    };
    NSSize textSize = [self.message sizeWithAttributes:attrs];
    NSRect textRect = NSMakeRect(NSMidX(self.bounds) - textSize.width / 2.0,
                                 NSMidY(self.bounds) - textSize.height / 2.0,
                                 textSize.width,
                                 textSize.height);
    [self.message drawInRect:textRect withAttributes:attrs];
  }
}

@end

@interface VSMAppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property(strong, nonatomic) NSWindow *window;
@property(strong, nonatomic) NSScrollView *controlScrollView;
@property(strong, nonatomic) VSMPreviewView *previewView;
@property(strong, nonatomic) NSTextField *previewTitleLabel;
@property(strong, nonatomic) NSTextField *previewMetaLabel;
@property(strong, nonatomic) NSTextView *displayListView;
@property(strong, nonatomic) NSPopUpButton *presetPopup;
@property(strong, nonatomic) NSTextField *nameField;
@property(strong, nonatomic) NSTextField *widthField;
@property(strong, nonatomic) NSTextField *heightField;
@property(strong, nonatomic) NSTextField *ppiField;
@property(strong, nonatomic) NSTextField *refreshField;
@property(strong, nonatomic) NSTextField *serialField;
@property(strong, nonatomic) NSButton *hiDPIButton;
@property(strong, nonatomic) NSButton *createButton;
@property(strong, nonatomic) NSButton *removeButton;
@property(strong, nonatomic) NSButton *gridButton;
@property(strong, nonatomic) NSPopUpButton *previewRatePopup;
@property(strong, nonatomic) NSButton *refreshCaptureAccessButton;
@property(strong, nonatomic) NSButton *openPrivacySettingsButton;
@property(strong, nonatomic) NSTextField *statusLabel;
@property(strong, nonatomic) NSTimer *previewTimer;
@property(strong, nonatomic) NSTimer *displayListTimer;
@property(strong, nonatomic) dispatch_queue_t previewCaptureQueue;
@property(nonatomic) BOOL previewCaptureInFlight;
@property(nonatomic) uint64_t previewGeneration;
@property(strong, nonatomic) CGVirtualDisplay *virtualDisplay;
@property(nonatomic) CGDirectDisplayID virtualDisplayID;
@property(copy, nonatomic) NSString *currentDisplayName;
@property(nonatomic) unsigned int currentDisplayWidth;
@property(nonatomic) unsigned int currentDisplayHeight;
@property(nonatomic) BOOL currentDisplayHiDPI;
@property(strong, nonatomic) NSArray<NSDictionary *> *presets;
@end

@implementation VSMAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  (void)notification;
  self.previewCaptureQueue = dispatch_queue_create("ws.daito.virtual-second-monitor.preview-capture", DISPATCH_QUEUE_SERIAL);
  [self buildMenu];
  [self buildWindow];
  [self refreshDisplayList:nil];
  self.displayListTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                           target:self
                                                         selector:@selector(refreshDisplayList:)
                                                         userInfo:nil
                                                          repeats:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
  (void)sender;
  return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
  (void)notification;
  [self.previewTimer invalidate];
  [self.displayListTimer invalidate];
  self.virtualDisplay = nil;
}

- (void)buildMenu {
  NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@""];
  NSMenuItem *appMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
  [mainMenu addItem:appMenuItem];

  NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Virtual Second Monitor"];
  NSString *quitTitle = @"Quit Virtual Second Monitor";
  NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:quitTitle
                                                    action:@selector(terminate:)
                                             keyEquivalent:@"q"];
  [appMenu addItem:quitItem];
  [appMenuItem setSubmenu:appMenu];
  [NSApp setMainMenu:mainMenu];
}

- (void)buildWindow {
  self.presets = @[
    @{@"title": @"Full HD 1920 x 1080", @"width": @1920, @"height": @1080, @"ppi": @110, @"hidpi": @NO},
    @{@"title": @"QHD 2560 x 1440", @"width": @2560, @"height": @1440, @"ppi": @110, @"hidpi": @NO},
    @{@"title": @"WUXGA 1920 x 1200", @"width": @1920, @"height": @1200, @"ppi": @110, @"hidpi": @NO},
    @{@"title": @"Portrait 1080 x 1920", @"width": @1080, @"height": @1920, @"ppi": @110, @"hidpi": @NO},
    @{@"title": @"4K UHD 3840 x 2160", @"width": @3840, @"height": @2160, @"ppi": @220, @"hidpi": @YES},
    @{@"title": @"5K Retina 5120 x 2880", @"width": @5120, @"height": @2880, @"ppi": @218, @"hidpi": @YES},
    @{@"title": @"8K UHD 7680 x 4320", @"width": @7680, @"height": @4320, @"ppi": @280, @"hidpi": @YES}
  ];

  NSRect frame = NSMakeRect(0, 0, 1060, 720);
  self.window = [[NSWindow alloc] initWithContentRect:frame
                                           styleMask:(NSWindowStyleMaskTitled |
                                                      NSWindowStyleMaskClosable |
                                                      NSWindowStyleMaskMiniaturizable |
                                                      NSWindowStyleMaskResizable)
                                             backing:NSBackingStoreBuffered
                                               defer:NO];
  self.window.title = @"Virtual Second Monitor";
  self.window.minSize = NSMakeSize(980, 640);
  self.window.delegate = self;
  [self.window center];

  NSView *content = self.window.contentView;
  content.wantsLayer = YES;
  content.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.075 green:0.082 blue:0.094 alpha:1.0].CGColor;

  [self buildControlsInView:content];
  [self buildPreviewInView:content];
  [self layoutContent];
  [self applyPreset:self.presets.firstObject];

  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(windowDidResize:)
                                               name:NSWindowDidResizeNotification
                                             object:self.window];
  [self.window makeKeyAndOrderFront:nil];
  [NSApp activateIgnoringOtherApps:YES];
}

- (void)buildControlsInView:(NSView *)content {
  self.controlScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
  self.controlScrollView.hasVerticalScroller = YES;
  self.controlScrollView.borderType = NSNoBorder;
  self.controlScrollView.drawsBackground = NO;
  [content addSubview:self.controlScrollView];

  NSView *document = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 320, 920)];
  document.wantsLayer = YES;
  document.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.105 green:0.118 blue:0.137 alpha:1.0].CGColor;
  self.controlScrollView.documentView = document;

  CGFloat y = 888.0;
  NSTextField *title = [self label:@"Virtual Second Monitor" size:22.0 weight:NSFontWeightBold];
  title.frame = VSMTopRect(&y, 18.0, 284.0, 30.0, 12.0);
  [document addSubview:title];

  NSTextField *subtitle = [self label:@"Create an OS-recognized second display and inspect it live." size:12.0 weight:NSFontWeightRegular];
  subtitle.textColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.62];
  subtitle.frame = VSMTopRect(&y, 18.0, 284.0, 36.0, 18.0);
  [document addSubview:subtitle];

  self.statusLabel = [self label:@"Idle" size:13.0 weight:NSFontWeightSemibold];
  self.statusLabel.textColor = [NSColor colorWithCalibratedRed:0.62 green:0.86 blue:1.0 alpha:1.0];
  self.statusLabel.frame = VSMTopRect(&y, 18.0, 284.0, 22.0, 18.0);
  [document addSubview:self.statusLabel];

  [self addSectionLabel:@"Preset" toView:document y:&y];
  self.presetPopup = [[NSPopUpButton alloc] initWithFrame:VSMTopRect(&y, 18.0, 284.0, 32.0, 14.0)];
  for (NSDictionary *preset in self.presets) {
    [self.presetPopup addItemWithTitle:preset[@"title"]];
  }
  self.presetPopup.target = self;
  self.presetPopup.action = @selector(presetChanged:);
  [document addSubview:self.presetPopup];

  [self addSectionLabel:@"Display" toView:document y:&y];
  [self addSmallLabel:@"Name" toView:document y:&y];
  self.nameField = [self textField:@"Debug Second Display"];
  self.nameField.frame = VSMTopRect(&y, 18.0, 284.0, 30.0, 10.0);
  [document addSubview:self.nameField];

  [self addSmallLabel:@"Resolution" toView:document y:&y];
  self.widthField = [self textField:@"1920"];
  self.heightField = [self textField:@"1080"];
  self.widthField.frame = NSMakeRect(18.0, y - 30.0, 136.0, 30.0);
  self.heightField.frame = NSMakeRect(166.0, y - 30.0, 136.0, 30.0);
  y -= 42.0;
  [document addSubview:self.widthField];
  [document addSubview:self.heightField];

  [self addSmallLabel:@"PPI / refresh" toView:document y:&y];
  self.ppiField = [self textField:@"110"];
  self.refreshField = [self textField:@"60"];
  self.ppiField.frame = NSMakeRect(18.0, y - 30.0, 136.0, 30.0);
  self.refreshField.frame = NSMakeRect(166.0, y - 30.0, 136.0, 30.0);
  y -= 42.0;
  [document addSubview:self.ppiField];
  [document addSubview:self.refreshField];

  [self addSmallLabel:@"Serial number" toView:document y:&y];
  self.serialField = [self textField:@""];
  self.serialField.placeholderString = @"auto";
  self.serialField.frame = VSMTopRect(&y, 18.0, 284.0, 30.0, 10.0);
  [document addSubview:self.serialField];

  self.hiDPIButton = [self checkbox:@"HiDPI backing scale"];
  self.hiDPIButton.frame = VSMTopRect(&y, 18.0, 284.0, 24.0, 18.0);
  [document addSubview:self.hiDPIButton];

  [self addSectionLabel:@"Actions" toView:document y:&y];
  self.createButton = [self button:@"Create Display" action:@selector(createDisplay:)];
  self.removeButton = [self button:@"Remove" action:@selector(removeDisplay:)];
  self.createButton.frame = NSMakeRect(18.0, y - 34.0, 172.0, 34.0);
  self.removeButton.frame = NSMakeRect(202.0, y - 34.0, 100.0, 34.0);
  y -= 46.0;
  [document addSubview:self.createButton];
  [document addSubview:self.removeButton];

  NSButton *settingsButton = [self button:@"Open Displays Settings" action:@selector(openDisplaySettings:)];
  settingsButton.frame = VSMTopRect(&y, 18.0, 284.0, 32.0, 10.0);
  [document addSubview:settingsButton];

  NSButton *refreshButton = [self button:@"Refresh Display List" action:@selector(refreshDisplayList:)];
  refreshButton.frame = VSMTopRect(&y, 18.0, 284.0, 32.0, 18.0);
  [document addSubview:refreshButton];

  [self addSectionLabel:@"Preview" toView:document y:&y];
  [self addSmallLabel:@"Refresh rate" toView:document y:&y];
  self.previewRatePopup = [[NSPopUpButton alloc] initWithFrame:VSMTopRect(&y, 18.0, 284.0, 32.0, 10.0)];
  [self.previewRatePopup addItemWithTitle:@"Lightweight (auto)"];
  [self.previewRatePopup addItemWithTitle:@"60 Hz"];
  self.previewRatePopup.target = self;
  self.previewRatePopup.action = @selector(previewRateChanged:);
  [document addSubview:self.previewRatePopup];

  self.refreshCaptureAccessButton = [self button:@"Refresh Recording Permission" action:@selector(refreshCaptureAccess:)];
  self.refreshCaptureAccessButton.frame = VSMTopRect(&y, 18.0, 284.0, 32.0, 8.0);
  [document addSubview:self.refreshCaptureAccessButton];

  self.openPrivacySettingsButton = [self button:@"Open Recording Privacy" action:@selector(openRecordingPrivacySettings:)];
  self.openPrivacySettingsButton.frame = VSMTopRect(&y, 18.0, 284.0, 32.0, 12.0);
  [document addSubview:self.openPrivacySettingsButton];

  self.gridButton = [self checkbox:@"Show preview grid"];
  self.gridButton.state = NSControlStateValueOn;
  self.gridButton.target = self;
  self.gridButton.action = @selector(gridChanged:);
  self.gridButton.frame = VSMTopRect(&y, 18.0, 284.0, 24.0, 10.0);
  [document addSubview:self.gridButton];

  NSTextField *note = [self label:@"If preview is blank, grant Screen Recording permission to this app and restart it." size:12.0 weight:NSFontWeightRegular];
  note.textColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.58];
  note.frame = VSMTopRect(&y, 18.0, 284.0, 56.0, 0.0);
  [document addSubview:note];
}

- (void)buildPreviewInView:(NSView *)content {
  self.previewTitleLabel = [self label:@"Preview" size:18.0 weight:NSFontWeightBold];
  [content addSubview:self.previewTitleLabel];

  self.previewMetaLabel = [self label:@"No virtual display" size:13.0 weight:NSFontWeightRegular];
  self.previewMetaLabel.textColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.62];
  [content addSubview:self.previewMetaLabel];

  self.previewView = [[VSMPreviewView alloc] initWithFrame:NSZeroRect];
  [content addSubview:self.previewView];

  NSTextField *displayListLabel = [self label:@"Online Displays" size:14.0 weight:NSFontWeightBold];
  displayListLabel.identifier = @"displayListLabel";
  [content addSubview:displayListLabel];

  NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
  scroll.identifier = @"displayListScroll";
  scroll.hasVerticalScroller = YES;
  scroll.hasHorizontalScroller = YES;
  scroll.borderType = NSBezelBorder;
  self.displayListView = [[NSTextView alloc] initWithFrame:NSZeroRect];
  self.displayListView.editable = NO;
  self.displayListView.selectable = YES;
  self.displayListView.font = [NSFont monospacedSystemFontOfSize:12.0 weight:NSFontWeightRegular];
  self.displayListView.textColor = [NSColor colorWithCalibratedWhite:0.88 alpha:1.0];
  self.displayListView.backgroundColor = [NSColor colorWithCalibratedRed:0.065 green:0.072 blue:0.084 alpha:1.0];
  scroll.documentView = self.displayListView;
  [content addSubview:scroll];
}

static NSRect VSMTopRect(CGFloat *y, CGFloat x, CGFloat width, CGFloat height, CGFloat gap) {
  *y -= height;
  NSRect rect = NSMakeRect(x, *y, width, height);
  *y -= gap;
  return rect;
}

- (NSTextField *)label:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight {
  NSTextField *label = [NSTextField labelWithString:text];
  label.font = [NSFont systemFontOfSize:size weight:weight];
  label.textColor = [NSColor colorWithCalibratedWhite:0.96 alpha:1.0];
  label.lineBreakMode = NSLineBreakByWordWrapping;
  return label;
}

- (NSTextField *)textField:(NSString *)text {
  NSTextField *field = [[NSTextField alloc] initWithFrame:NSZeroRect];
  field.stringValue = text;
  field.font = [NSFont systemFontOfSize:13.0];
  field.bezelStyle = NSTextFieldRoundedBezel;
  return field;
}

- (NSButton *)button:(NSString *)title action:(SEL)action {
  NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
  button.title = title;
  button.target = self;
  button.action = action;
  button.bezelStyle = NSBezelStyleRounded;
  return button;
}

- (NSButton *)checkbox:(NSString *)title {
  NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
  button.title = title;
  button.buttonType = NSButtonTypeSwitch;
  button.font = [NSFont systemFontOfSize:13.0];
  return button;
}

- (void)addSectionLabel:(NSString *)text toView:(NSView *)view y:(CGFloat *)y {
  NSTextField *label = [self label:text size:12.0 weight:NSFontWeightBold];
  label.textColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.70];
  label.frame = VSMTopRect(y, 18.0, 284.0, 18.0, 8.0);
  [view addSubview:label];
}

- (void)addSmallLabel:(NSString *)text toView:(NSView *)view y:(CGFloat *)y {
  NSTextField *label = [self label:text size:11.0 weight:NSFontWeightSemibold];
  label.textColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.58];
  label.frame = VSMTopRect(y, 18.0, 284.0, 15.0, 4.0);
  [view addSubview:label];
}

- (void)windowDidResize:(NSNotification *)notification {
  (void)notification;
  [self layoutContent];
}

- (void)layoutContent {
  NSView *content = self.window.contentView;
  CGFloat width = NSWidth(content.bounds);
  CGFloat height = NSHeight(content.bounds);
  CGFloat leftWidth = 320.0;
  CGFloat gap = 18.0;
  CGFloat rightX = leftWidth + gap;
  CGFloat rightWidth = MAX(320.0, width - rightX - gap);

  self.controlScrollView.frame = NSMakeRect(0, 0, leftWidth, height);
  self.previewTitleLabel.frame = NSMakeRect(rightX, height - 42.0, 220.0, 24.0);
  self.previewMetaLabel.frame = NSMakeRect(rightX + 220.0, height - 40.0, rightWidth - 220.0, 20.0);

  CGFloat listHeight = 138.0;
  CGFloat listY = 24.0;
  CGFloat listLabelY = listY + listHeight + 10.0;
  CGFloat previewY = listLabelY + 34.0;
  CGFloat previewHeight = MAX(260.0, height - previewY - 62.0);

  self.previewView.frame = NSMakeRect(rightX, previewY, rightWidth, previewHeight);

  for (NSView *view in content.subviews) {
    if ([view.identifier isEqualToString:@"displayListLabel"]) {
      view.frame = NSMakeRect(rightX, listLabelY, rightWidth, 20.0);
    } else if ([view.identifier isEqualToString:@"displayListScroll"]) {
      view.frame = NSMakeRect(rightX, listY, rightWidth, listHeight);
    }
  }
}

- (void)presetChanged:(id)sender {
  NSInteger index = self.presetPopup.indexOfSelectedItem;
  if (index >= 0 && index < (NSInteger)self.presets.count) {
    [self applyPreset:self.presets[index]];
  }
  (void)sender;
}

- (void)applyPreset:(NSDictionary *)preset {
  self.widthField.stringValue = [preset[@"width"] stringValue];
  self.heightField.stringValue = [preset[@"height"] stringValue];
  self.ppiField.stringValue = [preset[@"ppi"] stringValue];
  self.refreshField.stringValue = @"60";
  self.hiDPIButton.state = [preset[@"hidpi"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
}

- (VSMVirtualDisplayConfig)configFromFields {
  VSMVirtualDisplayConfig config = VSMDefaultConfig();
  config.name = self.nameField.stringValue.length > 0 ? self.nameField.stringValue : @"Debug Second Display";
  config.width = (unsigned int)MAX(0, self.widthField.integerValue);
  config.height = (unsigned int)MAX(0, self.heightField.integerValue);
  config.ppi = (unsigned int)MAX(0, self.ppiField.integerValue);
  config.refreshRate = MAX(1.0, self.refreshField.doubleValue);
  config.hiDPI = self.hiDPIButton.state == NSControlStateValueOn;
  config.serialNumber = self.serialField.stringValue.length > 0 ? (unsigned int)MAX(0, self.serialField.integerValue) : 0;
  return config;
}

- (void)createDisplay:(id)sender {
  (void)sender;

  if (self.virtualDisplay) {
    self.virtualDisplay = nil;
    self.virtualDisplayID = 0;
  }

  VSMVirtualDisplayConfig config = [self configFromFields];
  double requestedPixels = (double)config.width * (double)config.height;
  if (!config.hiDPI && requestedPixels >= 3840.0 * 2160.0) {
    config.hiDPI = YES;
    self.hiDPIButton.state = NSControlStateValueOn;
  }

  NSString *errorMessage = nil;
  CGVirtualDisplay *display = VSMCreateVirtualDisplay(config, &errorMessage);
  if (!display) {
    [self showError:VSMErrorString(errorMessage)];
    self.statusLabel.stringValue = @"Create failed";
    return;
  }

  self.virtualDisplay = display;
  self.virtualDisplayID = display.displayID;
  self.currentDisplayName = config.name;
  self.currentDisplayWidth = config.width;
  self.currentDisplayHeight = config.height;
  self.currentDisplayHiDPI = config.hiDPI;
  self.previewView.displaySize = CGSizeMake(config.width, config.height);
  self.previewView.message = @"Waiting for display frames...";
  [self updatePreviewMetaLabel];
  self.statusLabel.stringValue = [NSString stringWithFormat:@"Online: display id %u", self.virtualDisplayID];

  [self startPreviewTimer];
  [self refreshDisplayList:nil];
}

- (void)removeDisplay:(id)sender {
  (void)sender;
  if (!self.virtualDisplay) {
    self.statusLabel.stringValue = @"No virtual display to remove";
    return;
  }

  CGDirectDisplayID removedID = self.virtualDisplayID;
  self.previewGeneration++;
  self.previewCaptureInFlight = NO;
  self.virtualDisplay = nil;
  self.virtualDisplayID = 0;
  self.currentDisplayName = nil;
  self.currentDisplayWidth = 0;
  self.currentDisplayHeight = 0;
  self.currentDisplayHiDPI = NO;
  self.previewView.image = nil;
  self.previewView.message = @"Virtual display removed.";
  self.previewMetaLabel.stringValue = @"No virtual display";
  self.statusLabel.stringValue = [NSString stringWithFormat:@"Removed display id %u", removedID];
  [self.previewTimer invalidate];
  self.previewTimer = nil;

  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    [self refreshDisplayList:nil];
  });
}

- (void)startPreviewTimer {
  [self.previewTimer invalidate];
  self.previewGeneration++;
  self.previewCaptureInFlight = NO;
  NSTimeInterval interval = [self previewInterval];
  self.previewTimer = [NSTimer timerWithTimeInterval:interval
                                              target:self
                                            selector:@selector(updatePreview:)
                                            userInfo:nil
                                             repeats:YES];
  self.previewTimer.tolerance = [self isPreview60Hz] ? 0.002 : MIN(interval * 0.2, 0.05);
  [[NSRunLoop mainRunLoop] addTimer:self.previewTimer forMode:NSRunLoopCommonModes];
  [self updatePreview:nil];
}

- (NSTimeInterval)previewInterval {
  if ([self isPreview60Hz]) {
    return 1.0 / 60.0;
  }

  double pixels = self.previewView.displaySize.width * self.previewView.displaySize.height;
  if (pixels >= 7680.0 * 4320.0) {
    return 0.5;
  }
  if (pixels >= 3840.0 * 2160.0) {
    return 0.25;
  }
  if (pixels >= 2560.0 * 1440.0) {
    return 1.0 / 8.0;
  }
  return 1.0 / 12.0;
}

- (BOOL)isPreview60Hz {
  return self.previewRatePopup.indexOfSelectedItem == 1;
}

- (NSString *)previewRateDescription {
  return [self isPreview60Hz] ? @"Preview: 60 Hz" : @"Preview: Lightweight";
}

- (void)previewRateChanged:(id)sender {
  (void)sender;
  if (self.virtualDisplay) {
    [self startPreviewTimer];
    [self updatePreviewMetaLabel];
  }
}

- (void)updatePreviewMetaLabel {
  if (!self.virtualDisplay || self.virtualDisplayID == 0) {
    self.previewMetaLabel.stringValue = @"No virtual display";
    return;
  }

  self.previewMetaLabel.stringValue = [NSString stringWithFormat:@"id %u  %@  %ux%u%@  %@",
                                       self.virtualDisplayID,
                                       self.currentDisplayName ?: @"Debug Second Display",
                                       self.currentDisplayWidth,
                                       self.currentDisplayHeight,
                                       self.currentDisplayHiDPI ? @"  HiDPI" : @"",
                                       [self previewRateDescription]];
}

- (void)updatePreview:(id)sender {
  (void)sender;
  if (!self.virtualDisplay || self.virtualDisplayID == 0) {
    return;
  }

  if (self.previewCaptureInFlight) {
    return;
  }

  self.previewCaptureInFlight = YES;
  CGDirectDisplayID displayID = self.virtualDisplayID;
  uint64_t generation = self.previewGeneration;

  if (@available(macOS 14.0, *)) {
    [self captureScreenCaptureKitPreviewForDisplayID:displayID generation:generation];
    return;
  }

  [self captureCoreGraphicsPreviewForDisplayID:displayID generation:generation];
}

- (void)captureScreenCaptureKitPreviewForDisplayID:(CGDirectDisplayID)displayID generation:(uint64_t)generation API_AVAILABLE(macos(14.0)) {
  [SCShareableContent getShareableContentExcludingDesktopWindows:NO
                                             onScreenWindowsOnly:YES
                                               completionHandler:^(SCShareableContent *_Nullable shareableContent, NSError *_Nullable error) {
    if (error || !shareableContent) {
      [self captureCoreGraphicsPreviewForDisplayID:displayID generation:generation];
      return;
    }

    SCDisplay *targetDisplay = nil;
    for (SCDisplay *display in shareableContent.displays) {
      if (display.displayID == displayID) {
        targetDisplay = display;
        break;
      }
    }

    if (!targetDisplay) {
      [self captureCoreGraphicsPreviewForDisplayID:displayID generation:generation];
      return;
    }

    SCContentFilter *filter = [[SCContentFilter alloc] initWithDisplay:targetDisplay excludingWindows:@[]];
    if ([filter respondsToSelector:@selector(setIncludeMenuBar:)]) {
      filter.includeMenuBar = YES;
    }

    SCStreamConfiguration *configuration = [[SCStreamConfiguration alloc] init];
    configuration.width = (size_t)MAX(1, targetDisplay.width);
    configuration.height = (size_t)MAX(1, targetDisplay.height);
    configuration.showsCursor = YES;
    if ([configuration respondsToSelector:@selector(setCapturesAudio:)]) {
      configuration.capturesAudio = NO;
    }

    [SCScreenshotManager captureImageWithFilter:filter
                                  configuration:configuration
                              completionHandler:^(CGImageRef _Nullable imageRef, NSError *_Nullable captureError) {
      if (captureError || !imageRef) {
        [self captureCoreGraphicsPreviewForDisplayID:displayID generation:generation];
        return;
      }

      [self finishPreviewCaptureWithImage:CGImageRetain(imageRef)
                                displayID:displayID
                               generation:generation
                            failureMessage:nil];
    }];
  }];
}

- (void)captureCoreGraphicsPreviewForDisplayID:(CGDirectDisplayID)displayID generation:(uint64_t)generation {
  dispatch_async(self.previewCaptureQueue, ^{
    CGImageRef imageRef = VSMCopyPreviewImage(displayID);

    [self finishPreviewCaptureWithImage:imageRef
                              displayID:displayID
                             generation:generation
                          failureMessage:@"Preview unavailable. Grant Screen Recording permission and restart the app."];
  });
}

- (void)finishPreviewCaptureWithImage:(CGImageRef)imageRef
                            displayID:(CGDirectDisplayID)displayID
                           generation:(uint64_t)generation
                        failureMessage:(NSString *)failureMessage {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (generation != self.previewGeneration || displayID != self.virtualDisplayID || !self.virtualDisplay) {
      if (imageRef) {
        CGImageRelease(imageRef);
      }
      self.previewCaptureInFlight = NO;
      return;
    }

    if (!imageRef) {
      self.previewView.image = nil;
      self.previewView.message = failureMessage ?: @"Preview unavailable.";
      self.previewCaptureInFlight = NO;
      return;
    }

    NSImage *image = [[NSImage alloc] initWithCGImage:imageRef
                                                size:NSMakeSize(CGImageGetWidth(imageRef), CGImageGetHeight(imageRef))];
    CGImageRelease(imageRef);
    self.previewView.image = image;
    self.previewCaptureInFlight = NO;
  });
}

- (void)refreshDisplayList:(id)sender {
  (void)sender;
  self.displayListView.string = VSMDisplayListText();
}

- (void)refreshCaptureAccess:(id)sender {
  (void)sender;
  if (VSMScreenCaptureAccessGranted()) {
    self.statusLabel.stringValue = @"Permission preflight active";
    if (self.virtualDisplay) {
      self.previewView.message = @"Waiting for display frames...";
      [self startPreviewTimer];
    }
    return;
  }

  self.statusLabel.stringValue = @"Preflight inactive; trying capture";
  if (self.virtualDisplay) {
    self.previewView.message = @"Trying preview capture...";
    [self startPreviewTimer];
  }
}

- (void)gridChanged:(id)sender {
  (void)sender;
  self.previewView.showGrid = self.gridButton.state == NSControlStateValueOn;
  [self.previewView setNeedsDisplay:YES];
}

- (void)openDisplaySettings:(id)sender {
  (void)sender;
  NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.Displays-Settings.extension"];
  if (![[NSWorkspace sharedWorkspace] openURL:url]) {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:@"/System/Applications/System Settings.app"]];
  }
}

- (void)openRecordingPrivacySettings:(id)sender {
  (void)sender;
  NSArray<NSString *> *urls = @[
    @"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
    @"x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
  ];

  for (NSString *urlString in urls) {
    NSURL *url = [NSURL URLWithString:urlString];
    if ([[NSWorkspace sharedWorkspace] openURL:url]) {
      return;
    }
  }

  [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:@"/System/Applications/System Settings.app"]];
}

- (void)showError:(NSString *)message {
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"Could not create virtual display";
  alert.informativeText = message;
  alert.alertStyle = NSAlertStyleWarning;
  [alert addButtonWithTitle:@"OK"];
  [alert runModal];
}

@end

static int VSMSelfTest(void) {
  @autoreleasepool {
    VSMVirtualDisplayConfig config = VSMDefaultConfig();
    config.name = @"Virtual Second Monitor Self Test";
    config.width = 640;
    config.height = 480;
    config.ppi = 96;
    config.serialNumber = VSMAutoSerialNumber();

    NSString *errorMessage = nil;
    CGVirtualDisplay *display = VSMCreateVirtualDisplay(config, &errorMessage);
    if (!display) {
      fprintf(stderr, "self-test create failed: %s\n", [VSMErrorString(errorMessage) UTF8String]);
      return 1;
    }

    printf("self-test created display id=%u\n", display.displayID);
    [NSThread sleepForTimeInterval:0.8];
    printf("%s", [VSMDisplayListText() UTF8String]);
    display = nil;
    [NSThread sleepForTimeInterval:0.6];
    return 0;
  }
}

int main(int argc, const char *argv[]) {
  if (argc > 1 && strcmp(argv[1], "--self-test") == 0) {
    return VSMSelfTest();
  }

  @autoreleasepool {
    NSApplication *app = [NSApplication sharedApplication];
    app.activationPolicy = NSApplicationActivationPolicyRegular;
    VSMAppDelegate *delegate = [[VSMAppDelegate alloc] init];
    app.delegate = delegate;
    [app run];
  }
  return 0;
}
