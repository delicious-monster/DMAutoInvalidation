//
//  DMNotificationObserver.m
//  Library
//
//  Created by Jonathon Mah on 2011-07-11.
//  Copyright 2011 Delicious Monster Software. All rights reserved.
//

#import "DMNotificationObserver.h"

#import <objc/runtime.h>

#if !__has_feature(objc_arc)
#error This file must be compiled with Automatic Reference Counting (ARC).
#endif


static char DMNotificationInvalidatorAssociationKey;

@interface DMObserverInvalidator : NSObject
@property (nonatomic, retain) NSMutableSet *observers;
@end


@implementation DMNotificationObserver {
    BOOL _invalidated;
    NSString *_notificationName;
    __unsafe_unretained id _unsafeNotificationSender;
    DMNotificationActionBlock _actionBlock;
    
    Class _ownerClass;
    
    @package
    __unsafe_unretained id _unsafeOwner;
}

#pragma mark NSObject

- (void)dealloc;
{
    [self invalidate];
}

- (NSString *)description;
{
    @synchronized (self) {
        if (_invalidated)
            return [NSString stringWithFormat:@"<%@ %p (invalidated)>", [self class], self];
        return [NSString stringWithFormat:@"<%@ %p observing: %@, owner: <%@ %p>>", [self class], self, _notificationName ? : @"(all)", _ownerClass, _unsafeOwner];
    }
}


#pragma mark API

+ (instancetype)observerForName:(NSString *)notificationName object:(id)notificationSender owner:(id)owner action:(DMNotificationActionBlock)actionBlock;
{
    return [[self alloc] initWithName:notificationName object:notificationSender owner:owner action:actionBlock];
}

- (id)initWithName:(NSString *)notificationName object:(id)notificationSender owner:(id)owner action:(DMNotificationActionBlock)actionBlock;
{
    // Possible future: We might want to support a nil owner for global-type things
    NSParameterAssert(owner && actionBlock);
    if (!(self = [super init]))
        return nil;
    
    _unsafeOwner = owner;
    _ownerClass = [owner class];
    _notificationName = [notificationName copy];
    _unsafeNotificationSender = notificationSender;
    _actionBlock = actionBlock;
    
    static dispatch_once_t onceToken;
    static dispatch_semaphore_t invalidatorAssociationMutex;
    dispatch_once(&onceToken, ^{
        invalidatorAssociationMutex = dispatch_semaphore_create(1);
    });
    
    // Tie the observer to the owner
    DMObserverInvalidator *invalidator = objc_getAssociatedObject(owner, &DMNotificationInvalidatorAssociationKey);
    if (!invalidator) {
        // Protect against a race creating the associated set. Don't @synchronize on the owner, because someone else could be doing that and we'll deadlock.
        dispatch_semaphore_wait(invalidatorAssociationMutex, DISPATCH_TIME_FOREVER); {
            invalidator = objc_getAssociatedObject(owner, &DMNotificationInvalidatorAssociationKey);
            if (!invalidator) {
                invalidator = [[DMObserverInvalidator alloc] init];
                objc_setAssociatedObject(owner, &DMNotificationInvalidatorAssociationKey, invalidator, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        } dispatch_semaphore_signal(invalidatorAssociationMutex);
    }
    
    @synchronized (invalidator) {
        [invalidator.observers addObject:self];
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(fireAction:) name:_notificationName object:notificationSender];
    
    return self;
}

- (void)fireAction:(NSNotification *)notification;
{
    @synchronized (self) {
        if (_invalidated)
            return;
        
        // If our owner has deallocated, we should be invalidated at this point. Since we're not, our owner must still be alive.
        _actionBlock(notification, _unsafeOwner, self);
    }
}

- (void)invalidate;
{
    @synchronized (self) {
        if (_invalidated)
            return;
        _invalidated = YES;
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self name:_notificationName object:_unsafeNotificationSender];
    
    id strongOwner = _unsafeOwner;
    if (strongOwner) {
        DMObserverInvalidator *invalidator = objc_getAssociatedObject(strongOwner, &DMNotificationInvalidatorAssociationKey);
        @synchronized (invalidator) {
            [invalidator.observers removeObject:self];
        }
    }
    
    _actionBlock = nil;
    _notificationName = nil;
    _unsafeNotificationSender = nil;
    _unsafeOwner = nil;
}

@end


@implementation DMObserverInvalidator

@synthesize observers = _observers;

- (id)init;
{
    if (!(self = [super init]))
        return nil;
    _observers = [NSMutableSet set];
    return self;
}

- (void)dealloc;
{
    for (DMNotificationObserver *observer in self.observers) {
        // Our owner is in the process of deallocating. If the owner is touched such that it gets autoreleased, it will enter the pool as a zombie. Clear this out to ensure it's not.
        observer->_unsafeOwner = nil;
        [observer invalidate];
    }
}

@end
