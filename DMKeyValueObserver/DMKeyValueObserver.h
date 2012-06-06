//
//  DMKeyValueObserver.h
//  Library
//
//  Created by Jonathon Mah on 2012-01-22.
//  Copyright (c) 2012 Delicious Monster Software. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DMAutoInvalidation.h" // <DMAutoInvalidation>


@class DMKeyValueObserver;
typedef void(^DMKeyValueObserverBlock)(NSDictionary *changeDict, id localSelf, DMKeyValueObserver *observer);
// TODO: Expose handy things, instead of raw changeDict?


@interface DMKeyValueObserver : NSObject <DMAutoInvalidation>

// TODO: Consider thread safety; target queue; etc.
+ (instancetype)observerWithKeyPath:(NSString *)keyPath object:(id)observationTarget attachedToOwner:(id)owner action:(DMKeyValueObserverBlock)actionBlock;
+ (instancetype)observerWithKeyPath:(NSString *)keyPath object:(id)observationTarget attachedToOwner:(id)owner options:(NSKeyValueObservingOptions)options action:(DMKeyValueObserverBlock)actionBlock;

- (id)init UNAVAILABLE_ATTRIBUTE;
- (id)initWithKeyPath:(NSString *)keyPath object:(id)observationTarget attachedToOwner:(id)owner options:(NSKeyValueObservingOptions)options action:(DMKeyValueObserverBlock)actionBlock;
@property (readonly, nonatomic, unsafe_unretained) id object; // observation target
@property (readonly, nonatomic, copy) NSString *keyPath;

- (void)fireAction:(NSDictionary *)changeDict;
- (void)invalidate;

@end
