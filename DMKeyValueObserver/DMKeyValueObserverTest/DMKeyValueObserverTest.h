//
//  DMKeyValueObserverTest.h
//  DMKeyValueObserverTest
//
//  Created by Jonathon Mah on 2012-01-22.
//  Copyright 2012 Delicious Monster Software. All rights reserved.
//

#import <SenTestingKit/SenTestingKit.h>


@interface DMKeyValueObserverTest : SenTestCase

- (void)testOwnerTearDown;
- (void)testPrematureTargetDeallocation;
- (void)testSelfObservation;

@end
