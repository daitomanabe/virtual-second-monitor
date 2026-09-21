#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

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

extern const NSUInteger VSMMaximumDisplayCount;
VSMVirtualDisplayConfig VSMDefaultConfig(void);
unsigned int VSMAutoSerialNumber(void);

@interface VSMManagedDisplay : NSObject
@property(readonly, nonatomic) CGDirectDisplayID displayID;
@property(readonly, nonatomic) VSMVirtualDisplayConfig config;
@end

// Call on one owning thread. Each entry owns its OS display until removed.
@interface VSMDisplayManager : NSObject
@property(readonly, copy, nonatomic) NSArray<VSMManagedDisplay *> *displays;
- (VSMManagedDisplay *)addDisplayWithConfig:(VSMVirtualDisplayConfig)config error:(NSString **)error;
- (BOOL)removeDisplayWithID:(CGDirectDisplayID)displayID;
- (void)removeAllDisplays;
@end
