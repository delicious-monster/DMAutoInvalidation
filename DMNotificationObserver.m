//
//  DMNotificationObserver.m
//  Library
//
//  Created by Jonathon Mah on 2011-07-11.
//  Copyright 2011 Delicious Monster Software. All rights reserved.
//

#import "DMNotificationObserver.h"


#if !__has_feature(objc_arc)
#error This file must be compiled with Automatic Reference Counting (ARC).
#endif


@implementation DMNotificationObserver {
    BOOL _invalidated;
    NSString *_notificationName;
    __unsafe_unretained id _unsafeNotificationSender;
    DMNotificationActionBlock _actionBlock;
    
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
        return [NSString stringWithFormat:@"<%@ %p observing: %@, owner: <%@ %p>>", [self class], self, _notificationName ? : @"(all)", [_unsafeOwner class], _unsafeOwner];
    }
}


#pragma mark <DMAutoInvalidation>

- (void)invalidate;
{
    @synchronized (self) {
        if (_invalidated)
            return;
        _invalidated = YES;
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self name:_notificationName object:_unsafeNotificationSender];
    
    _actionBlock = nil;
    _notificationName = nil;
    _unsafeNotificationSender = nil;
    _unsafeOwner = nil;
    [DMObserverInvalidator observerDidInvalidate:self];
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
    _notificationName = [notificationName copy];
    _unsafeNotificationSender = notificationSender;
    _actionBlock = [actionBlock copy];
    
    [DMObserverInvalidator attachObserver:self toOwner:owner];
    
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

@end
