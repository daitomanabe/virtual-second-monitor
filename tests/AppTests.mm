// Exercise the production AppKit controller; hold captures to test late callbacks deterministically.
#define main VSMApplicationMain
#import "../native/VirtualSecondMonitorApp.mm"
#undef main

@interface VSMTestDelegate : VSMAppDelegate
@property(copy, nonatomic) NSString *lastError;
@property(nonatomic) NSUInteger captureCount;
@property(nonatomic) CGDirectDisplayID capturedID;
@property(nonatomic) uint64_t capturedGeneration;
@end
@implementation VSMTestDelegate
- (void)showError:(NSString *)message { self.lastError = message; }
- (void)captureScreenCaptureKitPreviewForDisplayID:(CGDirectDisplayID)displayID generation:(uint64_t)generation {
  self.captureCount++;
  self.capturedID = displayID;
  self.capturedGeneration = generation;
}
- (void)captureCoreGraphicsPreviewForDisplayID:(CGDirectDisplayID)displayID generation:(uint64_t)generation {
  self.captureCount++;
  self.capturedID = displayID;
  self.capturedGeneration = generation;
}
@end

static void Check(BOOL condition, NSString *message) {
  if (!condition) @throw [NSException exceptionWithName:@"TestFailure" reason:message userInfo:nil];
}

int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    VSMTestDelegate *delegate = [[VSMTestDelegate alloc] init];
    int result = 0;
    @try {
      [delegate applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:NSApp]];
      delegate.widthField.stringValue = @"640";
      delegate.heightField.stringValue = @"480";
      for (NSUInteger i = 0; i < 8; i++) {
        @autoreleasepool { [delegate createDisplay:nil]; }
        Check(delegate.displayManager.displays.count == i + 1, delegate.lastError ?: @"Add failed");
      }
      Check(delegate.monitorTable.numberOfRows == 8, @"Table must contain all eight displays");
      Check(!delegate.createButton.enabled, @"Add must be disabled at the cap");
      Check(delegate.removeButton.enabled && delegate.removeAllButton.enabled, @"Removal must be available");
      NSArray<VSMManagedDisplay *> *original = delegate.displayManager.displays;
      [delegate createDisplay:nil];
      Check(delegate.lastError != nil && delegate.displayManager.displays.count == 8, @"Action must also enforce the cap");
      printf("PASS: app adds eight monitors and enforces capacity in UI and action\n");

      // The first request is still in flight while eight additions and selection changes occur.
      Check(delegate.captureCount == 1, @"Switching displays must not overlap captures");
      CGDirectDisplayID oldID = delegate.capturedID;
      uint64_t oldGeneration = delegate.capturedGeneration;
      [delegate.monitorTable selectRowIndexes:[NSIndexSet indexSetWithIndex:3] byExtendingSelection:NO];
      Check(delegate.selectedDisplayID == original[3].displayID, @"Table selection did not select the monitor");
      [delegate applyPreviewImage:NULL displayID:oldID generation:oldGeneration failureMessage:@"STALE"];
      Check(![delegate.previewView.message isEqualToString:@"STALE"], @"Late callback replaced the selected preview");
      [delegate updatePreview:nil];
      Check(delegate.captureCount == 2 && delegate.capturedID == original[3].displayID, [NSString stringWithFormat:@"Capture did not resume: count=%lu captured=%u expected=%u inFlight=%d", (unsigned long)delegate.captureCount, delegate.capturedID, original[3].displayID, delegate.previewCaptureInFlight]);
      [delegate previewRateChanged:nil];
      Check(delegate.captureCount == 2, @"Changing preview rate overlapped a capture");
      printf("PASS: selection and preview rate changes reject stale frames without overlapping captures\n");

      CGDirectDisplayID removedID = delegate.selectedDisplayID;
      [delegate removeDisplay:nil];
      Check(delegate.displayManager.displays.count == 7 && delegate.monitorTable.numberOfRows == 7, @"Remove must affect one monitor");
      Check(delegate.selectedDisplayID != removedID && delegate.selectedDisplay != nil, @"Selection must move to a surviving display");
      Check(delegate.createButton.enabled, @"Capacity must become available after removal");
      NSSet *before = [NSSet setWithArray:[delegate.displayManager.displays valueForKey:@"displayID"]];
      for (NSString *value in @[@"0", @"-1", @"640junk", @"4294967936"]) {
        delegate.widthField.stringValue = value;
        delegate.lastError = nil;
        [delegate createDisplay:nil];
        Check(delegate.lastError != nil, @"Invalid width must report an error");
        Check([before isEqualToSet:[NSSet setWithArray:[delegate.displayManager.displays valueForKey:@"displayID"]]], @"Failed add changed existing monitors");
      }
      delegate.widthField.stringValue = @"640";
      delegate.serialField.stringValue = [NSString stringWithFormat:@"%u", delegate.selectedDisplay.config.serialNumber];
      delegate.lastError = nil;
      [delegate createDisplay:nil];
      Check(delegate.lastError != nil && delegate.displayManager.displays.count == 7, @"Duplicate serial must preserve the current monitors");
      delegate.serialField.stringValue = @"";
      @autoreleasepool { [delegate createDisplay:nil]; }
      Check(delegate.displayManager.displays.count == 8 && !delegate.createButton.enabled, @"Freed slot should accept another display");
      printf("PASS: individual removal, failed additions, duplicate serial and replacement preserve the other monitors\n");

      [delegate removeAllDisplays:nil];
      [delegate applyPreviewImage:NULL displayID:delegate.capturedID generation:delegate.capturedGeneration failureMessage:@"STALE"];
      Check(delegate.displayManager.displays.count == 0 && delegate.monitorTable.numberOfRows == 0, @"Remove All left entries behind");
      Check(delegate.selectedDisplayID == 0 && delegate.previewTimer == nil && delegate.previewView.image == nil, @"Empty state retains preview state");
      Check(delegate.createButton.enabled && !delegate.removeButton.enabled && !delegate.removeAllButton.enabled, @"Empty state buttons are wrong");
      Check(![delegate.previewView.message isEqualToString:@"STALE"], @"Late callback overwrote the empty state");
      printf("PASS: Remove All resets selection, controls and preview, including a late callback\n");
    } @catch (NSException *exception) {
      fprintf(stderr, "FAIL: %s\n", exception.reason.UTF8String);
      result = 1;
    } @finally {
      [delegate applicationWillTerminate:[NSNotification notificationWithName:NSApplicationWillTerminateNotification object:NSApp]];
      [delegate.window orderOut:nil];
    }
    return result;
  }
}
