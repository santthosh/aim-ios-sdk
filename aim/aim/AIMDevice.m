//
//  AIMDevice.m
//  aim
//
//  Created by Santthosh on 11/3/12.
//  Copyright (c) 2012 appinmap.com. All rights reserved.
//

#import "AIMDevice.h"
#import <UIKit/UIKit.h>
#ifdef __IPHONE_6_0
    #import <AdSupport/ASIdentifierManager.h>
#endif
#import <SystemConfiguration/CaptiveNetwork.h>
#import <CommonCrypto/CommonCryptor.h>
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>
#include <sys/sysctl.h>
#include <sys/socket.h>
#include <sys/sysctl.h>
#include <net/if.h>
#include <net/if_dl.h>

@implementation AIMDevice

#pragma mark - Message Digests

+ (NSData *)MD5Data:(NSData *)data {
    const char* str = data.bytes;
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5(str, strlen(str), result);
    NSData *_data = [NSData dataWithBytes:result length:CC_MD5_DIGEST_LENGTH];
    return _data;
}

+ (NSString *)MD5Digest:(NSString *)input {
    const char *cstr = [input cStringUsingEncoding:NSUTF8StringEncoding];
    NSData *data = [NSData dataWithBytes:cstr length:input.length];
    uint8_t digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(data.bytes, data.length, digest);
    NSMutableString* output = [NSMutableString
                               stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for(int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
        [output appendFormat:@"%02x", digest[i]];
    }
    return output;
}

+ (NSString *)SHA1Digest:(NSString*)input {
    const char *cstr = [input cStringUsingEncoding:NSUTF8StringEncoding];
    NSData *data = [NSData dataWithBytes:cstr length:input.length];
    uint8_t digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(data.bytes, data.length, digest);
    NSMutableString* output = [NSMutableString
                               stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
    for(int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
        [output appendFormat:@"%02x", digest[i]];
    }
    return output;
}

#pragma mark - Getting Identifiers

+(NSString *)getDeviceODIN1 {
    // Step 1: Get MAC address
    int                 mib[6];
    size_t              len;
    char                *buf;
    unsigned char       *ptr;
    struct if_msghdr    *ifm;
    struct sockaddr_dl  *sdl;
    
    mib[0] = CTL_NET;
    mib[1] = AF_ROUTE;
    mib[2] = 0;
    mib[3] = AF_LINK;
    mib[4] = NET_RT_IFLIST;
    
    if ((mib[5] = if_nametoindex("en0")) == 0) {
        //NSLog(@"ODIN-1.1: if_nametoindex error");
        return nil;
    }
    
    if (sysctl(mib, 6, NULL, &len, NULL, 0) < 0) {
        //NSLog(@"ODIN-1.1: sysctl 1 error");
        return nil;
    }
    
    if ((buf = malloc(len)) == NULL) {
        //NSLog(@"ODIN-1.1: malloc error");
        return nil;
    }
    
    if (sysctl(mib, 6, buf, &len, NULL, 0) < 0) {
        //NSLog(@"ODIN-1.1: sysctl 2 error");
        if (buf) free(buf);
        return nil;
    }
    
    ifm = (struct if_msghdr *)buf;
    sdl = (struct sockaddr_dl *)(ifm + 1);
    ptr = (unsigned char *)LLADDR(sdl);
    
    //NSLog(@"SO1 - MAC Address: %02X:%02X:%02X:%02X:%02X:%02X",
    //      *ptr, *(ptr+1), *(ptr+2), *(ptr+3), *(ptr+4), *(ptr+5));
    
    // Step 2: Take the SHA-1 of the MAC address
    
    CFDataRef data = CFDataCreate(NULL, (uint8_t*)ptr, 6);
    
    unsigned char messageDigest[CC_SHA1_DIGEST_LENGTH];
	
	CC_SHA1(CFDataGetBytePtr((CFDataRef)data),
			CFDataGetLength((CFDataRef)data),
			messageDigest);
	
	CFMutableStringRef string = CFStringCreateMutable(NULL, 40);
	for(int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
		CFStringAppendFormat(string,
							 NULL,
							 (CFStringRef)@"%02X",
							 messageDigest[i]);
	}
    CFStringLowercase(string, CFLocaleGetSystem());
    
    if (buf) free(buf);

    NSString *odinstring = [[NSString alloc] initWithString:(NSString *)CFBridgingRelease(string)];
   
    CFRelease(data);
    //CFRelease(string);
    
    return odinstring;
}

+(NSString *)getDeviceHashedUDID {
    UIDevice *device = [UIDevice currentDevice];
    NSString *udid = nil;
    if([device respondsToSelector:@selector(uniqueIdentifier)])
        udid = [device uniqueIdentifier];
    else
        return nil;
        
    return [AIMDevice MD5Digest:udid];
}


+(NSString *)getIdentifierForVendor {
    UIDevice *device = [UIDevice currentDevice];
    NSUUID *idForVendor = nil;
    if([device respondsToSelector:@selector(identifierForVendor)])
        idForVendor = [device identifierForVendor];
    else
        return nil;
    
    return [idForVendor UUIDString];
}

+(NSString *)getIdentifierForAdvertiser {
#ifdef __IPHONE_6_0
    if (NSClassFromString(@"ASIdentifierManager")) {
        ASIdentifierManager *advIdManager = [ASIdentifierManager sharedManager];
        return [[advIdManager advertisingIdentifier] UUIDString];
    }
#endif
    return nil;
}

@end
