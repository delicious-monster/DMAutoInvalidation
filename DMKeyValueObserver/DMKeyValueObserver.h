//
//  DMKeyValueObserver.h
//  DMAutoInvalidation
//
//  Created by Jonathon Mah on 2012-01-22.
//  Copyright (c) 2012 Delicious Monster Software.
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
- (id)initWithKeyPath:(NSString *)keyPath objects:(NSArray *)observationTargets attachedToOwner:(id)owner options:(NSKeyValueObservingOptions)options action:(DMKeyValueObserverBlock)actionBlock;

@property (readonly, nonatomic, unsafe_unretained) id changingObject; // only set during action block
@property (readonly, nonatomic, copy) NSString *keyPath;

- (void)fireActionWithObject:(id)object changeDictionary:(NSDictionary *)changeDict;
- (void)invalidate;

@end
