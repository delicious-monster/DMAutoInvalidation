//
//  DMAutoInvalidation.m
//  DMAutoInvalidation
//
//  Created by Jonathon Mah on 2012-01-21.
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

#import "DMAutoInvalidation.h"

#import <objc/message.h>

#if !__has_feature(objc_arc)
#error This file must be compiled with Automatic Reference Counting (ARC).
#endif


static char DMAutoInvalidatorAssociationKey, DMObserverOwnerAssociationKey;

@implementation DMObserverInvalidator {
    NSMutableSet *_observers;
}

#pragma mark NSObject

- (void)dealloc;
{
    // Take a local copy of this, since observers could remove themselves from this set when invalidated (mutating it while we're enumerating)
    NSSet *observersToInvalidate = _observers;
    _observers = nil;
    for (id<DMAutoInvalidation> observer in observersToInvalidate)
        [observer invalidate];
}

- (id)init;
{
    if (!(self = [super init]))
        return nil;
    _observers = [NSMutableSet set];
    return self;
}


#pragma mark API

+ (void)attachObserver:(id<DMAutoInvalidation>)observer toOwner:(id)owner;
{
    NSParameterAssert(observer && owner);
    static dispatch_once_t onceToken;
    static dispatch_semaphore_t invalidatorAssociationMutex;
    static NSMutableSet *classesWithEarlyInvalidateOnDealloc;
    static dispatch_semaphore_t earlyInvalidateMutex;
    dispatch_once(&onceToken, ^{
        invalidatorAssociationMutex = dispatch_semaphore_create(1);
        classesWithEarlyInvalidateOnDealloc = [NSMutableSet set];
        earlyInvalidateMutex = dispatch_semaphore_create(1);
    });

    // Tie the observer to the owner
    DMObserverInvalidator *invalidator = objc_getAssociatedObject(owner, &DMAutoInvalidatorAssociationKey);
    if (!invalidator) {
        // Protect against a race creating the associated set. Don't @synchronize on the owner, because someone else could be doing that and we'll deadlock.
        dispatch_semaphore_wait(invalidatorAssociationMutex, DISPATCH_TIME_FOREVER); {
            invalidator = objc_getAssociatedObject(owner, &DMAutoInvalidatorAssociationKey);
            if (!invalidator) {
                invalidator = [[self alloc] init];
                objc_setAssociatedObject(owner, &DMAutoInvalidatorAssociationKey, invalidator, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        } dispatch_semaphore_signal(invalidatorAssociationMutex);
    }
    
    @synchronized (invalidator) {
        [invalidator->_observers addObject:observer];
    }
    
    // Add a non-retained reference from the observer back to the owner for explicit tear-down
    objc_setAssociatedObject(observer, &DMObserverOwnerAssociationKey, owner, OBJC_ASSOCIATION_ASSIGN);

    // Set up the owner's class to invalidate its observers before its own dealloc code runs
    Class ownerClass = [owner class];
    dispatch_semaphore_wait(invalidatorAssociationMutex, DISPATCH_TIME_FOREVER);
    if (![classesWithEarlyInvalidateOnDealloc containsObject:ownerClass]) {
        [self addEarlyInvalidateOnDeallocToClass:ownerClass];
        [classesWithEarlyInvalidateOnDealloc addObject:ownerClass];
    }
    dispatch_semaphore_signal(invalidatorAssociationMutex);
}

+ (void)observerDidInvalidate:(id<DMAutoInvalidation>)observer;
{
    if (!observer)
        return;
    id owner = objc_getAssociatedObject(observer, &DMObserverOwnerAssociationKey);
    if (!owner)
        return;
    objc_setAssociatedObject(observer, &DMObserverOwnerAssociationKey, nil, OBJC_ASSOCIATION_ASSIGN);
    DMObserverInvalidator *invalidator = objc_getAssociatedObject(owner, &DMAutoInvalidatorAssociationKey);
    if (!invalidator)
        return; // If we're receiving this because the owner deallocated, its associations will already have been cleared by this point
    
    @synchronized (invalidator) {
        [invalidator->_observers removeObject:observer];
    }
}


#pragma mark Private

// objc headers in 10.7 aren't properly compatible with ARC, grr. (10.8 is fine.)
#if (MAC_OS_X_VERSION_10_7 >= MAC_OS_X_VERSION_MAX_ALLOWED)

IMP (*imp_implementationWithBlock_ARCFIXED)(id block) = (void *)imp_implementationWithBlock;
#define imp_implementationWithBlock  (*imp_implementationWithBlock_ARCFIXED)

struct objc_super_ARCFIXED {
    __unsafe_unretained id receiver;
    __unsafe_unretained Class super_class;
};
#define objc_super  objc_super_ARCFIXED

#endif


+ (BOOL)addEarlyInvalidateOnDeallocToClass:(Class)targetClass;
{
    const SEL deallocSel = NSSelectorFromString(@"dealloc"); // ARC forbids @selector(dealloc)
    const char *deallocTypes = "v@:";

    Method originalDealloc = NULL;
    {
        // class_copyMethodList() returns only methods defined by this class; class_getInstanceMethod() looks at superclasses too, which isn't what we want.
        Method *const instanceMethods = class_copyMethodList(targetClass, NULL);
        if (instanceMethods)
            for (NSUInteger i = 0; !originalDealloc && instanceMethods[i]; i++)
                if (method_getName(instanceMethods[i]) == deallocSel)
                    originalDealloc = instanceMethods[i];
        free(instanceMethods);
    }

    // Test disabled; NSObject's implementation is reported with sizes, like "v16@0:8' (on 64-bit). I don't know how to check these for equivalence.
    //if (originalDealloc && strcmp(deallocTypes, method_getTypeEncoding(originalDealloc)) != 0)
        //return NSLog(@"%s dealloc method of class %s has unexpected type %s (expected %s)", __func__, class_getName(targetClass), method_getTypeEncoding(originalDealloc), deallocTypes), NO;

    // Captured variables
    IMP originalDeallocIMP = (originalDealloc ? method_getImplementation(originalDealloc) : NULL);
    Class capturedSuperclass = [targetClass superclass]; // Nil for root class
    if (!originalDeallocIMP && !capturedSuperclass)
        return NSLog(@"%s unable to proceed; class %s has neither a -dealloc nor a superclass", __func__, class_getName(targetClass)), NO;

    // Build the block
    IMP earlyNotifyDeallocIMP = imp_implementationWithBlock(^(__unsafe_unretained id receiver) {
        // ---- This is the replacement -dealloc call. It must continue the deallocation by calling the original -dealloc implementation, or super if there was none ----
#if 0
        NSLog(@"DMAutoInvalidation early-invalidate dealloc for <%@ %p> at level %s (will call %@)", [receiver class], receiver, class_getName(targetClass), originalDeallocIMP ? @"own dealloc" : @"super");
#endif
        // We can run this multiple times per object (once per class to which we've added early-notify dealloc) so it must be idempotent.
        // Shouldn't need to lock; this is during -dealloc, so no-one else should be touching the receiver.
        objc_setAssociatedObject(receiver, &DMAutoInvalidatorAssociationKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); // Cause the invalidator instance (if any) to be released

        // Proceed with dealloc
        if (originalDeallocIMP) {
            void (*void_origDealloc)(id, SEL) = (void *)originalDeallocIMP;
            void_origDealloc(receiver, deallocSel);
        } else {
            void (*void_msgSendSuper)(struct objc_super *, SEL) = (void *)objc_msgSendSuper;
            void_msgSendSuper(&(struct objc_super){receiver, capturedSuperclass}, deallocSel);
        }
    });

    if (!earlyNotifyDeallocIMP)
        return NSLog(@"%s failed to create trampoline for dealloc block", __func__), NO;

    // Add or replace the IMP
    if (originalDealloc)
        return method_setImplementation(originalDealloc, earlyNotifyDeallocIMP), YES;
    else
        return class_addMethod(targetClass, deallocSel, earlyNotifyDeallocIMP, deallocTypes);
}

@end
