//
//  DMNotificationObserver.h
//  Library
//
//  Created by Jonathon Mah on 2011-07-11.
//  Copyright 2011 Delicious Monster Software. All rights reserved.
//

#import <Foundation/Foundation.h>


/* The action block is passed the notification, the owner as a parameter (to avoid retain cycles),
 * and the triggering observer (so it can easiliy invalidate it if it needs to). */
@class DMNotificationObserver;
typedef void(^DMNotificationActionBlock)(NSNotification *notification, id localOwner, DMNotificationObserver *observer);


@interface DMNotificationObserver : NSObject

+ (id)observerForName:(NSString *)notificationName
               object:(id)notificationSender
                owner:(id)owner
               action:(DMNotificationActionBlock)actionBlock
                      __attribute__((__nonnull__(1,3,4)));

- (id)initWithName:(NSString *)notificationName
            object:(id)notificationSender
             owner:(id)owner
            action:(DMNotificationActionBlock)actionBlock
                   __attribute__((__nonnull__(1,3,4)));

- (void)fireAction:(NSNotification *)notification;
- (void)invalidate;

@end
