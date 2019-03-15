//
//  SandBoxHelper.m
//  IAPDemo
//
//  Created by Charles.Yao on 2016/10/31.
//  Copyright © 2016年 com.pico. All rights reserved.
//

#import "SandBoxHelper.h"

@implementation SandBoxHelper

+ (NSString *)homePath {
    return NSHomeDirectory();
}

+ (NSString *)appPath {
    NSArray * paths = NSSearchPathForDirectoriesInDomains(NSApplicationDirectory, NSUserDomainMask, YES);
    return [paths objectAtIndex:0];
}

+ (NSString *)docPath {
    NSArray * paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return [paths objectAtIndex:0];
}

+ (NSString *)libPrefPath {
    NSArray * paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    return [[paths objectAtIndex:0] stringByAppendingFormat:@"/Preferences"];
}

+ (NSString *)libCachePath {
    
    NSArray * paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    return [[paths objectAtIndex:0] stringByAppendingFormat:@"/Caches"];
}

+ (NSString *)tmpPath {
    return [NSHomeDirectory() stringByAppendingFormat:@"/tmp"];
}

+ (NSString *)iapReceiptPath {
    
    NSString *path = [[self libPrefPath] stringByAppendingFormat:@"/EACEF35FE363A75A"];
    [self hasLive:path];
    return path;
}

+ (BOOL)hasLive:(NSString *)path
{
    if ( NO == [[NSFileManager defaultManager] fileExistsAtPath:path] )
    {
        return [[NSFileManager defaultManager] createDirectoryAtPath:path
                                         withIntermediateDirectories:YES
                                                          attributes:nil
                                                               error:NULL];
    }
    
    return YES;
}

+(NSString *)SuccessIapPath{
    
    NSString *path = [[self libPrefPath] stringByAppendingFormat:@"/SuccessReceiptPath"];
    
    [self hasLive:path];
    
    
    return path;
    
}

+(NSString *)exitResourePath{
    
    NSString *path = [[self libPrefPath] stringByAppendingFormat:@"/ExitResourePath"];
    
    [self hasLive:path];
    
    
    return path;
}

+(NSString *)tempOrderPath{
  
    NSString *path = [[self libPrefPath] stringByAppendingFormat:@"/tempOrderPath"];
    
    [self hasLive:path];
   
    return path;
    
}

+(NSString *)crashLogInfo{
    
    NSString * path = [[self libPrefPath]stringByAppendingFormat:@"/crashLogInfoPath"];
    [self hasLive:path];
    
    return path;
}

@end
