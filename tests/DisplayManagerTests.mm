#import "../native/VSMDisplayManager.h"
#import <math.h>

static void Check(BOOL condition, NSString *message) {
  if (!condition) @throw [NSException exceptionWithName:@"TestFailure" reason:message userInfo:nil];
}

static BOOL WaitForOnline(CGDirectDisplayID displayID, BOOL online) {
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
  do {
    CGDirectDisplayID displays[128];
    uint32_t count = 0;
    BOOL found = NO;
    if (CGGetOnlineDisplayList(128, displays, &count) == kCGErrorSuccess) {
      for (uint32_t i = 0; i < count; i++) if (displays[i] == displayID) found = YES;
      if (found == online) return YES;
    }
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
  } while (deadline.timeIntervalSinceNow > 0);
  return NO;
}

int main(void) {
  @autoreleasepool {
    VSMDisplayManager *manager = [[VSMDisplayManager alloc] init];
    NSMutableArray<NSNumber *> *createdIDs = [NSMutableArray array];
    int result = 0;
    @try {
      NSMutableSet *serials = [NSMutableSet set];
      for (NSUInteger i = 0; i < VSMMaximumDisplayCount; i++) {
        @autoreleasepool {
          VSMVirtualDisplayConfig config = VSMDefaultConfig();
          config.width = 640; config.height = 480;
          config.name = [NSString stringWithFormat:@"VSM Runtime Test %lu", (unsigned long)i + 1];
          NSString *error = nil;
          VSMManagedDisplay *entry = [manager addDisplayWithConfig:config error:&error];
          Check(entry != nil, error ?: @"Display creation failed");
          Check(![serials containsObject:@(entry.config.serialNumber)], @"Serial collision");
          [serials addObject:@(entry.config.serialNumber)];
          [createdIDs addObject:@(entry.displayID)];
          Check(WaitForOnline(entry.displayID, YES), @"Created display did not come online");
        }
      }
      Check(manager.displays.count == 8, @"Expected eight managed displays");
      for (NSNumber *displayID in createdIDs) Check(CGDisplayIsOnline(displayID.unsignedIntValue), @"Eight displays must be online together");
      printf("PASS: eight simultaneous OS displays with unique serials\n");

      NSString *error = nil;
      Check([manager addDisplayWithConfig:VSMDefaultConfig() error:&error] == nil && error != nil, @"Ninth display must be rejected");
      Check(manager.displays.count == 8, @"Cap rejection changed existing displays");
      printf("PASS: ninth display rejected without replacing existing displays\n");

      // Keep a snapshot alive: removing an entry must still disconnect its OS display.
      NSArray<VSMManagedDisplay *> *snapshot = manager.displays;
      CGDirectDisplayID removedID = snapshot[3].displayID;
      Check([manager removeDisplayWithID:removedID], @"Individual removal failed");
      Check(WaitForOnline(removedID, NO), @"Removed display still online");
      for (VSMManagedDisplay *entry in manager.displays) Check(CGDisplayIsOnline(entry.displayID), @"Removal affected another display");
      Check(![manager removeDisplayWithID:removedID], @"Repeated removal should be harmless");
      printf("PASS: individual removal preserves the other seven displays\n");

      VSMVirtualDisplayConfig invalid = VSMDefaultConfig();
      invalid.width = 0;
      Check([manager addDisplayWithConfig:invalid error:&error] == nil, @"Invalid resolution accepted");
      invalid = VSMDefaultConfig(); invalid.refreshRate = NAN;
      Check([manager addDisplayWithConfig:invalid error:&error] == nil, @"NaN refresh accepted");
      invalid = VSMDefaultConfig(); invalid.serialNumber = manager.displays[0].config.serialNumber;
      Check([manager addDisplayWithConfig:invalid error:&error] == nil, @"Duplicate serial accepted");
      Check(manager.displays.count == 7, @"Failed creation changed the display count");
      printf("PASS: invalid settings and duplicate serial leave existing displays intact\n");

      @autoreleasepool {
        VSMVirtualDisplayConfig replacement = VSMDefaultConfig();
        replacement.width = 1280; replacement.height = 960; replacement.hiDPI = YES;
        replacement.name = @"VSM Runtime Test Replacement";
        VSMManagedDisplay *entry = [manager addDisplayWithConfig:replacement error:&error];
        Check(entry != nil, error ?: @"Could not reuse freed capacity");
        [createdIDs addObject:@(entry.displayID)];
        Check(WaitForOnline(entry.displayID, YES), @"Replacement did not come online");
      }
      Check(manager.displays.count == 8, @"Freed capacity was not reused");
      printf("PASS: removed slot accepts a new HiDPI monitor\n");
    } @catch (NSException *exception) {
      fprintf(stderr, "FAIL: %s\n", exception.reason.UTF8String);
      result = 1;
    } @finally {
      [manager removeAllDisplays];
      for (NSNumber *displayID in createdIDs) {
        if (!WaitForOnline(displayID.unsignedIntValue, NO)) {
          fprintf(stderr, "FAIL: cleanup left display %u online\n", displayID.unsignedIntValue);
          result = 1;
        }
      }
    }
    if (result == 0) printf("PASS: all test displays disconnected\n");
    return result;
  }
}
