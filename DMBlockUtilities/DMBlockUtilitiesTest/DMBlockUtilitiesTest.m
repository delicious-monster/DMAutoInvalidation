//
//  DMBlockUtilitiesTest.m
//  DMBlockUtilitiesTest
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

#import "DMBlockUtilitiesTest.h"

#import "DMBlockUtilities.h"

#if __has_feature(objc_arc)
#error This file MUST NOT be compiled with Automatic Reference Counting (ARC).
// The automatic block-copying stuff interferes too much.
#endif


@implementation DMBlockUtilitiesTest
{
    id _myIvar;
}

#pragma mark DMBlockUtilitiesTest

- (void)testStrongBlockObjectCapture;
{
    id capturedObject = [NSArray arrayWithObject:@"Yo"];
    id uncapturedObject = [NSArray arrayWithObject:@"Whoops"];

    dispatch_block_t blk = ^{
        NSLog(@"Hey, look what I captured: %@", capturedObject);
    };

    STAssertTrue([DMBlockUtilities isObject:capturedObject implicitlyRetainedByBlock:blk], @"Strong capture of object not detected");
    STAssertFalse([DMBlockUtilities isObject:uncapturedObject implicitlyRetainedByBlock:blk], @"False positive of object capture");

    dispatch_block_t blkCopy = [blk copy];
    STAssertTrue(blkCopy != blk, @"blk should be on stack, blkCopy on heap for following tests");
    STAssertTrue([DMBlockUtilities isObject:capturedObject implicitlyRetainedByBlock:blkCopy], @"Strong capture of object not detected");
    STAssertFalse([DMBlockUtilities isObject:uncapturedObject implicitlyRetainedByBlock:blkCopy], @"False positive of object capture");
}

- (void)testBlockIvarCapturesSelf;
{
    _myIvar = [NSDate date];

    dispatch_block_t blk = ^{
        NSLog(@"Hey, look what I captured: %@", _myIvar);
    };

    STAssertTrue([DMBlockUtilities isObject:self implicitlyRetainedByBlock:blk], @"Implicit capture of self from ivar capture not detected");
}

- (void)testByReferenceCapture;
{
    __block id blockSelf = self;
    id byValueObject = [NSMutableDictionary dictionary];

    dispatch_block_t blk = ^{
        NSLog(@"Hey, look what I captured: %@", blockSelf);
        [byValueObject self];
    };

    STAssertFalse([DMBlockUtilities isObject:self implicitlyRetainedByBlock:blk], @"Explicit __block capture of self shouldn't be considered by-value");
    STAssertTrue([DMBlockUtilities isObject:byValueObject implicitlyRetainedByBlock:blk], @"Capture of by-value object not detected");
}

- (void)testPointerAndNonWordCapture;
{
    char zee = 'z';
    id taggedObj = [NSDate date];
    short shirt = 10;
    long jacket = 20;
    id somethingElse = [NSArray arrayWithObject:@"the Cake is a lie"];

    dispatch_block_t blk = ^{
        NSLog(@"Hey, look what I captured: %c %@ %ld", zee, taggedObj, (long)(shirt + jacket));
        [somethingElse self];
    };

    STAssertTrue([DMBlockUtilities isObject:taggedObj implicitlyRetainedByBlock:blk], @"Capture of object along with non-word-sized types not detected");
    STAssertTrue([DMBlockUtilities isObject:somethingElse implicitlyRetainedByBlock:blk], @"Capture of object along with non-word-sized types not detected");
    STAssertFalse([DMBlockUtilities isObject:self implicitlyRetainedByBlock:blk], @"False positive of object capture");
}

@end
