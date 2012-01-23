//
//  DMAutoInvalidation.h
//  Library
//
//  Created by Jonathon Mah on 2012-01-21.
//  Copyright (c) 2012 Delicious Monster Software. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol DMAutoInvalidation;


@interface DMObserverInvalidator : NSObject
+ (void)attachObserver:(id<DMAutoInvalidation>)observer toOwner:(id)owner; // Calls -setInvalidator: on the observer
+ (void)observerDidInvalidate:(id<DMAutoInvalidation>)observer; // Observers must call this as part of their -invalidate
@end


@protocol DMAutoInvalidation <NSObject>
- (void)invalidate;
@end
