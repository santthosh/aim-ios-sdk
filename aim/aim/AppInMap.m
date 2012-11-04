//
//  AppInMap.m
//  aim
//
//  Created by Santthosh on 11/2/12.
//  Copyright (c) 2012 appinmap.com. All rights reserved.
//

#import "AppInMap.h"

#import "AIMDevice.h"
#import "AIMPOSTOperation.h"
#import "AIMJSONKit.h"

@interface AppInMap ()

+(AppInMap *)sharedInstance;

@property (nonatomic,strong) NSString *applicationId;

@property (nonatomic,strong) NSString *applicationSecret;

@property (nonatomic,strong) NSString *bundleId;

@property (nonatomic,strong) NSString *sdkVersion;

@property (nonatomic,strong) NSString *appVersion;

@property (nonatomic,strong) NSOperationQueue *queue;

@property (nonatomic,strong) NSString *sessionId;

@property (nonatomic,assign) CGFloat latitude;

@property (nonatomic,assign) CGFloat longitude;

@property (nonatomic,assign) CGFloat accuracy;

@end

@implementation AppInMap

@synthesize applicationId,applicationSecret,bundleId,sdkVersion,appVersion,tags,queue,sessionId,latitude,longitude,accuracy;

#pragma mark - Class Methods

+(AppInMap *)sharedInstance {
    static AppInMap *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[AppInMap alloc] init];
        sharedInstance.queue = [[NSOperationQueue alloc] init];
    });
    return sharedInstance;
}

+(void)startSession:(NSString *)applicationId secret:(NSString *)secret {
    AppInMap *manager = [AppInMap sharedInstance];
    
    manager.applicationId = applicationId;
    manager.applicationSecret = secret;
    
    NSDictionary *bundleDictionary = [[NSBundle mainBundle] infoDictionary];
    manager.bundleId = [bundleDictionary objectForKey:@"CFBundleIdentifier"];
    manager.sdkVersion = SDK_VERSION;
    manager.appVersion = [NSString stringWithFormat:@"%@,%@",[bundleDictionary objectForKey:@"CFBundleShortVersionString"], [bundleDictionary objectForKey:@"CFBundleVersion"]];
    
    [manager startSession];
}

+(void)setLatitude:(CGFloat)latitude longitude:(CGFloat)longitude accuracy:(CGFloat)accuracy {
    AppInMap *manager = [AppInMap sharedInstance];
    
    manager.latitude = latitude;
    manager.longitude = longitude;
    manager.accuracy = accuracy;
}

+ (NSString *)uuid {
    CFUUIDRef theUUID = CFUUIDCreate(NULL);
    NSString *uuidString = (__bridge_transfer NSString *) CFUUIDCreateString(NULL, theUUID);
    CFRelease(theUUID);
    return uuidString;
}

#pragma mark - Instance Methods

-(void)startSession {
    sessionId = [AppInMap uuid];
    
    /*
     * '{"sessionId":"9f87d9dc-e91a-48a6-9a4c-0e65ac0ba2cc","applicationId":"098c27f2-383b-4cad-909b-e63f28387a44",
     * "bundleId":"com.dinakaran.mobile.iphone", 
     * "deviceIds":["2216f4f9-60da-4478-9fb6-9c4ca778c57a"],"time":1351380896,"appVersion":"1.02.1.02","sdkVersion":"0.1","location":
     * {"latitude":37.391644,"longitude":-122.044174,"accuracy":50},"platform":0,"tags":[]}'
     */
    
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    [dictionary setObject:sessionId forKey:@"sessionId"];
    [dictionary setObject:applicationId forKey:@"applicationId"];
    [dictionary setObject:bundleId forKey:@"bundleId"];
    [dictionary setObject:[NSNumber numberWithLongLong:([[NSDate date] timeIntervalSince1970] * 1000)] forKey:@"time"];
    [dictionary setObject:appVersion forKey:@"appVersion"];
    [dictionary setObject:sdkVersion forKey:@"sdkVersion"];
    
    NSMutableDictionary *location = [NSMutableDictionary dictionary];
    [location setObject:[NSNumber numberWithFloat:latitude] forKey:@"latitude"];
    [location setObject:[NSNumber numberWithFloat:longitude] forKey:@"longitude"];
    [location setObject:[NSNumber numberWithFloat:accuracy] forKey:@"accuracy"];
    [dictionary setObject:location forKey:@"location"];
    
    NSMutableArray *deviceIds = [NSMutableArray array];
    NSString *udid = [AIMDevice getDeviceHashedUDID];
    if(udid)
        [deviceIds addObject:[NSString stringWithFormat:@"UDID=%@",udid]];
    NSString *odin1 = [AIMDevice getDeviceODIN1];
    if(odin1)
        [deviceIds addObject:[NSString stringWithFormat:@"ODIN1=%@",odin1]];
    NSString *idv = [AIMDevice getIdentifierForVendor];
    if(idv)
        [deviceIds addObject:[NSString stringWithFormat:@"IDV=%@",idv]];
    NSString *ida = [AIMDevice getIdentifierForAdvertiser];
    if(ida)
        [deviceIds addObject:[NSString stringWithFormat:@"IDA=%@",ida]];
    
    [dictionary setObject:deviceIds forKey:@"deviceIds"];
    
    [dictionary setObject:[NSNumber numberWithInt:0] forKey:@"platform"];
    
    if(tags && [tags count]) {
        [dictionary setObject:tags forKey:@"tags"];
    } else {
        [dictionary setObject:[NSArray array] forKey:@"tags"];
    }
    
    AIMPOSTOperation *operation = [[AIMPOSTOperation alloc] initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/session/start",URL_BASE]] body:[dictionary JSONData] username:applicationId password:applicationSecret];
    [operation addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew context:NULL];
    [queue addOperation:operation];
}

-(void)sendBeacon:(NSString *)beaconURL {
    if(!sessionId)
        return;
    
    if(!beaconURL)
        beaconURL = @"/session/beacon";
        
    /*
     *
     curl --user "098c27f2-383b-4cad-909b-e63f28387a44":"008b06ef-0a48-4c78-8261-5570fd927ffb" -X POST -H "Content-Type: application/json; charset=UTF-8" -d '{"sessionId":"9f87d9dc-e91a-48a6-9a4c-0e65ac0ba2cc","time":1352380996,"location":{"latitude":37.391644,"longitude":-122.044174,"accuracy":50}}' http://localhost:8888/session/beacon
     */
    
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    [dictionary setObject:sessionId forKey:@"sessionId"];
    [dictionary setObject:[NSNumber numberWithLongLong:([[NSDate date] timeIntervalSince1970] * 1000)] forKey:@"time"];
    
    NSMutableDictionary *location = [NSMutableDictionary dictionary];
    [location setObject:[NSNumber numberWithFloat:latitude] forKey:@"latitude"];
    [location setObject:[NSNumber numberWithFloat:longitude] forKey:@"longitude"];
    [location setObject:[NSNumber numberWithFloat:accuracy] forKey:@"accuracy"];
    [dictionary setObject:location forKey:@"location"];
    
    AIMPOSTOperation *operation = [[AIMPOSTOperation alloc] initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@%@",URL_BASE,beaconURL]] body:[dictionary JSONData] username:applicationId password:applicationSecret];
    [operation addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionNew context:NULL];
    [queue addOperation:operation];
}

+(void)endSession {
    AppInMap *manager = [AppInMap sharedInstance];
    
    [NSTimer cancelPreviousPerformRequestsWithTarget:manager];
    [manager sendBeacon:@"/session/end"];
}

#pragma mark - KVO Observing

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)operation change:(NSDictionary *)change context:(void *)context {
    NSData *data = nil;
    NSError *error = nil;
    if ([operation isKindOfClass:[AIMPOSTOperation class]]) {
        AIMPOSTOperation *postOperation = (AIMPOSTOperation *)operation;
        if([postOperation.connectionURL.absoluteString hasSuffix:@"/session/start"]) {
            data = [postOperation data];
            error = [postOperation error];
            if(!error) {
                NSLog(@"[AIM] Session started");
                [NSTimer timerWithTimeInterval:120 target:self selector:@selector(sendBeacon:) userInfo:nil repeats:YES];
            } else {
                NSLog(@"Session start failed: %@",error);
            }
        } else if([postOperation.connectionURL.absoluteString hasSuffix:@"/session/beacon"]) {
            data = [postOperation data];
            error = [postOperation error];
            //Successful beacon
            if(error) {
                NSLog(@"Session beacon failed: %@",error);
            }
        } else if([postOperation.connectionURL.absoluteString hasSuffix:@"/session/endSession"]) {
            data = [postOperation data];
            error = [postOperation error];
            //Successful end session
            if(!error) {
                NSLog(@"[AIM] Session ended");
            } else {
                NSLog(@"Session end failed: %@",error);
            }
        }
    }
}


@end
