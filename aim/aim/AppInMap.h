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

@property (nonatomic,strong) NSArray *tags;

+(void)startSession:(NSString *)applicationId secret:(NSString *)secret;

+(void)setLatitude:(CGFloat)latitude longitude:(CGFloat)longitude accuracy:(CGFloat)accuracy;

+(void)endSession;

@end
