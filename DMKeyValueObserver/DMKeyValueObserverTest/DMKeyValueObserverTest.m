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


@interface MyClass : NSObject
@property (nonatomic, retain) MyClass *nestedObj;
@property (nonatomic, retain) id leafValue;
@end

@implementation MyClass
@synthesize nestedObj, leafValue;
@end

@implementation DMKeyValueObserverTest

- (void)testOwnerTearDown;
{
    NSMutableDictionary *mdict = [NSMutableDictionary dictionary];
    NSObject *dummyOwner = [NSObject new];
    
    __block NSUInteger callCount = 0;
    DMKeyValueObserver *observer = [[DMKeyValueObserver alloc] initWithKeyPath:@"name" object:mdict attachedToOwner:dummyOwner options:0 action:^(NSDictionary *changeDict, id localOwner, DMKeyValueObserver *observer) {
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
        DMKeyValueObserver *observer = [[DMKeyValueObserver alloc] initWithKeyPath:@"arrangedObjects" object:ac attachedToOwner:dummyOwner options:NSKeyValueObservingOptionInitial action:^(NSDictionary *changeDict, id localOwner, DMKeyValueObserver *observer) {
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
        DMKeyValueObserver *observer = [[DMKeyValueObserver alloc] initWithKeyPath:@"arrangedObjects" object:ac attachedToOwner:dummyOwner options:NSKeyValueObservingOptionInitial action:^(NSDictionary *changeDict, id localOwner, DMKeyValueObserver *observer) { }];
        
        // Should pass
        [observer invalidate];
        ac = nil;
        dummyOwner = nil;
    }
    {
        NSMutableDictionary *mdict = [NSMutableDictionary dictionary];
        NSObject *dummyOwner = [NSObject new];
        
        DMKeyValueObserver *observer = [[DMKeyValueObserver alloc] initWithKeyPath:@"name" object:mdict attachedToOwner:dummyOwner options:0 action:^(NSDictionary *changeDict, id localOwner, DMKeyValueObserver *observer) { }];
        
        STAssertNotNil(observer, nil);
        mdict = nil; // Should log
    }
    {
        // NSArrayController (and other NSController subclasses) have custom observer tracking code
        NSArrayController *ac = [[NSArrayController alloc] initWithContent:[NSArray arrayWithObjects:@"1", @"2", nil]];
        NSObject *dummyOwner = [NSObject new];
        (void)[[DMKeyValueObserver alloc] initWithKeyPath:@"arrangedObjects" object:ac attachedToOwner:dummyOwner options:NSKeyValueObservingOptionInitial action:^(NSDictionary *changeDict, id localOwner, DMKeyValueObserver *observer) { }];
        
        ac = nil; // Should log
    }
}

- (void)testSelfObservation;
{
    /* The goal: Many classes want to say something like, "when nested key-path a.b.c is changed, do this".
     * (For un-nested changes, we'd just typically override the setter.) It would also be nice to declare this
     * once, i.e. "when (self.)a.b.c changes, fire X", instead of manually maintaining the observation in the
     * setter -setA: (which is more code, with more things to go wrong).
     *
     * This required changing DMObserverInvalidator such that -invalidate is sent earlier in the
     * deallocation process. */
    {
        MyClass *twoLevel = [MyClass new];
        MyClass *nestedObj = [MyClass new];
        twoLevel.nestedObj = nestedObj;
        twoLevel.nestedObj.leafValue = @"Kitten";

        __block NSUInteger callCount = 0;
        [DMKeyValueObserver observerWithKeyPath:@"nestedObj.leafValue" object:twoLevel attachedToOwner:twoLevel action:^(NSDictionary *changeDict, id localSelf, DMKeyValueObserver *observer) {
            callCount++;
        }];
        STAssertEquals(callCount, 0UL, nil);

        nestedObj.leafValue = @"Puppy";
        STAssertEquals(callCount, 1UL, nil);
        twoLevel.nestedObj.leafValue = @"Bunny";
        STAssertEquals(callCount, 2UL, nil);

        twoLevel = nil;

        // Shouldn't crash:
        nestedObj.leafValue = @"Badger";
        nestedObj = nil;
    }
    // Let's make things harder. Use a key-path that passes through 'self' multiple times: A -> B -> A -> B -> leafValue
    {
        MyClass *a = [MyClass new], *b = [MyClass new];
        a.nestedObj = b; b.nestedObj = a;

        __block NSUInteger callCount = 0;
        [DMKeyValueObserver observerWithKeyPath:@"nestedObj.nestedObj.nestedObj.leafValue" object:a attachedToOwner:a action:^(NSDictionary *changeDict, id localSelf, DMKeyValueObserver *observer) {
            callCount++;
        }];
        STAssertEquals(callCount, 0UL, nil);

        b.leafValue = @"Kitten";
        STAssertEquals(callCount, 1UL, nil);
        b.leafValue = @"Puppy";
        STAssertEquals(callCount, 2UL, nil);

        a = nil;
        b.nestedObj = nil;

        // Shouldn't crash:
        b.leafValue = @"Badger";
        b = nil;
    }
}

@end
