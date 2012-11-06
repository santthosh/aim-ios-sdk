//
//  AppInMap.h
//  aim
//
//  Created by Santthosh on 11/2/12.
//  Copyright (c) 2012 appinmap.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@interface AppInMap : NSObject

#pragma mark - Sessions

// Start the app in map session
+(void)startSession:(NSString *)applicationId secret:(NSString *)secret;

// Set the location parameters for the app in map analytics
+(void)setLatitude:(CGFloat)latitude longitude:(CGFloat)longitude accuracy:(CGFloat)accuracy;

// End the app in map session
+(void)endSession;

#pragma mark - Push Notification

// Register the device token for push notifications
+(void)registerDeviceToken:(NSData *)data;

#pragma mark - Tags

// Add a tag to the device tokens
+(void)addTags:(NSArray *)tags;

// Add tag
+(void)addTag:(NSString *)tag;

@end
