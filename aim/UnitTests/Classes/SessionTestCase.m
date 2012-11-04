//
//  SessionTestCase.m
//  aim
//
//  Created by Santthosh on 11/3/12.
//  Copyright (c) 2012 appinmap.com. All rights reserved.
//

#import "SessionTestCase.h"
#import "AppInMap.h"

@implementation SessionTestCase

/*
 * {"platform":0,"name":"UnitTests iPhone","bundleId":"com.appinmap.ios.unittests","applicationId":"6ebfaf23-d739-4719-9c53-cba76351cba5","secret":"c433d362-5d5d-427f-8761-46fec92ac95b"}
 */

-(void)testSessions {
    [AppInMap startSession:@"11d35127-ae92-4743-8466-3df0598c156b" secret:@"0094cd31-8815-4ffa-8045-568d4a8ba79f"];
    
    [NSThread sleepForTimeInterval:180];
    
    [AppInMap endSession];
    
    [NSThread sleepForTimeInterval:10];
}

@end
