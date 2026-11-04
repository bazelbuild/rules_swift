#import <Foundation/Foundation.h>
#import "test/fixtures/local_defines/mixed_lib.h"

#ifdef LOCAL_FOO
#error LOCAL_FOO should NOT be defined
#endif

#ifndef PROPAGATED_BAR
#error PROPAGATED_BAR should be defined
#endif

@interface Dependent : NSObject
- (void)doSomethingElse;
@end

@implementation Dependent
- (void)doSomethingElse {
  NSLog(@"Dependent doing something");
}
@end
