//
//  LIFilesystemEventObserver.m
//  DMAutoInvalidation
//
//  Created by William Shipley on 2007-01-03.
//  Copyright (c) 2007 Delicious Monster Software.
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

#import "LIFilesystemEventObserver.h"
// <dmclean.filter: lines.sort.uniq>
#import "DMBlockUtilities.h"


static void callback(ConstFSEventStreamRef streamRef, void *clientCallbackInfo, size_t numEvents, void *eventPaths, const FSEventStreamEventFlags eventFlags[], const FSEventStreamEventId eventIds[])
{
    LIFilesystemEventObserver *observer = (__bridge id)clientCallbackInfo;
    [observer fireAction];
}


@implementation LIFilesystemEventObserver {
    BOOL _invalidated;
    FSEventStreamRef _eventStreamRef;
    LIFilesystemEventActionBlock _actionBlock;
    __unsafe_unretained id _unsafeOwner;
}

#pragma mark NSObject

- (void)dealloc;
{
    [self invalidate];
}


#pragma mark <DMAutoInvalidation>

- (void)invalidate;
{
    if (_invalidated)
        return;
    _invalidated = YES;
    
    FSEventStreamStop(_eventStreamRef);
    FSEventStreamInvalidate(_eventStreamRef);
    FSEventStreamRelease(_eventStreamRef);
    _eventStreamRef = NULL;
    
    _actionBlock = nil;
    _unsafeOwner = nil;
    [DMObserverInvalidator observerDidInvalidate:self];
}


#pragma mark API

+ (instancetype)observerForDirectoryPaths:(NSArray *)paths attachedToOwner:(id)owner action:(LIFilesystemEventActionBlock)actionBlock;
{
#define DEFAULT_LATENCY (2.0)
    return [[self alloc] initWithDirectoryPaths:paths attachedToOwner:owner since:kFSEventStreamEventIdSinceNow latency:DEFAULT_LATENCY action:actionBlock];
}

- (id)initWithDirectoryPaths:(NSArray *)paths attachedToOwner:(id)owner since:(FSEventStreamEventId)since latency:(NSTimeInterval)latency action:(LIFilesystemEventActionBlock)actionBlock;
{
    NSParameterAssert(paths && owner && actionBlock);
    if (!(self = [super init]))
        return nil;
    
    _unsafeOwner = owner;
    _actionBlock = [actionBlock copy];
    
    FSEventStreamContext filesystemEventStreamContext = {.version = 0, .info = (__bridge void *)self};
    _eventStreamRef = FSEventStreamCreate(kCFAllocatorDefault, callback, &filesystemEventStreamContext, (__bridge CFArrayRef)paths, since, latency, kFSEventStreamCreateFlagNone);
    
    FSEventStreamScheduleWithRunLoop(_eventStreamRef, [[NSRunLoop mainRunLoop] getCFRunLoop], kCFRunLoopDefaultMode);
    if (!FSEventStreamStart(_eventStreamRef))
        return nil;
    
    [DMObserverInvalidator attachObserver:self toOwner:owner];

#ifndef NS_BLOCK_ASSERTIONS
    if ([DMBlockUtilities isObject:owner implicitlyRetainedByBlock:actionBlock])
        DMBlockRetainCycleDetected([NSString stringWithFormat:@"%s action captures owner; use localSelf (localOwner) parameter to fix.", __func__]);
#endif
    return self;
}

- (void)fireAction;
{
    if (_invalidated)
        return;
    
    // If our owner has deallocated, we should be invalidated at this point. Since we're not, our owner must still be alive.
    LIFilesystemEventActionBlock actionBlock = [_actionBlock copy]; // Use a local reference, as the actionBock could call -invalidate on us
    actionBlock(_unsafeOwner, self);
}

@end
