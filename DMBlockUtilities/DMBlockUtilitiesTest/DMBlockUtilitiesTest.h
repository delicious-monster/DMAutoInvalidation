//
//  DMBlockUtilitiesTest.h
//  DMBlockUtilitiesTest
//
//  Created by Jonathon Mah on 2012-06-07.
//  Copyright (c) 2012 Delicious Monster Software. All rights reserved.
//

#import <SenTestingKit/SenTestingKit.h>


@interface DMBlockUtilitiesTest : SenTestCase

- (void)testStrongBlockObjectCapture;
- (void)testBlockIvarCapturesSelf;
- (void)testByReferenceCapture;
- (void)testPointerAndNonWordCapture;

@end
