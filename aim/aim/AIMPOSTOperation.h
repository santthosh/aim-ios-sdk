//
//  AIMPOSTOperation.h
//  aim
//
//  Created by Santthosh on 11/2/12.
//  Copyright (c) 2012 appinmap.com. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface AIMPOSTOperation : NSOperation {
    BOOL executing;
    BOOL finished;
    
    NSData *body;
    NSString *username;
    NSString *password;
    NSURLConnection *connection;
}

@property (nonatomic,readonly) NSError* error;
@property (nonatomic,readonly) NSMutableData *data;
@property (nonatomic,readonly) NSURL *connectionURL;

-(id)initWithURL:(NSURL*)url body:(NSData *)body username:(NSString *)username password:(NSString *)password;

@end
