//
//  AIMDevice.h
//  aim
//
//  Created by Santthosh on 11/3/12.
//  Copyright (c) 2012 appinmap.com. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface AIMDevice : NSObject

+(NSString *)getDeviceODIN1;

+(NSString *)getDeviceHashedUDID;

+(NSString *)getIdentifierForVendor;

+(NSString *)getIdentifierForAdvertiser;

+(NSString *)getDeviceModel;

+(NSString *)getUserAgent;

@end
