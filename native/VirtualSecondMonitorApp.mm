#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
#import <stdlib.h>

#import "VSMDisplayManager.h"
#import <math.h>

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
    _showGrid = NO;
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

@interface VSMAppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate>
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
@property(strong, nonatomic) NSButton *removeAllButton;
@property(strong, nonatomic) NSTableView *monitorTable;
@property(strong, nonatomic) NSTextField *monitorCountLabel;
@property(nonatomic) BOOL reloadingMonitorTable;
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
@property(strong, nonatomic) VSMDisplayManager *displayManager;
@property(nonatomic) CGDirectDisplayID selectedDisplayID;
@property(readonly, nonatomic) VSMManagedDisplay *selectedDisplay;
@property(strong, nonatomic) NSArray<NSDictionary *> *presets;
@end

@implementation VSMAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  (void)notification;
  self.displayManager = [[VSMDisplayManager alloc] init];
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
  [self.displayManager removeAllDisplays];
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

  NSRect frame = NSMakeRect(0, 0, 1160, 820);
  self.window = [[NSWindow alloc] initWithContentRect:frame
                                           styleMask:(NSWindowStyleMaskTitled |
                                                      NSWindowStyleMaskClosable |
                                                      NSWindowStyleMaskMiniaturizable |
                                                      NSWindowStyleMaskResizable)
                                             backing:NSBackingStoreBuffered
                                               defer:NO];
  self.window.title = @"Virtual Second Monitor";
  self.window.minSize = NSMakeSize(1060, 760);
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
  [self reloadMonitors];
  [self.controlScrollView.documentView scrollPoint:NSMakePoint(0, NSHeight(self.controlScrollView.documentView.bounds))];
}

- (void)buildControlsInView:(NSView *)content {
  self.controlScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
  self.controlScrollView.hasVerticalScroller = YES;
  self.controlScrollView.borderType = NSNoBorder;
  self.controlScrollView.drawsBackground = NO;
  [content addSubview:self.controlScrollView];

  NSView *document = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 320, 1100)];
  document.wantsLayer = YES;
  document.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.105 green:0.118 blue:0.137 alpha:1.0].CGColor;
  self.controlScrollView.documentView = document;

  CGFloat y = 1068.0;
  NSTextField *title = [self label:@"Virtual Second Monitor" size:22.0 weight:NSFontWeightBold];
  title.frame = VSMTopRect(&y, 18.0, 284.0, 30.0, 12.0);
  [document addSubview:title];

  NSTextField *subtitle = [self label:@"Connect up to 8 virtual monitors. Select one to preview or remove." size:12.0 weight:NSFontWeightRegular];
  subtitle.textColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.62];
  subtitle.frame = VSMTopRect(&y, 18.0, 284.0, 36.0, 18.0);
  [document addSubview:subtitle];

  self.statusLabel = [self label:@"Idle" size:13.0 weight:NSFontWeightSemibold];
  self.statusLabel.textColor = [NSColor colorWithCalibratedRed:0.62 green:0.86 blue:1.0 alpha:1.0];
  self.statusLabel.frame = VSMTopRect(&y, 18.0, 284.0, 22.0, 18.0);
  [document addSubview:self.statusLabel];

  [self addSectionLabel:@"New monitor preset" toView:document y:&y];
  self.presetPopup = [[NSPopUpButton alloc] initWithFrame:VSMTopRect(&y, 18.0, 284.0, 32.0, 14.0)];
  for (NSDictionary *preset in self.presets) {
    [self.presetPopup addItemWithTitle:preset[@"title"]];
  }
  self.presetPopup.target = self;
  self.presetPopup.action = @selector(presetChanged:);
  [document addSubview:self.presetPopup];

  [self addSectionLabel:@"Display" toView:document y:&y];
  [self addSmallLabel:@"Name" toView:document y:&y];
  self.nameField = [self textField:@"Virtual Monitor 1"];
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
  self.createButton = [self button:@"Add Monitor" action:@selector(createDisplay:)];
  self.createButton.frame = VSMTopRect(&y, 18.0, 284.0, 34.0, 12.0);
  [document addSubview:self.createButton];

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
  self.gridButton.state = NSControlStateValueOff;
  self.gridButton.target = self;
  self.gridButton.action = @selector(gridChanged:);
  self.gridButton.frame = VSMTopRect(&y, 18.0, 284.0, 24.0, 10.0);
  [document addSubview:self.gridButton];

  NSTextField *note = [self label:@"If preview is blank, grant Screen Recording permission to this app and restart it." size:12.0 weight:NSFontWeightRegular];
  note.textColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.58];
  note.frame = VSMTopRect(&y, 18.0, 284.0, 56.0, 0.0);
  [document addSubview:note];
  CGFloat offset = 24.0 - y;
  for (NSView *view in document.subviews) {
    NSRect frame = view.frame;
    frame.origin.y += offset;
    view.frame = frame;
  }
  [document setFrameSize:NSMakeSize(320, 1100 + offset)];
}

- (void)buildPreviewInView:(NSView *)content {
  self.monitorCountLabel = [self label:@"Virtual Monitors — 0 / 8" size:18 weight:NSFontWeightBold];
  [content addSubview:self.monitorCountLabel];
  self.removeButton = [self button:@"Remove Selected" action:@selector(removeDisplay:)];
  self.removeAllButton = [self button:@"Remove All" action:@selector(removeAllDisplays:)];
  [content addSubview:self.removeButton];
  [content addSubview:self.removeAllButton];

  NSScrollView *monitors = [[NSScrollView alloc] initWithFrame:NSZeroRect];
  monitors.identifier = @"monitorScroll";
  monitors.hasVerticalScroller = YES;
  monitors.borderType = NSBezelBorder;
  self.monitorTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
  self.monitorTable.rowHeight = 21;
  self.monitorTable.intercellSpacing = NSMakeSize(3, 1);
  self.monitorTable.usesAlternatingRowBackgroundColors = YES;
  self.monitorTable.allowsMultipleSelection = NO;
  self.monitorTable.allowsEmptySelection = NO;
  for (NSArray *columnInfo in @[@[@"name", @"Monitor", @220], @[@"mode", @"Resolution", @160],
                               @[@"id", @"Display ID", @80], @[@"serial", @"Serial", @100]]) {
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:columnInfo[0]];
    column.title = columnInfo[1];
    column.width = [columnInfo[2] doubleValue];
    column.minWidth = 60;
    column.editable = NO;
    [self.monitorTable addTableColumn:column];
  }
  self.monitorTable.dataSource = self;
  self.monitorTable.delegate = self;
  monitors.documentView = self.monitorTable;
  [content addSubview:monitors];

  self.previewTitleLabel = [self label:@"Preview" size:18.0 weight:NSFontWeightBold];
  [content addSubview:self.previewTitleLabel];

  self.previewMetaLabel = [self label:@"No virtual display" size:13.0 weight:NSFontWeightRegular];
  self.previewTitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  self.previewMetaLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  self.previewMetaLabel.textColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.62];
  [content addSubview:self.previewMetaLabel];

  self.previewView = [[VSMPreviewView alloc] initWithFrame:NSZeroRect];
  self.previewView.showGrid = self.gridButton.state == NSControlStateValueOn;
  [content addSubview:self.previewView];

  NSTextField *displayListLabel = [self label:@"Online Displays" size:14.0 weight:NSFontWeightBold];
  displayListLabel.identifier = @"displayListLabel";
  [content addSubview:displayListLabel];

  NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
  scroll.identifier = @"displayListScroll";
  scroll.hasVerticalScroller = YES;
  scroll.hasHorizontalScroller = YES;
  scroll.borderType = NSBezelBorder;
  self.displayListView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 1100, 124)];
  self.displayListView.minSize = NSMakeSize(1100, 124);
  self.displayListView.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
  self.displayListView.verticallyResizable = YES;
  self.displayListView.horizontallyResizable = NO;
  self.displayListView.textContainer.widthTracksTextView = YES;
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
  self.monitorCountLabel.frame = NSMakeRect(rightX, height - 40, rightWidth - 270, 24);
  self.removeButton.frame = NSMakeRect(width - 276, height - 43, 142, 30);
  self.removeAllButton.frame = NSMakeRect(width - 130, height - 43, 112, 30);
  self.previewTitleLabel.frame = NSMakeRect(rightX, height - 290, rightWidth, 24);
  self.previewMetaLabel.frame = NSMakeRect(rightX, height - 314, rightWidth, 20);
  self.previewView.frame = NSMakeRect(rightX, 184, rightWidth, height - 510);

  for (NSView *view in content.subviews) {
    if ([view.identifier isEqualToString:@"monitorScroll"]) {
      view.frame = NSMakeRect(rightX, height - 260, rightWidth, 202);
    } else if ([view.identifier isEqualToString:@"displayListLabel"]) {
      view.frame = NSMakeRect(rightX, 152, rightWidth, 20);
    } else if ([view.identifier isEqualToString:@"displayListScroll"]) {
      view.frame = NSMakeRect(rightX, 18, rightWidth, 124);
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

- (BOOL)readUnsignedField:(NSTextField *)field value:(unsigned int *)value {
  NSString *text = [field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (text.length == 0 || [text rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet]].location != NSNotFound) return NO;
  unsigned long long number = 0;
  NSScanner *scanner = [NSScanner scannerWithString:text];
  if (![scanner scanUnsignedLongLong:&number] || !scanner.isAtEnd || number > UINT_MAX) return NO;
  *value = (unsigned int)number;
  return YES;
}

- (BOOL)configFromFields:(VSMVirtualDisplayConfig *)config {
  *config = VSMDefaultConfig();
  config->name = self.nameField.stringValue.length > 0 ? self.nameField.stringValue : [self nextMonitorName];
  if (![self readUnsignedField:self.widthField value:&config->width] ||
      ![self readUnsignedField:self.heightField value:&config->height] ||
      ![self readUnsignedField:self.ppiField value:&config->ppi]) return NO;
  NSString *serialText = [self.serialField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (serialText.length > 0 && ![self readUnsignedField:self.serialField value:&config->serialNumber]) return NO;
  NSScanner *scanner = [NSScanner scannerWithString:self.refreshField.stringValue];
  double refresh = 0;
  if (![scanner scanDouble:&refresh] || !scanner.isAtEnd || !isfinite(refresh) || refresh <= 0) return NO;
  config->refreshRate = refresh;
  config->hiDPI = self.hiDPIButton.state == NSControlStateValueOn;
  return YES;
}

- (VSMManagedDisplay *)selectedDisplay {
  for (VSMManagedDisplay *entry in self.displayManager.displays) {
    if (entry.displayID == self.selectedDisplayID) return entry;
  }
  return nil;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
  (void)tableView;
  return self.displayManager.displays.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
  (void)tableView;
  NSArray<VSMManagedDisplay *> *displays = self.displayManager.displays;
  if (row < 0 || row >= (NSInteger)displays.count) return @"";
  VSMManagedDisplay *entry = displays[row];
  VSMVirtualDisplayConfig config = entry.config;
  if ([column.identifier isEqualToString:@"name"]) return config.name;
  if ([column.identifier isEqualToString:@"mode"]) return [NSString stringWithFormat:@"%u x %u%@", config.width, config.height, config.hiDPI ? @" HiDPI" : @""];
  if ([column.identifier isEqualToString:@"id"]) return [NSString stringWithFormat:@"%u", entry.displayID];
  return [NSString stringWithFormat:@"%u", config.serialNumber];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
  (void)notification;
  if (self.reloadingMonitorTable) return;
  NSInteger row = self.monitorTable.selectedRow;
  NSArray<VSMManagedDisplay *> *displays = self.displayManager.displays;
  self.selectedDisplayID = row >= 0 && row < (NSInteger)displays.count ? displays[row].displayID : 0;
  [self updateSelection];
}

- (void)reloadMonitors {
  self.reloadingMonitorTable = YES;
  [self.monitorTable reloadData];
  NSInteger row = -1;
  NSArray<VSMManagedDisplay *> *displays = self.displayManager.displays;
  for (NSUInteger i = 0; i < displays.count; i++) {
    if (displays[i].displayID == self.selectedDisplayID) row = i;
  }
  if (row < 0 && displays.count > 0) {
    row = 0;
    self.selectedDisplayID = displays[0].displayID;
  }
  if (row >= 0) {
    [self.monitorTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    [self.monitorTable scrollRowToVisible:row];
  } else {
    self.selectedDisplayID = 0;
    [self.monitorTable deselectAll:nil];
  }
  self.reloadingMonitorTable = NO;
  self.monitorCountLabel.stringValue = [NSString stringWithFormat:@"Virtual Monitors — %lu / 8", (unsigned long)displays.count];
  self.createButton.enabled = displays.count < VSMMaximumDisplayCount;
  self.createButton.title = self.createButton.enabled ? @"Add Monitor" : @"Maximum 8 Monitors";
  self.removeAllButton.enabled = displays.count > 0;
  [self updateSelection];
}

- (void)updateSelection {
  [self.previewTimer invalidate];
  self.previewTimer = nil;
  self.previewGeneration++;
  self.previewView.image = nil;
  VSMManagedDisplay *selected = self.selectedDisplay;
  self.removeButton.enabled = selected != nil;
  self.previewTitleLabel.stringValue = selected ? [NSString stringWithFormat:@"Preview — %@", selected.config.name] : @"Preview";
  self.previewView.message = selected ? @"Waiting for display frames..." : @"Add a monitor to preview it here.";
  if (selected) {
    self.previewView.displaySize = CGSizeMake(selected.config.width, selected.config.height);
    [self startPreviewTimer];
  }
  [self updatePreviewMetaLabel];
}

- (NSString *)nextMonitorName {
  NSMutableSet<NSString *> *names = [NSMutableSet set];
  for (VSMManagedDisplay *entry in self.displayManager.displays) [names addObject:entry.config.name];
  for (NSUInteger i = 1; ; i++) {
    NSString *name = [NSString stringWithFormat:@"Virtual Monitor %lu", (unsigned long)i];
    if (![names containsObject:name]) return name;
  }
}

- (void)createDisplay:(id)sender {
  (void)sender;
  VSMVirtualDisplayConfig config;
  if (![self configFromFields:&config]) {
    self.statusLabel.stringValue = @"Invalid monitor settings";
    [self showError:@"Use whole numbers for resolution, PPI and serial, and a positive refresh rate."];
    return;
  }
  double requestedPixels = (double)config.width * (double)config.height;
  if (!config.hiDPI && requestedPixels >= 3840.0 * 2160.0) {
    config.hiDPI = YES;
    self.hiDPIButton.state = NSControlStateValueOn;
  }

  NSString *errorMessage = nil;
  VSMManagedDisplay *display = [self.displayManager addDisplayWithConfig:config error:&errorMessage];
  if (!display) {
    self.statusLabel.stringValue = @"Could not add monitor";
    [self showError:errorMessage ?: @"Unknown error"];
    return;
  }
  self.selectedDisplayID = display.displayID;
  self.statusLabel.stringValue = [NSString stringWithFormat:@"Added monitor id %u", display.displayID];
  self.nameField.stringValue = [self nextMonitorName];
  self.serialField.stringValue = @"";
  [self reloadMonitors];
  [self refreshDisplayList:nil];
}

- (void)removeDisplay:(id)sender {
  (void)sender;
  if (!self.selectedDisplay) return;
  CGDirectDisplayID removedID = self.selectedDisplayID;
  [self.displayManager removeDisplayWithID:removedID];
  [self reloadMonitors];
  self.statusLabel.stringValue = [NSString stringWithFormat:@"Removed monitor id %u", removedID];
  [self refreshDisplayList:nil];
}

- (void)removeAllDisplays:(id)sender {
  (void)sender;
  [self.displayManager removeAllDisplays];
  [self reloadMonitors];
  self.statusLabel.stringValue = @"All virtual monitors removed";
  [self refreshDisplayList:nil];
}

- (void)startPreviewTimer {
  [self.previewTimer invalidate];
  self.previewGeneration++;
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
  if (self.selectedDisplay) {
    [self startPreviewTimer];
    [self updatePreviewMetaLabel];
  }
}

- (void)updatePreviewMetaLabel {
  if (!self.selectedDisplay || self.selectedDisplayID == 0) {
    self.previewMetaLabel.stringValue = @"No virtual display";
    return;
  }

  self.previewMetaLabel.stringValue = [NSString stringWithFormat:@"id %u  %@  %ux%u%@  %@",
                                       self.selectedDisplayID,
                                       self.selectedDisplay.config.name,
                                       self.selectedDisplay.config.width,
                                       self.selectedDisplay.config.height,
                                       self.selectedDisplay.config.hiDPI ? @"  HiDPI" : @"",
                                       [self previewRateDescription]];
}

- (void)updatePreview:(id)sender {
  (void)sender;
  if (!self.selectedDisplay || self.selectedDisplayID == 0) {
    return;
  }

  if (self.previewCaptureInFlight) {
    return;
  }

  self.previewCaptureInFlight = YES;
  CGDirectDisplayID displayID = self.selectedDisplayID;
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
    [self applyPreviewImage:imageRef displayID:displayID generation:generation failureMessage:failureMessage];
  });
}

// Main-thread completion. Only one capture remains in flight across selection changes.
- (void)applyPreviewImage:(CGImageRef)imageRef
                displayID:(CGDirectDisplayID)displayID
               generation:(uint64_t)generation
            failureMessage:(NSString *)failureMessage {
  if (generation != self.previewGeneration || displayID != self.selectedDisplayID || !self.selectedDisplay) {
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
}

- (void)refreshDisplayList:(id)sender {
  (void)sender;
  self.displayListView.string = VSMDisplayListText();
}

- (void)refreshCaptureAccess:(id)sender {
  (void)sender;
  if (VSMScreenCaptureAccessGranted()) {
    self.statusLabel.stringValue = @"Permission preflight active";
    if (self.selectedDisplay) {
      self.previewView.message = @"Waiting for display frames...";
      [self startPreviewTimer];
    }
    return;
  }

  self.statusLabel.stringValue = @"Preflight inactive; trying capture";
  if (self.selectedDisplay) {
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
    VSMDisplayManager *manager = [[VSMDisplayManager alloc] init];
    VSMManagedDisplay *display = [manager addDisplayWithConfig:config error:&errorMessage];
    if (!display) {
      fprintf(stderr, "self-test create failed: %s\n", [(errorMessage ?: @"Unknown error") UTF8String]);
      return 1;
    }

    printf("self-test created display id=%u\n", display.displayID);
    [NSThread sleepForTimeInterval:0.8];
    printf("%s", [VSMDisplayListText() UTF8String]);
    [manager removeAllDisplays];
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
