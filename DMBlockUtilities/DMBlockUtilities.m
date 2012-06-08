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

    const struct Block_layout *blockAsLayout = (__bridge void *)block;
    const unsigned long blockSize = blockAsLayout->descriptor->size;

    // We only pick out pointers that are all word-aligned
    const void *curCapturedValue = (void *)((char *)blockAsLayout + blockSize);
    while (--curCapturedValue >= (void *)(blockAsLayout + 1)) // +1 adds sizeof(struct Block_layout), remember
        if (*(void **)curCapturedValue == (__bridge void *)object)
            return YES;
    return NO;
}

@end
