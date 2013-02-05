//
//  DMKeyValueObserver.m
//  Library
//
//  Created by Jonathon Mah on 2012-01-22.
//  Copyright (c) 2012 Delicious Monster Software. All rights reserved.
//

#import "DMKeyValueObserver.h"

#import "DMAutoInvalidation.h"

#if __has_include("DMBlockUtilities.h")
#import "DMBlockUtilities.h"
#define HAVE_DMBLOCKUTILITIES 1
#endif

#if !__has_feature(objc_arc)
#error This file must be compiled with Automatic Reference Counting (ARC).
#endif

#if !defined(DMKVO_INVALIDATE_ON_TARGET_DEALLOC)
#define DMKVO_INVALIDATE_ON_TARGET_DEALLOC 1
#endif

#if !defined(DMKVO_LOG_ON_TARGET_DEALLOC)
#    if defined(NS_BLOCK_ASSERTIONS)
#    define DMKVO_LOG_ON_TARGET_DEALLOC 0
#    else
#    define DMKVO_LOG_ON_TARGET_DEALLOC 1
#    endif
#endif


/* Objects of this class are used to invalidate a key-value observer if the target object is deallocated while a
 * DMKeyValueObserver is observing it. NSObject's implementation raises an error here by default, but classes that
 * override it (such as NSArrayController) do NOT log an error -- instead, random corruption happens later. */
@interface DMKeyValueTargetObserver : NSObject <DMAutoInvalidation>
- (id)initWithKeyValueObserver:(DMKeyValueObserver *)keyValueObserver target:(id)target;
@end

@interface DMKeyValueObserver () <DMAutoInvalidation>
#pragma mark Protected: DMKeyValueTargetObserver support
- (void)targetWillDeallocate:(__unsafe_unretained id)deallocatingTarget;
@end


static char DMKeyValueObserverContext;

@implementation DMKeyValueObserver {
    BOOL _invalidated;

    NSHashTable *_targetsAsUnsafePointers;
    NSArray *_targetObservers;
    __unsafe_unretained id _unsafeOwner;
    DMKeyValueObserverBlock _actionBlock;
}

@synthesize changingObject = _changingObject;
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

    __unsafe_unretained id anyTarget = _targetsAsUnsafePointers.anyObject;
    NSString *targetString = [NSString stringWithFormat:@"<%@ %p>", ([anyTarget class] ? : @"(deallocated object)"), anyTarget];
    if (_targetsAsUnsafePointers.count > 1)
        targetString = [NSString stringWithFormat:@"%lu objects (including %@)", (unsigned long)_targetsAsUnsafePointers.count, targetString];
    return [NSString stringWithFormat:@"<%@ %p observing '%@' of %@, owner: <%@ %p>>", [self class], self, _keyPath, targetString, [_unsafeOwner class], _unsafeOwner];
}

- (id)init;
{ NSAssert(NO, @"Bad initializer; use -initWithKeyPath:objects:attachedToOwner:options:action:"); return nil; }

#pragma mark NSObject (NSKeyValueObserving)

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
    if (context == &DMKeyValueObserverContext)
        [self fireActionWithObject:object changeDictionary:change];
    else
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}


#pragma mark <DMAutoInvalidation>

- (void)invalidate;
{
    if (_invalidated)
        return;
    _invalidated = YES;

    /* We may be getting invalidated because our owner is deallocating.
     * If so, calling -allObjects on the NSHashTable will retain/autorelease the owner, and the deferred release will crash.
     * Wrap in our own pool so the -release is fired before the object is finished deallocating. */
    @autoreleasepool {
        for (DMKeyValueTargetObserver *targetObserver in _targetObservers)
            [targetObserver invalidate];
        _targetObservers = nil;

        NSArray *remainingObjects = _targetsAsUnsafePointers.allObjects;
        _targetsAsUnsafePointers = nil;
        [remainingObjects removeObserver:self fromObjectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:(NSRange){0, remainingObjects.count}] forKeyPath:_keyPath context:&DMKeyValueObserverContext];

        _keyPath = nil;
        _unsafeOwner = nil;
        _actionBlock = nil;
        [DMObserverInvalidator observerDidInvalidate:self];
    }
}


#pragma mark API

+ (instancetype)observerWithKeyPath:(NSString *)keyPath object:(id)observationTarget attachedToOwner:(id)owner action:(DMKeyValueObserverBlock)actionBlock;
{ return [self observerWithKeyPath:keyPath object:observationTarget attachedToOwner:owner options:0 action:actionBlock]; }
          
+ (instancetype)observerWithKeyPath:(NSString *)keyPath object:(id)observationTarget attachedToOwner:(id)owner options:(NSKeyValueObservingOptions)options action:(DMKeyValueObserverBlock)actionBlock;
{ return [[self alloc] initWithKeyPath:keyPath object:observationTarget attachedToOwner:owner options:options action:actionBlock]; }

- (id)initWithKeyPath:(NSString *)keyPath object:(id)observationTarget attachedToOwner:(id)owner options:(NSKeyValueObservingOptions)options action:(DMKeyValueObserverBlock)actionBlock;
{
    return [self initWithKeyPath:keyPath objects:@[observationTarget] attachedToOwner:owner options:options action:actionBlock];
}

- (id)initWithKeyPath:(NSString *)keyPath objects:(NSArray *)observationTargets attachedToOwner:(id)owner options:(NSKeyValueObservingOptions)options action:(DMKeyValueObserverBlock)actionBlock;
{
    // Possible future: We might want to support a nil owner for global-type things
    NSParameterAssert(keyPath && observationTargets.count && owner && actionBlock);
    if (!(self = [super init]))
        return nil;
    
    _keyPath = [keyPath copy];
    _actionBlock = [actionBlock copy];
    _unsafeOwner = owner;
    
    [DMObserverInvalidator attachObserver:self toOwner:owner];

    const NSUInteger targetCount = observationTargets.count;
    [observationTargets addObserver:self toObjectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:(NSRange){0, targetCount}] forKeyPath:keyPath options:options context:&DMKeyValueObserverContext];

    _targetsAsUnsafePointers = [[NSHashTable alloc] initWithOptions:(NSPointerFunctionsOpaqueMemory | NSPointerFunctionsObjectPointerPersonality) capacity:targetCount];
    for (id observationTarget in observationTargets)
        [_targetsAsUnsafePointers addObject:observationTarget];

#if HAVE_DMBLOCKUTILITIES && !defined(NS_BLOCK_ASSERTIONS)
    if ([DMBlockUtilities isObject:owner implicitlyRetainedByBlock:actionBlock])
        DMBlockRetainCycleDetected([NSString stringWithFormat:@"%s action captures owner; use localSelf (localOwner) parameter to fix.", __func__]);
#endif

#if DMKVO_INVALIDATE_ON_TARGET_DEALLOC || !defined(NS_BLOCK_ASSERTIONS)
    NSMutableArray *targetObservers = [NSMutableArray arrayWithCapacity:observationTargets.count];
    // Typical KVO rules say our clients should call -invalidate on us before the target deallocates. We'll watch the target so we can recover if they didn't.
    for (id observationTarget in observationTargets)
        if (observationTarget != owner)
            [targetObservers addObject:[[DMKeyValueTargetObserver alloc] initWithKeyValueObserver:self target:observationTarget]];
    if (targetObservers.count)
        _targetObservers = targetObservers;
#endif
    
    return self;
}

- (void)fireActionWithObject:(id)object changeDictionary:(NSDictionary *)changeDict;
{
    if (_invalidated)
        return;

    // If our owner has deallocated, we should be invalidated at this point. Since we're not, our owner must still be alive.
    DMKeyValueObserverBlock actionBlock = _actionBlock; // Use a local reference, as the actionBock could call -invalidate on us
    _changingObject = object;
    actionBlock(changeDict, _unsafeOwner, self);
    [actionBlock self]; // required for compiler to not optimize away retain/release
    _changingObject = nil;
}


#pragma mark Protected: DMKeyValueTargetObserver support

- (void)targetWillDeallocate:(__unsafe_unretained id)deallocatingTarget;
{
    if (_invalidated)
        return;

#if DMKVO_INVALIDATE_ON_TARGET_DEALLOC
    /* If you received this message, we are currently in a recoverable state. We have the opportunity
     * to unregister the observation before the target object deallocates too far. However, this is
     * ILLEGAL behavior with normal key-value observing, so you may want to avoid it if possible for
     * compatibility or general cleanliness. */
    [_targetsAsUnsafePointers removeObject:deallocatingTarget];
    [deallocatingTarget removeObserver:self forKeyPath:_keyPath context:&DMKeyValueObserverContext];

#    if DMKVO_LOG_ON_TARGET_DEALLOC
    NSLog(@"Note: Target <%@ %p> of active %@ is deallocating. The target will be unobserved now, with no change notification sent. Break on -targetWillDeallocate: to trace.", [deallocatingTarget class], deallocatingTarget, self);
    static BOOL printedSuppression;
    if (!printedSuppression)
        NSLog(@"(suppress log with NS_BLOCK_ASSERTIONS or DMKVO_LOG_ON_TARGET_DEALLOC)"), printedSuppression = 1;
#    endif
    BOOL trace = NO;
    if (trace) // Set this to YES in the debugger and step in to see the location of the observer in the source code. Note that this calls the block that otherwise would NOT be run.
        _actionBlock(nil, _unsafeOwner, self);

    if (!_targetsAsUnsafePointers.count)
        [self invalidate];
#else
    _invalidated = YES; // It's not safe to do proper invalidation anymore
    [NSException raise:NSGenericException format:@"Error: The target of %@ is deallocating. The observer should have been sent -invalidate before this point.", self];
#endif
}

@end


@implementation DMKeyValueTargetObserver {
    __unsafe_unretained DMKeyValueObserver *_unsafeKeyValueObserver;
    __unsafe_unretained id _unsafeTarget;
    BOOL _invalidated;
}

- (id)initWithKeyValueObserver:(DMKeyValueObserver *)keyValueObserver target:(id)target;
{
    NSParameterAssert(keyValueObserver && target);
    if (!(self = [super init]))
        return nil;
    _unsafeKeyValueObserver = keyValueObserver;
    _unsafeTarget = target;
    [DMObserverInvalidator attachObserver:self toOwner:target];
    return self;
}

- (void)invalidate;
{
    if (_invalidated)
        return;
    _invalidated = YES;
    [DMObserverInvalidator observerDidInvalidate:self];
    [_unsafeKeyValueObserver targetWillDeallocate:_unsafeTarget];
    _unsafeTarget = nil;
}

@end
