//
//  DMKeyValueObserverTest.m
//  DMKeyValueObserverTest
//
//  Created by Jonathon Mah on 2012-01-22.
//  Copyright 2012 Delicious Monster Software. All rights reserved.
//

#import <AppKit/AppKit.h>
#import "DMKeyValueObserverTest.h"

#import "DMKeyValueObserver.h"


@implementation DMKeyValueObserverTest

- (void)testOwnerTearDown;
{
    NSMutableDictionary *mdict = [NSMutableDictionary dictionary];
    NSObject *dummyOwner = [NSObject new];
    
    __block NSUInteger callCount = 0;
    DMKeyValueObserver *observer = [[DMKeyValueObserver alloc] initWithKeyPath:@"name" object:mdict owner:dummyOwner options:0 action:^(NSDictionary *changeDict, id localOwner, DMKeyValueObserver *observer) {
        callCount++;
    }];
    
    STAssertNotNil(observer, nil);
    STAssertEquals(callCount, 0UL, nil);
    
    [mdict setObject:[NSDate date] forKey:@"date"];
    STAssertEquals(callCount, 0UL, nil);
    [mdict setObject:@"Steve" forKey:@"name"];
    STAssertEquals(callCount, 1UL, nil);
    [mdict setObject:@"Bob" forKey:@"name"];
    STAssertEquals(callCount, 2UL, nil);
    
    dummyOwner = nil;
    [mdict setObject:@"Eric" forKey:@"name"];
    STAssertEquals(callCount, 2UL, @"Releasing owner should trigger invalidation of observer");
}

- (void)testPrematureTargetDeallocation;
{
    // It's rather hard to test this, because if premature target deallocation occurs the program will be in a corrupted state.
    {
        NSArrayController *ac = [[NSArrayController alloc] initWithContent:[NSArray arrayWithObjects:@"1", @"2", nil]];
        NSObject *dummyOwner = [NSObject new];
        
        __block NSUInteger callCount = 0;
        DMKeyValueObserver *observer = [[DMKeyValueObserver alloc] initWithKeyPath:@"arrangedObjects" object:ac owner:dummyOwner options:NSKeyValueObservingOptionInitial action:^(NSDictionary *changeDict, id localOwner, DMKeyValueObserver *observer) {
            callCount++;
        }];
        
        STAssertNotNil(observer, nil);
        STAssertEquals(callCount, 1UL, nil);
        [ac setSortDescriptors:[NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"self" ascending:NO]]];
        STAssertEquals(callCount, 2UL, nil);
        
        // Should pass
        dummyOwner = nil; // implicit invalidation
        ac = nil;
    }
    {
        NSArrayController *ac = [[NSArrayController alloc] initWithContent:[NSArray arrayWithObjects:@"1", @"2", nil]];
        NSObject *dummyOwner = [NSObject new];
        DMKeyValueObserver *observer = [[DMKeyValueObserver alloc] initWithKeyPath:@"arrangedObjects" object:ac owner:dummyOwner options:NSKeyValueObservingOptionInitial action:^(NSDictionary *changeDict, id localOwner, DMKeyValueObserver *observer) { }];
        
        // Should pass
        [observer invalidate];
        ac = nil;
        dummyOwner = nil;
    }
    // If the following code is run, messages should be logged and exceptions thrown - but memory corruption will also occur after the first group, so not all may run.
#if 0
    {
        NSMutableDictionary *mdict = [NSMutableDictionary dictionary];
        NSObject *dummyOwner = [NSObject new];
        
        DMKeyValueObserver *observer = [[DMKeyValueObserver alloc] initWithKeyPath:@"name" object:mdict owner:dummyOwner options:0 action:^(NSDictionary *changeDict, id localOwner, DMKeyValueObserver *observer) { }];
        
        STAssertNotNil(observer, nil);
        mdict = nil; // Should throw
    }
    {
        // NSArrayController (and other NSController subclasses) have custom observer tracking code
        NSArrayController *ac = [[NSArrayController alloc] initWithContent:[NSArray arrayWithObjects:@"1", @"2", nil]];
        NSObject *dummyOwner = [NSObject new];
        (void)[[DMKeyValueObserver alloc] initWithKeyPath:@"arrangedObjects" object:ac owner:dummyOwner options:NSKeyValueObservingOptionInitial action:^(NSDictionary *changeDict, id localOwner, DMKeyValueObserver *observer) { }];
        
        ac = nil; // Should throw
    }
#endif
}

@end
