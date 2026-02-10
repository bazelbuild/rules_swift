#import "third_party/bazel_rules/rules_swift/test/fixtures/local_defines/mixed_lib.h"
#import <Foundation/Foundation.h>

#ifdef LOCAL_FOO
#error LOCAL_FOO should NOT be defined
#endif

#ifndef PROPAGATED_BAR
#error PROPAGATED_BAR should be defined
#endif

@implementation Dependent
- (void)doSomethingElse {
    NSLog(@"Dependent doing something");
}
@end
