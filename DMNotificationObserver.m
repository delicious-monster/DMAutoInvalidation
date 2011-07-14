//
//  DMNotificationObserver.m
//  Library
//
//  Created by Jonathon Mah on 2011-07-11.
//  Copyright 2011 Delicious Monster Software. All rights reserved.
//

#import "DMNotificationObserver.h"

#import "DMCommonMacros.h"

#if !__has_feature(objc_arc)
#error This file must be compiled with Automatic Reference Counting (ARC).
#endif


static NSMutableSet *activeObservers;

@implementation DMNotificationObserver {
    BOOL _invalidated;
    NSString *_notificationName;
    DMNotificationActionBlock _actionBlock;
    
    BOOL _hasWeakOwner;
    id __weak _weakOwner; // Set if owner class allows weak references (_hasWeakOwner == YES)
    id __unsafe_unretained _unsafeOwner; // Always set
    Class _ownerClass;
    
    id __unsafe_unretained _unsafeNotificationSender;
}

#pragma mark NSObject

+ (void)initialize;
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        activeObservers = [NSMutableSet set];
    });
}

- (void)dealloc;
{
    [self invalidate];
}

- (NSString *)description;
{
    @synchronized (self) {
        if (_invalidated)
            return [NSString stringWithFormat:@"<%@ %p (invalidated)>", [self class], self];
        return [NSString stringWithFormat:@"<%@ %p observing: %@, owner: <%@ %p>>", [self class], self, _notificationName, [_unsafeOwner class], _unsafeOwner];
    }
}


#pragma mark API

+ (id)observerForName:(NSString *)notificationName object:(id)notificationSender owner:(id)owner action:(DMNotificationActionBlock)actionBlock;
{
    return [[self alloc] initWithName:notificationName object:notificationSender owner:owner action:actionBlock];
}

- (id)initWithName:(NSString *)notificationName object:(id)notificationSender owner:(id)owner action:(DMNotificationActionBlock)actionBlock;
{
    // Possible future: We might want to support a nil owner for global-type things
    NSParameterAssert(notificationName && owner && actionBlock);
    if (!(self = [super init]))
        return nil;
    
    BOOL ownerAllowsWeakReference = YES;
    NSSet *classesKnownToDenyWeakReferences = [NSSet setWithObjects:[NSWindowController class], [NSViewController class], [NSWindow class], nil];
    for (Class cls in classesKnownToDenyWeakReferences)
        if ([owner isKindOfClass:cls])
            ownerAllowsWeakReference = NO;
    
    _unsafeOwner = owner;
    if (ownerAllowsWeakReference) {
        _hasWeakOwner = YES;
        _weakOwner = owner;
    }
    _ownerClass = [owner class];
    _notificationName = [notificationName copy];
    _unsafeNotificationSender = notificationSender;
    _actionBlock = actionBlock;
    
    @synchronized (activeObservers) {
        [activeObservers addObject:self];
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(fireAction:) name:_notificationName object:notificationSender];
    
#ifndef NS_BLOCK_ASSERTIONS
    if (!_hasWeakOwner) {
        // Schedule sanity check for non-weak owners
        dispatch_async(dispatch_get_main_queue(), ^{
            /* If we can't weakly reference our owner, we'll have to be manually invalidated. That means our
             * owner must keep a reference to us. Assuming that reference is strong (which it should be), our
             * retainCount should be ≥ 3: the activeObservers set, this async block, and our owner's reference.
             * If it's < 3, it's very likely our owner doesn't have a reference to us and won't invalidate us
             * when it gets freed. */
            NSUInteger retainCount = [[self valueForKey:@"retainCount"] unsignedIntegerValue];
            if (retainCount < 3) {
                NSLog(@"Warning: %@ has an owner that doesn't support weak references. Its owner must -invalidate it when the owner is freed, but from the retainCount it appears the owner has no (strong) reference to this observer. This may lead to a crash when the notification fires.", self);
                DMDebugBreak();
            }
        });
    }
#endif
    
    return self;
}

- (void)fireAction:(NSNotification *)notification;
{
    @synchronized (self) {
        if (_invalidated)
            return;
        
        id strongOwner = nil;
        if (_hasWeakOwner)
            strongOwner = _weakOwner;
        else // Otherwise we have to assume the object is still there
            strongOwner = _unsafeOwner; // If we crash here, our owner should have invalidated us but failed to.
        
        if (!strongOwner)
            return [self invalidate]; // Our owning object has gone away
        
        // The above assignment did a msgSend of -retain, so we know we have something object-like in strongOwner.
        NSAssert1([strongOwner class] == _ownerClass, @"DMNotificationObserver saw a notification fire, but the owner has changed class. The original owner (an %@) was probably freed without it calling -invalidate on its observer, and another object was allocated in its place.", _ownerClass);
        
        _actionBlock(notification, strongOwner, self);
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
    
    _actionBlock = nil;
    _notificationName = nil;
    _unsafeNotificationSender = nil;
    _weakOwner = nil;
    _unsafeOwner = nil;
    
    @synchronized (activeObservers) {
        [activeObservers removeObject:self];
    }
}

@end
