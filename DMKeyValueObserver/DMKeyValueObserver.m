//
//  DMKeyValueObserver.m
//  Library
//
//  Created by Jonathon Mah on 2012-01-22.
//  Copyright (c) 2012 Delicious Monster Software. All rights reserved.
//

#import "DMKeyValueObserver.h"

#import "DMBlockUtilities.h"

#if !__has_feature(objc_arc)
#error This file must be compiled with Automatic Reference Counting (ARC).
#endif


#define INVALIDATE_ON_TARGET_DEALLOC 1

#ifndef NS_BLOCK_ASSERTIONS
#define LOG_ON_TARGET_DEALLOC 1
#endif


/* Objects of this class are used to invalidate a key-value observer if the target object is deallocated while a
 * DMKeyValueObserver is observing it. NSObject's implementation raises an error here by default, but classes that
 * override it (such as NSArrayController) do NOT log an error -- instead, random corruption happens later. */
@interface DMKeyValueTargetObserver : NSObject <DMAutoInvalidation>
- (id)initWithKeyValueObserver:(DMKeyValueObserver *)keyValueObserver target:(id)target;
@end

@interface DMKeyValueObserver ()
#pragma mark Protected: DMKeyValueTargetObserver support
- (void)targetObserverDidInvalidate;
@end


static char DMKeyValueObserverContext;

@implementation DMKeyValueObserver {
    BOOL _invalidated;
    
    DMKeyValueTargetObserver *_targetObserver;
    __unsafe_unretained id _unsafeOwner;
    DMKeyValueObserverBlock _actionBlock;
}

@synthesize object = _unsafeTarget;
@synthesize keyPath = _keyPath;

#pragma mark NSObject

- (void)dealloc;
{
    [self invalidate];
}

- (NSString *)description;
{
    if (_invalidated)
        return [NSString stringWithFormat:@"<%@ %p (invalidated)>", [self class], self];
    return [NSString stringWithFormat:@"<%@ %p observing: <%@ %p>.%@, owner: <%@ %p>>", [self class], self, [_unsafeTarget class], _unsafeTarget, _keyPath, [_unsafeOwner class], _unsafeOwner];
}

- (id)init;
{ NSAssert(NO, @"Bad initializer; use -initWithKeyPath:object:attachedToOwner:options:action:"); return nil; }

#pragma mark NSObject (NSKeyValueObserving)

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
    if (context == &DMKeyValueObserverContext)
        [self fireAction:change];
    else
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}


#pragma mark <DMAutoInvalidation>

- (void)invalidate;
{
    if (_invalidated)
        return;
    _invalidated = YES;
    
    [_targetObserver invalidate];
    _targetObserver = nil;
    
    [_unsafeTarget removeObserver:self forKeyPath:_keyPath context:&DMKeyValueObserverContext];
    
    _unsafeTarget = nil;
    _keyPath = nil;
    _unsafeOwner = nil;
    _actionBlock = nil;
    [DMObserverInvalidator observerDidInvalidate:self];
}


#pragma mark API

+ (instancetype)observerWithKeyPath:(NSString *)keyPath object:(id)observationTarget attachedToOwner:(id)owner action:(DMKeyValueObserverBlock)actionBlock;
{ return [self observerWithKeyPath:keyPath object:observationTarget attachedToOwner:owner options:0 action:actionBlock]; }
          
+ (instancetype)observerWithKeyPath:(NSString *)keyPath object:(id)observationTarget attachedToOwner:(id)owner options:(NSKeyValueObservingOptions)options action:(DMKeyValueObserverBlock)actionBlock;
{ return [[self alloc] initWithKeyPath:keyPath object:observationTarget attachedToOwner:owner options:options action:actionBlock]; }

- (id)initWithKeyPath:(NSString *)keyPath object:(id)observationTarget attachedToOwner:(id)owner options:(NSKeyValueObservingOptions)options action:(DMKeyValueObserverBlock)actionBlock;
{
    // Possible future: We might want to support a nil owner for global-type things
    NSParameterAssert(owner && actionBlock);
    if (!(self = [super init]))
        return nil;
    
    _unsafeTarget = observationTarget;
    _keyPath = [keyPath copy];
    _actionBlock = [actionBlock copy];
    _unsafeOwner = owner;
    
    [DMObserverInvalidator attachObserver:self toOwner:owner];
    
    [observationTarget addObserver:self forKeyPath:keyPath options:options context:&DMKeyValueObserverContext];

#ifndef NS_BLOCK_ASSERTIONS
    if ([DMBlockUtilities isObject:owner implicitlyRetainedByBlock:actionBlock])
        DMBlockRetainCycleDetected([NSString stringWithFormat:@"%s action captures owner; use localSelf (localOwner) parameter to fix.", __func__]);
#endif

#if INVALIDATE_ON_TARGET_DEALLOC
    // Typical KVO rules say our clients should call -invalidate on us before the target deallocates. We'll watch the target so we can recover if they didn't.
    if (observationTarget != owner)
        _targetObserver = [[DMKeyValueTargetObserver alloc] initWithKeyValueObserver:self target:observationTarget];
#endif
    
    return self;
}

- (void)fireAction:(NSDictionary *)changeDict;
{
    if (_invalidated)
        return;
    
    // If our owner has deallocated, we should be invalidated at this point. Since we're not, our owner must still be alive.
    _actionBlock(changeDict, _unsafeOwner, self);
}


#pragma mark Protected: DMKeyValueTargetObserver support

- (void)targetObserverDidInvalidate;
{
    if (!_invalidated) {
#if INVALIDATE_ON_TARGET_DEALLOC
        /* If you received this message, we are currently in a recoverable state. We have the opportunity
         * to unregister the observation before the target object deallocates too far. However, this is
         * ILLEGAL behavior with normal key-value observing, so you may want to avoid it if possible for
         * compatibility or general cleanliness. */
#    if LOG_ON_TARGET_DEALLOC
        NSLog(@"Note: The target of active %@ is deallocating. The observer will be invalidated now, with no change notification sent. Break on -targetObserverDidInvalidate to trace.", self);
        static BOOL printedSuppression;
        if (!printedSuppression)
            NSLog(@"(suppress log with NS_BLOCK_ASSERTIONS or LOG_ON_TARGET_DEALLOC)"), printedSuppression = 1;
#    endif
        BOOL trace = NO;
        if (trace) // Set this to YES in the debugger and step in to see the location of the observer in the source code. Note that this calls the block that otherwise would NOT be run.
            _actionBlock(nil, _unsafeOwner, self);

        [self invalidate];
#else
        _invalidated = YES; // It's not safe to do proper invalidation anymore
        [NSException raise:NSGenericException format:@"Error: The target of %@ is deallocating. The observer should have been sent -invalidate before this point.", self];
#endif
    }
}

@end


@implementation DMKeyValueTargetObserver {
    __unsafe_unretained DMKeyValueObserver *_unsafeKeyValueObserver;
    BOOL _invalidated;
}

- (id)initWithKeyValueObserver:(DMKeyValueObserver *)keyValueObserver target:(id)target;
{
    NSParameterAssert(keyValueObserver && target);
    if (!(self = [super init]))
        return nil;
    _unsafeKeyValueObserver = keyValueObserver;
    [DMObserverInvalidator attachObserver:self toOwner:target];
    return self;
}

- (void)invalidate;
{
    if (_invalidated)
        return;
    _invalidated = YES;
    [DMObserverInvalidator observerDidInvalidate:self];
    [_unsafeKeyValueObserver targetObserverDidInvalidate];
}

@end
