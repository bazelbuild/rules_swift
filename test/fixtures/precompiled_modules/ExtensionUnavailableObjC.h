#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ExtensionUnavailableAPI : NSObject
+ (NSString *)extensionUnavailableMessage NS_EXTENSION_UNAVAILABLE("message");
@end

NS_ASSUME_NONNULL_END
