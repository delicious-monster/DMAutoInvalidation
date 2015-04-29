//
//  DMAutoInvalidation.h
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

#import <Foundation/Foundation.h>

@protocol DMAutoInvalidation;


@interface DMObserverInvalidator : NSObject
+ (void)attachObserver:(id<DMAutoInvalidation>)observer toOwner:(id)owner; // Calls -setInvalidator: on the observer
+ (void)observerDidInvalidate:(id<DMAutoInvalidation>)observer; // Observers must call this as part of their -invalidate
@end


@protocol DMAutoInvalidation <NSObject>
- (void)invalidate;
@end
