#import "third_party/bazel_rules/rules_swift/test/fixtures/local_defines/mixed_lib.h"
#import <Foundation/Foundation.h>

#ifndef LOCAL_FOO
#error LOCAL_FOO should be defined
#endif

#ifndef PROPAGATED_BAR
#error PROPAGATED_BAR should be defined
#endif

@implementation MixedLib
- (void)doSomething {
    NSLog(@"Doing something with Foundation");
}
@end
