//
//  DMKeyValueObserver.m
//  Library
//
//  Created by Jonathon Mah on 2012-01-22.
//  Copyright (c) 2012 Delicious Monster Software. All rights reserved.
//

#import "DMKeyValueObserver.h"


#if !__has_feature(objc_arc)
#error This file must be compiled with Automatic Reference Counting (ARC).
#endif


/* Objects of this class are only used to throw an error if the target object is deallocated while a
 * DMKeyValueObserver is observing it. NSObject's implementation does this by default, but classes that
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
{ NSAssert(NO, @"Bad initializer; use -initWithKeyPath:object:owner:options:action:"); return nil; }

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

+ (instancetype)observerWithKeyPath:(NSString *)keyPath object:(id)observationTarget owner:(id)owner action:(DMKeyValueObserverBlock)actionBlock;
{ return [self observerWithKeyPath:keyPath object:observationTarget owner:owner options:0 action:actionBlock]; }
          
+ (instancetype)observerWithKeyPath:(NSString *)keyPath object:(id)observationTarget owner:(id)owner options:(NSKeyValueObservingOptions)options action:(DMKeyValueObserverBlock)actionBlock;
{ return [[self alloc] initWithKeyPath:keyPath object:observationTarget owner:owner options:options action:actionBlock]; }

- (id)initWithKeyPath:(NSString *)keyPath object:(id)observationTarget owner:(id)owner options:(NSKeyValueObservingOptions)options action:(DMKeyValueObserverBlock)actionBlock;
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
    // Our clients should call -invalidate on us before the target deallocates. We'll watch the target so we can complain if they didn't.
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
        // This is programmer error! It's no longer safe to call -removeObserver:forKeyPath:context: on our target, so we can't be torn down. Unfortunately it's not possible to recover cleanly from this state.
        [NSException raise:NSGenericException format:@"Error: The target of %@ is deallocating. The observer should have been sent -invalidate before this point.", self];
        _invalidated = YES; // It's not safe to do proper invalidation anymore
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
