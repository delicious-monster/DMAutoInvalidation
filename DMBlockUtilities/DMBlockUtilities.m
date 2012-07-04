//
//  DMBlockUtilities.m
//  DMBlockUtilities
//
//  Created by Jonathon Mah on 2012-06-07.
//  Copyright (c) 2012 Delicious Monster Software. All rights reserved.
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
    const unsigned long blockSize = blockAsLayout->descriptor->size;

    // We only pick out pointers that are all word-aligned
    uintptr_t curCapturedValueAddr = (uintptr_t)blockAsLayout + blockSize;
    curCapturedValueAddr += sizeof(id) - (curCapturedValueAddr % sizeof(id)); // Move to aligned address
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
