//
//  DMManagedObjectObserver.m
//  DMAutoInvalidation
//
//  Created by Jonathon Mah on 2013-05-20.
//  Copyright (c) 2013 Delicious Monster Software.
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

#import "DMManagedObjectObserver.h"
// <dmclean.filter: lines.sort.uniq>
#import "DMSafeKVC.h"


static NSSet *flattenSubentities(NSEntityDescription *entity)
{
    // There's -[NSEntityDescription _collectSubentities], which is cached in NSEntityDescription._flattenedSubentities, but that's all private.
    NSMutableSet *const entities = [NSMutableSet new];
    [entities addObject:entity];
    for (NSEntityDescription *subentity in entity.subentities)
        [entities unionSet:flattenSubentities(subentity)];
    return entities;
}

static NSSet *relationshipAsSet(id relationshipValue)
{
    if (!relationshipValue)
        return [NSSet set];
    else if ([relationshipValue isKindOfClass:[NSSet class]])
        return relationshipValue;
    else if ([relationshipValue isKindOfClass:[NSOrderedSet class]])
        return ((NSOrderedSet *)relationshipValue).set;
    else
        return [NSSet setWithObject:relationshipValue]; // assume to-one
}


@implementation DMManagedObjectObserver
{
    NSEntityDescription *_baseEntity;
    NSDictionary *_entityNamesToModeledPropertyNamesAffectingKeyPaths;
    NSDictionary *_entityNamesToInverseRelationshipKeyPaths;
}


#pragma mark DMNotificationObserver

- (id)initWithName:(NSString *)notificationName object:(id)notificationSender attachedToOwner:(id)owner notificationCenter:(NSNotificationCenter *)notificationCenter action:(DMNotificationActionBlock)actionBlock; // Designated initializer
{
    if (!(self = [super initWithName:notificationName object:notificationSender attachedToOwner:owner notificationCenter:notificationCenter action:actionBlock]))
        return nil;
    return self;
}


#pragma mark API

- (id)initWithManagedObjectContext:(NSManagedObjectContext *)moc baseEntity:(NSEntityDescription *)baseEntity interestedKeyPaths:(NSSet *)keyPaths attachedToOwner:(id)owner action:(DMManagedObjectsDidChangeBlock)mocActionBlock;
{
    NSParameterAssert(moc && baseEntity && owner && mocActionBlock);
    DMNotificationActionBlock actionBlock = ^(NSNotification *notification, id localOwner, DMNotificationObserver *observer) {
        [(DMManagedObjectObserver *)observer _fireManagedObjectsDidChangeAction:mocActionBlock owner:localOwner notification:notification];
    };

    if (!(self = [self initWithName:NSManagedObjectContextObjectsDidChangeNotification object:moc attachedToOwner:owner notificationCenter:[NSNotificationCenter defaultCenter] action:actionBlock]))
        return nil;
    _baseEntity = baseEntity;
    _entityNamesToModeledPropertyNamesAffectingKeyPaths = [[self class] entityNamesToModeledPropertyNamesAffectingKeyPaths:keyPaths ofEntity:baseEntity];
    _entityNamesToInverseRelationshipKeyPaths = [[self class] entityNamesToInverseRelationshipKeyPathsAffectedByKeyPaths:keyPaths ofEntity:baseEntity];

    if (!_entityNamesToModeledPropertyNamesAffectingKeyPaths.count)
        return nil;

    [_entityNamesToInverseRelationshipKeyPaths enumerateKeysAndObjectsUsingBlock:^(NSString *entityName, id inverseKeyPathOrNull, BOOL *stop) {
        if ([inverseKeyPathOrNull isKindOfClass:[NSNull class]]) {
            NSLog(@"%s *** WARNING: No inverse relationship from entity %@ to %@, will not be able to notify about which %@ instances are affected by change in some of the given key paths: %@", __func__, entityName, _baseEntity.name, _baseEntity.name, keyPaths);
        }
    }];
    return self;
}

+ (NSDictionary *)entityNamesToModeledPropertyNamesAffectingKeyPaths:(NSSet *)modeledOrUnmodeledKeyPaths ofEntity:(NSEntityDescription *)baseEntity;
{
    NSMutableDictionary *const modeledPropertyNamesByEntityName = [NSMutableDictionary new];
    void (^accumulatePropertiesByEntityBlock)(NSPropertyDescription *, NSEntityDescription *) = ^(NSPropertyDescription *property, NSEntityDescription *entityOrSubentity) {
        NSMutableSet *mutableSet = modeledPropertyNamesByEntityName[entityOrSubentity.name];
        if (!mutableSet)
            mutableSet = modeledPropertyNamesByEntityName[entityOrSubentity.name] = [NSMutableSet new];
        [mutableSet addObject:property.name];
    };

    for (NSEntityDescription *entity in flattenSubentities(baseEntity))
        for (NSString *keyPath in modeledOrUnmodeledKeyPaths)
            [self _enumerateModeledPropertyNamesAffectingKeyPath:keyPath ofEntity:entity usingBlock:accumulatePropertiesByEntityBlock];

    // Share set instances when used for the same keys. Typically many sets are identical (particularly if entities have sub-entities) so this uses less memory; may make for better locality when processing notification. No proven reason.
    NSMutableSet *const keySets = [NSMutableSet new];
    // Use new dictionary, because stupidly they can't be mutated while enumerating
    NSMutableDictionary *const uniquedModeledPropertyNamesByEntityName = [NSMutableDictionary dictionaryWithCapacity:modeledPropertyNamesByEntityName.count];
    [modeledPropertyNamesByEntityName enumerateKeysAndObjectsUsingBlock:^(NSString *entityName, NSSet *modeledPropertyNames, BOOL *stop) {
        NSSet *uniquedSet = [keySets member:modeledPropertyNames];
        if (!uniquedSet)
            uniquedSet = [modeledPropertyNames copy], [keySets addObject:uniquedSet];
        uniquedModeledPropertyNamesByEntityName[entityName] = uniquedSet;
    }];

    return modeledPropertyNamesByEntityName;
}

+ (NSDictionary *)entityNamesToInverseRelationshipKeyPathsAffectedByKeyPaths:(NSSet *)modeledOrUnmodeledKeyPaths ofEntity:(NSEntityDescription *)baseEntity;
{
    // Resulting dictionary contains NSNull if some relationships are missing inverses, so traversal isn't possible
    NSMutableDictionary *const inverseRelationshipPathByEntityName = [NSMutableDictionary new];
    void (^accumulateInverseRelationshipByEntityBlock)(NSPropertyDescription *, NSEntityDescription *) = ^(NSPropertyDescription *property, NSEntityDescription *entityOrSubentity) {
        if (![property isKindOfClass:[NSRelationshipDescription class]])
            return;

        id inverseKeyPathOrNull = [NSNull null];
        NSRelationshipDescription *const relationship = (id)property;
        NSRelationshipDescription *const inverseRelationship = relationship.inverseRelationship;
        if (inverseRelationship) {
            inverseKeyPathOrNull = inverseRelationship.name;
            if (![entityOrSubentity isKindOfEntity:baseEntity]) {
                NSString *subsequentPathToBase = inverseRelationshipPathByEntityName[entityOrSubentity.name];
                if (![subsequentPathToBase isKindOfClass:[NSNull class]] && subsequentPathToBase.length)
                    inverseKeyPathOrNull = [inverseKeyPathOrNull stringByAppendingPathExtension:subsequentPathToBase];
            }
        }

        for (NSEntityDescription *destinationEntity in flattenSubentities(relationship.destinationEntity))
            inverseRelationshipPathByEntityName[destinationEntity.name] = inverseKeyPathOrNull;
    };

    for (NSEntityDescription *entity in flattenSubentities(baseEntity))
        for (NSString *keyPath in modeledOrUnmodeledKeyPaths)
            [self _enumerateModeledPropertyNamesAffectingKeyPath:keyPath ofEntity:entity usingBlock:accumulateInverseRelationshipByEntityBlock];

    return inverseRelationshipPathByEntityName;
}


#pragma mark Private

- (void)_fireManagedObjectsDidChangeAction:(DMManagedObjectsDidChangeBlock)mocActionBlock owner:(id)owner notification:(NSNotification *)objectsDidChangeNotification;
{
    NSParameterAssert([objectsDidChangeNotification.name isEqual:NSManagedObjectContextObjectsDidChangeNotification]);
    NSDictionary *const userInfo = objectsDidChangeNotification.userInfo;

    NSMutableSet *const affectedObjectsOfBaseEntity = [NSMutableSet new];
    BOOL someObjectsInvalidated = NO;

    if (userInfo[NSInvalidatedAllObjectsKey]) {
        someObjectsInvalidated = YES;
    } else {
        for (NSManagedObject *managedObject in userInfo[NSInvalidatedObjectsKey])
            if (_entityNamesToModeledPropertyNamesAffectingKeyPaths[managedObject.entity.name]) {
                someObjectsInvalidated = YES;
                break;
            }


        for (NSString *changeKey in @[NSUpdatedObjectsKey, NSRefreshedObjectsKey])
            for (NSManagedObject *changedObject in userInfo[changeKey]) {
                NSSet *const modeledPropertyNames = _entityNamesToModeledPropertyNamesAffectingKeyPaths[changedObject.entity.name];
                if (!modeledPropertyNames)
                    continue;

                if (changeKey == NSUpdatedObjectsKey) { // treat all refreshed objects as changeed.
                    BOOL keyChangedAffectingBaseEntity = NO;
                    for (NSString *changedKey in changedObject.changedValuesForCurrentEvent)
                        if ([modeledPropertyNames containsObject:changedKey]) {
                            keyChangedAffectingBaseEntity = YES;
                            break;
                        }

                    if (!keyChangedAffectingBaseEntity)
                        continue;
                }

                if ([changedObject.entity isKindOfEntity:_baseEntity]) {
                    [affectedObjectsOfBaseEntity addObject:changedObject];
                } else {
                    NSString *const inverseKeyPath = _entityNamesToInverseRelationshipKeyPaths[changedObject.entity.name];
                    [affectedObjectsOfBaseEntity unionSet:[[self class] setByTraversingRelationshipKeyPath:inverseKeyPath ofManagedObject:changedObject]];
                }
            }

        for (NSString *changeKey in @[NSInsertedObjectsKey, NSDeletedObjectsKey])
            for (NSManagedObject *changedObject in userInfo[changeKey])
                if ([changedObject.entity isKindOfEntity:_baseEntity])
                    [affectedObjectsOfBaseEntity addObject:changedObject];
    }

    mocActionBlock(someObjectsInvalidated, affectedObjectsOfBaseEntity, objectsDidChangeNotification, owner, self);
}

+ (void)_enumerateModeledPropertyNamesAffectingKeyPath:(NSString *)modeledOrUnmodeledKeyPath ofEntity:(NSEntityDescription *)entity usingBlock:(void (^)(NSPropertyDescription *, NSEntityDescription *))block;
{
    NSString *remainingKeyPath;
    NSString *const firstKey = DMSplitKeyPath(modeledOrUnmodeledKeyPath, &remainingKeyPath);

    NSPropertyDescription *const modeledProperty = entity.propertiesByName[firstKey];
    if (!modeledProperty) {
        const Class managedObjectClass = NSClassFromString(entity.managedObjectClassName);
        for (NSString *dependentKeyPath in [managedObjectClass keyPathsForValuesAffectingValueForKey:firstKey]) {
            /* Add the remaining key path onto the dependent key. This may not be how the dependent key is actually used,
             * but unknown keys are ignored by +keyPathsForValuesAffectingValueForKey: so we can be more promiscuous.
             * For example, a case where it's appropriate is observing "primarySynopsis.string", where -primarySynopsis
             * returns { self.userSynopsis ? : self.amazonSynopses.firstObject } (synopsis being a managed object), thus
             * depending on K(userSynopsis) and K(amazonSynopses), then _also_ on K(string) of Synopsis. */
            NSString *const dependentKeyPathWithSuffix = remainingKeyPath.length ? [dependentKeyPath stringByAppendingPathExtension:remainingKeyPath] : dependentKeyPath;
            [self _enumerateModeledPropertyNamesAffectingKeyPath:dependentKeyPathWithSuffix ofEntity:entity usingBlock:block];
        }

    } else {
        // Key is a modeled property (attribute or relationship)
        block(modeledProperty, entity);

        if (remainingKeyPath.length) {
            if ([modeledProperty isKindOfClass:[NSRelationshipDescription class]]) {
                NSRelationshipDescription *const relationship = (id)modeledProperty;
                for (NSEntityDescription *destinationEntity in flattenSubentities(relationship.destinationEntity))
                    [self _enumerateModeledPropertyNamesAffectingKeyPath:remainingKeyPath ofEntity:destinationEntity usingBlock:block];

            } else {
                // Ignore remaining key path of non-relationship (e.g. an NSDictionary); that won't post an ObjectsDidChangeNotification anyway.
                //NSLog(@"%s ignoring remaining key path '%@' of attribute %@.%@", __func__, remainingKeyPath, entity.name, modeledProperty.name);
            }
        }
    }
}

+ (NSSet *)setByTraversingRelationshipKeyPath:(NSString *)keyPath ofManagedObject:(NSManagedObject *)managedObject;
{
    NSString *remainingKeyPath;
    NSString *const firstKey = DMSplitKeyPath(keyPath, &remainingKeyPath);

    NSSet *const relationshipSet = relationshipAsSet([managedObject valueForKey:firstKey]);
    if (remainingKeyPath) {
        NSMutableSet *const objects = [NSMutableSet new];
        for (NSManagedObject *relatedManagedObject in relationshipSet)
            [objects unionSet:[self setByTraversingRelationshipKeyPath:remainingKeyPath ofManagedObject:relatedManagedObject]];
        return objects;
    } else
        return relationshipSet;
}

@end
