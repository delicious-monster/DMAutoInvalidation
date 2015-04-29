//
//  DMBlockUtilities.m
//  DMBlockUtilities
//
//  Created by Jonathon Mah on 2012-06-07.
//  Copyright (c) 2012 Delicious Monster Software.
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "DMBlockUtilities.h"

#ifndef NS_BLOCK_ASSERTIONS
#import "Block_private.h"
#endif

#if !__has_feature(objc_arc)
#error This file needs Automatic Reference Counting (ARC).
#endif


@implementation DMBlockUtilities

+ (BOOL)isObject:(id)object implicitlyRetainedByBlock:(id)block;
{
    if (!block || !object)
        return NO;

#ifndef NS_BLOCK_ASSERTIONS
    const struct Block_layout *blockAsLayout = (__bridge void *)block;
    const ptrdiff_t blockSize = blockAsLayout->descriptor->size;

    // We only pick out pointers that are all word-aligned
    uintptr_t curCapturedValueAddr = (uintptr_t)blockAsLayout + blockSize;
    if (curCapturedValueAddr % sizeof(id))
        curCapturedValueAddr += sizeof(id) - (curCapturedValueAddr % sizeof(id)); // Move forward to aligned address (past size, but we walk back before dereferencing)
    while ((curCapturedValueAddr -= sizeof(id)) >= (uintptr_t)(blockAsLayout + 1)) // +1 adds sizeof(struct Block_layout), remember
        if (*(uintptr_t *)curCapturedValueAddr == (uintptr_t)object)
            return YES;
#else
    NSLog(@"%s Warning: Retained object detection disabled without assertions; this method will always return NO", __func__);
#endif
    return NO;
}

@end


void DMBlockRetainCycleDetected(NSString *msg)
{
    NSLog(@"WARNING: Retain cycle detected! %@ Break on DMBlockRetainCycleDetected to debug.", msg);
}
