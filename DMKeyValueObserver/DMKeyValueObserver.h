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
