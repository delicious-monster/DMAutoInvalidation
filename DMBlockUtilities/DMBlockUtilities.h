//
//  DMBlockUtilities.h
//  DMBlockUtilities
//
//  Created by Jonathon Mah on 2012-06-07.
//  Copyright (c) 2012 Delicious Monster Software. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface DMBlockUtilities : NSObject

+ (BOOL)isObject:(id)object implicitlyRetainedByBlock:(id)block;

@end


extern void DMBlockRetainCycleDetected(NSString *msg); // Logs msg and stuff, provide a function to break on
