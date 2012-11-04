//
//  AIMPOSTOperation.m
//  aim
//
//  Created by Santthosh on 11/2/12.
//  Copyright (c) 2012 appinmap.com. All rights reserved.
//

#import "AIMPOSTOperation.h"

@implementation AIMPOSTOperation

@synthesize error, data, connectionURL;

#pragma mark -
#pragma mark Initialization & Memory Management

-(id)initWithURL:(NSURL*)url body:(NSData *)abody username:(NSString *)aUsername password:(NSString *)aPassword {
    if( (self = [super init]) ) {
        connectionURL = [url copy];
        body = abody;
        username = aUsername;
        password = aPassword;
    }
    return self;
}

- (void)dealloc {
    if(connection) {
        [connection cancel];
    }
}

#pragma mark -
#pragma mark Start & Utility Methods

// This method is just for convenience. It cancels the URL connection if it
// still exists and finishes up the operation.
- (void)done {
    if(connection) {
        [connection cancel];
    }
    
    // Alert anyone that we are finished
    [self willChangeValueForKey:@"isExecuting"];
    [self willChangeValueForKey:@"isFinished"];
    
    executing = NO;
    finished  = YES;
    
    [self didChangeValueForKey:@"isFinished"];
    [self didChangeValueForKey:@"isExecuting"];
}

-(void)canceled {
	// Code for being cancelled
    error = [[NSError alloc] initWithDomain:@"AIMPOSTOperation" code:205 userInfo:nil];
    [self done];
}

- (void)start {
    // Ensure that this operation starts on the main thread
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(start) withObject:nil waitUntilDone:NO];
        return;
    }
    
    // Ensure that the operation should execute
    if( finished || [self isCancelled] ) { [self done]; return; }
    
    // From this point on, the operation is officially executing--remember, isExecuting
    // needs to be KVO compliant!
    [self willChangeValueForKey:@"isExecuting"];
    executing = YES;
    [self didChangeValueForKey:@"isExecuting"];
    
    // Create the NSURLConnection--this could have been done in init, but we delayed
    // until no in case the operation was never enqueued or was cancelled before starting
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:connectionURL cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:20.0];
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:body];
    [request setValue:@"application/json" forHTTPHeaderField:@"content-type"];
    connection = [[NSURLConnection alloc] initWithRequest:request delegate:self];
}

#pragma mark -
#pragma mark Overrides

- (BOOL)isConcurrent {
    return YES;
}

- (BOOL)isExecuting {
    return executing;
}

- (BOOL)isFinished {
    return finished;
}

#pragma mark -
#pragma mark Delegate Methods for NSURLConnection

- (BOOL)connection:(NSURLConnection *)connection canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)protectionSpace {
    return [protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust] || [protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodHTTPBasic];
    
}

- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        if ([challenge.protectionSpace.host isEqualToString:@"api.appinmap.com"])
            [challenge.sender useCredential:[NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust] forAuthenticationChallenge:challenge];
    } else if([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodHTTPBasic]) {
        if([challenge previousFailureCount] == 0) {
            NSURLCredential *newCredential = [NSURLCredential credentialWithUser:username
                                                                        password:password
                                                                     persistence:NSURLCredentialPersistenceForSession];
            [[challenge sender] useCredential:newCredential forAuthenticationChallenge:challenge];
        }
        else {
            NSLog(@"previous authentication failure");
            [challenge.sender continueWithoutCredentialForAuthenticationChallenge:challenge];
        }
    }
}

// The connection failed
- (void)connection:(NSURLConnection*)connection didFailWithError:(NSError*)error {
    // Check if the operation has been cancelled
    if([self isCancelled]) {
        [self canceled];
		return;
    }
	else {
		[self done];
	}
}

// The connection received more data
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)aData {
    // Check if the operation has been cancelled
    if([self isCancelled]) {
        [self canceled];
		return;
    }
    
    [data appendData:aData];
}

// Initial response
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    // Check if the operation has been cancelled
    if([self isCancelled]) {
        [self canceled];
		return;
    }
    
    NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
    NSInteger statusCode = [httpResponse statusCode];
    if(statusCode == 200 || statusCode == 201) {
        NSUInteger contentSize = [httpResponse expectedContentLength] > 0 ? [httpResponse expectedContentLength] : 0;
        data = [[NSMutableData alloc] initWithCapacity:contentSize];
    } else {
        NSString* statusError  = [NSString stringWithFormat:NSLocalizedString(@"HTTP Error: %ld", nil), statusCode];
        NSDictionary* userInfo = [NSDictionary dictionaryWithObject:statusError forKey:NSLocalizedDescriptionKey];
        error = [[NSError alloc] initWithDomain:@"AIMPOSTOperation"code:statusCode userInfo:userInfo];
        [self done];
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    // Check if the operation has been cancelled
    if([self isCancelled]) {
        [self canceled];
		return;
    }
	else {
		[self done];
	}
}

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection
                  willCacheResponse:(NSCachedURLResponse *)cachedResponse {
    return nil;
}

@end
