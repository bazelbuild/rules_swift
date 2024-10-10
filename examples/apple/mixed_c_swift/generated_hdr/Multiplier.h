// Copyright 2024 The Bazel Authors. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import <Foundation/Foundation.h>

NS_HEADER_AUDIT_BEGIN(nullability, sendability)

/// Types that perform some kind of multiplication should conform to this protocol.
@protocol Multiplier <NSObject>
- (NSInteger)valueByMultiplying:(NSInteger)value;
@end

// Imagine that `Squarer` also used to be here, but then a teammate who was
// really eager to use Swift rewrote it there.

/// A `Multiplier` that cubes values.
@interface Cuber : NSObject <Multiplier>
- (instancetype)init;
@end

NS_HEADER_AUDIT_END(nullability, sendability)
