//
//  LIFilesystemEventObserver.h
//  Library
//
//  Created by William Shipley on 1/3/07.
//  Copyright 2007 Delicious Monster Software. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DMAutoInvalidation.h"

@class LIFilesystemEventObserver;
// Not all info is passed to block callback, just because no-one needs it (yet).
typedef void(^LIFilesystemEventActionBlock)(id localSelf, LIFilesystemEventObserver *observer); // ‘localSelf’ param is actually the owner, which is almost always used as ‘self’


@interface LIFilesystemEventObserver : NSObject <DMAutoInvalidation>

+ (instancetype)observerForDirectoryPaths:(NSArray *)paths attachedToOwner:(id)owner action:(LIFilesystemEventActionBlock)actionBlock __attribute__((nonnull(1,2,3)));

- (id)initWithDirectoryPaths:(NSArray *)paths attachedToOwner:(id)owner since:(FSEventStreamEventId)since latency:(NSTimeInterval)latency action:(LIFilesystemEventActionBlock)actionBlock __attribute__((nonnull(1,2,5)));

- (void)fireAction;
- (void)invalidate;

@end
