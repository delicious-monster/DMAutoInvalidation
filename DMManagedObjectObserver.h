//
//  DMManagedObjectObserver.h
//  Library
//
//  Created by Jonathon Mah on 2013-05-20.
//  Copyright (c) 2013 Delicious Monster Software. All rights reserved.
//

#import "DMNotificationObserver.h"
#import <CoreData/CoreData.h>


/* The action block is passed the notification, the owner as a parameter (to avoid retain cycles),
 * and the triggering observer (so it can easily invalidate it if it needs to). */
@class DMManagedObjectObserver;
typedef void(^DMManagedObjectsDidChangeBlock)(BOOL someObjectsInvalidated, NSSet *affectedObjectsOfBaseEntity, NSNotification *notification, id localSelf, DMManagedObjectObserver *observer); // ‘localSelf’ param is actually the owner, which is almost always used as ‘self’


@interface DMManagedObjectObserver : DMNotificationObserver

- (id)initWithManagedObjectContext:(NSManagedObjectContext *)moc
                        baseEntity:(NSEntityDescription *)baseEntity
                interestedKeyPaths:(NSSet *)keyPaths
                   attachedToOwner:(id)owner
                            action:(DMManagedObjectsDidChangeBlock)mocActionBlock
                                   __attribute__((nonnull(1,2,4,5))); // Designated initializer

@property (readonly, nonatomic, retain) NSEntityDescription *baseEntity;

+ (NSDictionary *)entityNamesToModeledPropertyNamesAffectingKeyPaths:(NSSet *)modeledOrUnmodeledKeyPaths ofEntity:(NSEntityDescription *)baseEntity;
+ (NSDictionary *)entityNamesToInverseRelationshipKeyPathsAffectedByKeyPaths:(NSSet *)modeledOrUnmodeledKeyPaths ofEntity:(NSEntityDescription *)baseEntity;

@end
