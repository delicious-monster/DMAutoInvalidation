//
//  DMAutoInvalidation.m
//  Library
//
//  Created by Jonathon Mah on 2012-01-21.
//  Copyright (c) 2012 Delicious Monster Software. All rights reserved.
//

#import "DMAutoInvalidation.h"

#import <objc/runtime.h>


static char DMAutoInvalidatorAssociationKey, DMObserverOwnerAssociationKey;

@implementation DMObserverInvalidator {
    NSMutableSet *_observers;
}

#pragma mark NSObject

- (void)dealloc;
{
    for (id<DMAutoInvalidation> observer in _observers)
        [observer invalidate];
}

- (id)init;
{
    if (!(self = [super init]))
        return nil;
    _observers = [NSMutableSet set];
    return self;
}


#pragma mark API

+ (void)attachObserver:(id<DMAutoInvalidation>)observer toOwner:(id)owner;
{
    NSParameterAssert(observer && owner);
    static dispatch_once_t onceToken;
    static dispatch_semaphore_t invalidatorAssociationMutex;
    dispatch_once(&onceToken, ^{
        invalidatorAssociationMutex = dispatch_semaphore_create(1);
    });
    
    // Tie the observer to the owner
    DMObserverInvalidator *invalidator = objc_getAssociatedObject(owner, &DMAutoInvalidatorAssociationKey);
    if (!invalidator) {
        // Protect against a race creating the associated set. Don't @synchronize on the owner, because someone else could be doing that and we'll deadlock.
        dispatch_semaphore_wait(invalidatorAssociationMutex, DISPATCH_TIME_FOREVER); {
            invalidator = objc_getAssociatedObject(owner, &DMAutoInvalidatorAssociationKey);
            if (!invalidator) {
                invalidator = [[self alloc] init];
                objc_setAssociatedObject(owner, &DMAutoInvalidatorAssociationKey, invalidator, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        } dispatch_semaphore_signal(invalidatorAssociationMutex);
    }
    
    @synchronized (invalidator) {
        [invalidator->_observers addObject:observer];
    }
    
    // Add a non-retained reference from the observer back to the owner for explicit tear-down
    objc_setAssociatedObject(observer, &DMObserverOwnerAssociationKey, owner, OBJC_ASSOCIATION_ASSIGN);
}

+ (void)observerDidInvalidate:(id<DMAutoInvalidation>)observer;
{
    if (!observer)
        return;
    id owner = objc_getAssociatedObject(observer, &DMObserverOwnerAssociationKey);
    if (!owner)
        return;
    objc_setAssociatedObject(observer, &DMObserverOwnerAssociationKey, nil, OBJC_ASSOCIATION_ASSIGN);
    DMObserverInvalidator *invalidator = objc_getAssociatedObject(owner, &DMAutoInvalidatorAssociationKey);
    if (!invalidator)
        return; // If we're receiving this because the owner deallocated, its associations will already have been cleared by this point
    
    @synchronized (invalidator) {
        [invalidator->_observers removeObject:observer];
    }
}

@end
