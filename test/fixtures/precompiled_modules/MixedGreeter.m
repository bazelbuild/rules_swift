#import "test/fixtures/precompiled_modules/MixedGreeter.h"

@implementation MixedGreeterObjC

+ (NSString *)objcGreeting {
    return @"Hello from Obj-C side of mixed module!";
}

@end
