//
//  DMKeyValueObserver.h
//  Library
//
//  Created by Jonathon Mah on 2012-01-22.
//  Copyright (c) 2012 Delicious Monster Software. All rights reserved.
//

#import <Foundation/Foundation.h>

@class DMKeyValueObserver;
typedef void(^DMKeyValueObserverBlock)(NSDictionary *changeDict, id localSelf, DMKeyValueObserver *observer);

/* #defines recognized in implementation:
 *
 * NS_BLOCK_ASSERTIONS
 *      Disables assertions
 *
 * DMKVO_INVALIDATE_ON_TARGET_DEALLOC
 *      Setting this to non-zero will invalidate the observer when the observation target deallocates, in addition to when the owner deallocates.
 *      This provides more safety than Foundation's key-value observing implementation, but costs performance.
 *      Default is 1 (enabled).
 *
 * DMKVO_LOG_ON_TARGET_DEALLOC
 *      If DMKVO_INVALIDATE_ON_TARGET_DEALLOC is enabled, this will log a message when the target of a non-invalidated observer deallocates.
 *      Messages will be logged where Foundation's key-value observing implementation would go in an unrecoverable error state (leaving dangling pointers).
 *      Default is 1 when assertions are enabled (via NS_BLOCK_ASSERTIONS); 0 otherwise.
 */


@interface DMKeyValueObserver : NSObject

+ (instancetype)observerWithKeyPath:(NSString *)keyPath object:(id)observationTarget attachedToOwner:(id)owner action:(DMKeyValueObserverBlock)actionBlock;
+ (instancetype)observerWithKeyPath:(NSString *)keyPath object:(id)observationTarget attachedToOwner:(id)owner options:(NSKeyValueObservingOptions)options action:(DMKeyValueObserverBlock)actionBlock;

- (id)init UNAVAILABLE_ATTRIBUTE;
- (id)initWithKeyPath:(NSString *)keyPath object:(id)observationTarget attachedToOwner:(id)owner options:(NSKeyValueObservingOptions)options action:(DMKeyValueObserverBlock)actionBlock;
@property (readonly, nonatomic, unsafe_unretained) id object; // observation target
@property (readonly, nonatomic, copy) NSString *keyPath;

- (void)fireAction:(NSDictionary *)changeDict;
- (void)invalidate;

@end
