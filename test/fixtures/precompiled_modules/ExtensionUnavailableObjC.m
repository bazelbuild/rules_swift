#import "test/fixtures/precompiled_modules/ExtensionUnavailableObjC.h"

@implementation ExtensionUnavailableAPI

+ (NSString *)extensionUnavailableMessage {
  return @"extension unavailable Objective-C API";
}

@end
