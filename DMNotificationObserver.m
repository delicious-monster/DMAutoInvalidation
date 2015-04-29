//
//  DMNotificationObserver.m
//  DMAutoInvalidation
//
//  Created by Jonathon Mah on 2011-07-11.
//  Copyright (c) 2011 Delicious Monster Software.
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

#import "DMNotificationObserver.h"

#import "DMAutoInvalidation.h"
#import "DMBlockUtilities.h"

#if !__has_feature(objc_arc)
#error This file must be compiled with Automatic Reference Counting (ARC).
#endif


@interface DMNotificationObserver () <DMAutoInvalidation>
@end


@implementation DMNotificationObserver {
    BOOL _invalidated;
    NSNotificationCenter *_notificationCenter;
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
    [_notificationCenter removeObserver:self name:_notificationName object:_unsafeNotificationSender];
    
    _actionBlock = nil;
    _notificationName = nil;
    _unsafeNotificationSender = nil;
    _unsafeOwner = nil;
    [DMObserverInvalidator observerDidInvalidate:self];
}


#pragma mark API

+ (NSArray *)observersForNames:(NSArray *)notificationNameArray object:(id)notificationSender attachedToOwner:(id)owner action:(DMNotificationActionBlock)actionBlock;
{
    NSMutableArray *observers = [NSMutableArray arrayWithCapacity:notificationNameArray.count];
    DMNotificationActionBlock sharedActionBlock = [actionBlock copy];
    for (NSString *name in notificationNameArray)
        [observers addObject:[self observerForName:name object:notificationSender attachedToOwner:owner action:sharedActionBlock]];
    return observers;
}

+ (instancetype)observerForName:(NSString *)notificationName object:(id)notificationSender attachedToOwner:(id)owner action:(DMNotificationActionBlock)actionBlock;
{
    return [[self alloc] initWithName:notificationName object:notificationSender attachedToOwner:owner action:actionBlock];
}

- (id)initWithName:(NSString *)notificationName object:(id)notificationSender attachedToOwner:(id)owner action:(DMNotificationActionBlock)actionBlock;
{
    return [self initWithName:notificationName object:notificationSender attachedToOwner:owner notificationCenter:[NSNotificationCenter defaultCenter] action:actionBlock];
}

- (id)initWithName:(NSString *)notificationName object:(id)notificationSender attachedToOwner:(id)owner notificationCenter:(NSNotificationCenter *)notificationCenter action:(DMNotificationActionBlock)actionBlock; // Designated initializer
{
    NSParameterAssert(owner && notificationCenter && actionBlock);
    if (!(self = [super init]))
        return nil;
    
    _unsafeOwner = owner;
    _notificationCenter = notificationCenter;
    _notificationName = [notificationName copy];
    _unsafeNotificationSender = notificationSender;
    _actionBlock = [actionBlock copy];
    
    [DMObserverInvalidator attachObserver:self toOwner:owner];

    [_notificationCenter addObserver:self selector:@selector(fireAction:) name:_notificationName object:notificationSender];
    
#ifndef NS_BLOCK_ASSERTIONS
    if ([DMBlockUtilities isObject:owner implicitlyRetainedByBlock:actionBlock])
        DMBlockRetainCycleDetected([NSString stringWithFormat:@"%s action captures owner; use localSelf (localOwner) parameter to fix.", __func__]);
#endif

    return self;
}

- (void)fireAction:(NSNotification *)notification;
{
    @synchronized (self) {
        if (_invalidated)
            return;
        
        // If our owner has deallocated, we should be invalidated at this point. Since we're not, our owner must still be alive.
        DMNotificationActionBlock actionBlock = [_actionBlock copy]; // Use a local reference, as the actionBock could call -invalidate on us
        actionBlock(notification, _unsafeOwner, self);
    }
}

@end
