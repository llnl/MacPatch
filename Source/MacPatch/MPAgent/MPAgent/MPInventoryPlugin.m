//
//  MPInventoryPlugin.m
//  MPAgent
/*
 Copyright (c) 2018, Lawrence Livermore National Security, LLC.
 Produced at the Lawrence Livermore National Laboratory (cf, DISCLAIMER).
 Written by Charles Heizer <heizer1 at llnl.gov>.
 LLNL-CODE-636469 All rights reserved.
 
 This file is part of MacPatch, a program for installing and patching
 software.
 
 MacPatch is free software; you can redistribute it and/or modify it under
 the terms of the GNU General Public License (as published by the Free
 Software Foundation) version 2, dated June 1991.
 
 MacPatch is distributed in the hope that it will be useful, but WITHOUT ANY
 WARRANTY; without even the IMPLIED WARRANTY OF MERCHANTABILITY or FITNESS
 FOR A PARTICULAR PURPOSE. See the terms and conditions of the GNU General Public
 License for more details.
 
 You should have received a copy of the GNU General Public License along
 with MacPatch; if not, write to the Free Software Foundation, Inc.,
 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
 */


#import "MPInventoryPlugin.h"
#import "InventoryPlugin.h"
#include <CommonCrypto/CommonCrypto.h>

#define kMPInvPluginsDir    @"/Library/MacPatch/Client/lib/PlugIns"

@implementation MPInventoryPlugin

- (NSArray *)loadPlugins
{
    NSArray *fileNames = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:kMPInvPluginsDir error:nil];
    if ([fileNames count] <= 0) {
        return nil;
    }
    NSString *fullFilePath = nil;
    NSMutableArray *availablePlugins = [NSMutableArray array];
    
    id plugin = nil;
    NSBundle *pluginBundle = nil;
    
    for (NSString *fileName in fileNames)
    {
        if (![fileName hasSuffix:@"bundle"]) continue;
        
        plugin = nil;
        pluginBundle = nil;
        fullFilePath = [kMPInvPluginsDir stringByAppendingPathComponent:fileName];
        pluginBundle = [NSBundle bundleWithPath:fullFilePath];
        [pluginBundle load];
        
        Class principalClass = [pluginBundle principalClass];
        
        // Do a little sanity checking
        if (![principalClass conformsToProtocol: @protocol(InventoryPluginProtocol)]) {
            NSLog (@"plug-in principal class must conform to the InventoryPluginProtocol");
            continue;
        }
		
        // Check to see if valid hash
        NSString *_pluginHash = [self getPluginHash:fullFilePath];
		qldebug(@"Plugimn Hash: %@",_pluginHash);
        BOOL validPlugin = [self isValidPlugin:[[pluginBundle infoDictionary] valueForKey:@"CFBundleName"]
                                      bundleID:[[pluginBundle infoDictionary] valueForKey:@"CFBundleIdentifier"]
                                       version:[[pluginBundle infoDictionary] valueForKey:@"CFBundleShortVersionString"] pluginHash:_pluginHash];
        if (!validPlugin) {
            logit(lcl_vError, @"Will not load %@. Invalid plugin.",[[pluginBundle infoDictionary] valueForKey:@"CFBundleName"]);
            continue;
        }
        
        plugin = [[principalClass alloc] init];
        [availablePlugins addObject:@{ @"plugin":plugin,
                                       @"pluginName":[[pluginBundle infoDictionary] valueForKey:@"CFBundleName"],
                                       @"pluginVersion":[[pluginBundle infoDictionary] valueForKey:@"CFBundleShortVersionString"]}];
        
        plugin = nil;
        pluginBundle = nil;
    }
    
    return availablePlugins;
}

- (BOOL)isValidPlugin:(NSString *)pluginName bundleID:(NSString *)pluginBundleID version:(NSString *)pluginVersion pluginHash:(NSString *)aHash
{
    BOOL result = NO;
    NSError *err = nil;
    MPRESTfull *mprest = [[MPRESTfull alloc] init];
    NSString *wsHash = [mprest getHashForPluginName:pluginName pluginBunleID:pluginBundleID pluginVersion:pluginVersion error:&err];
    if (err) {
        logit(lcl_vError,@"%@",err.description);
        return result;
    }
    logit(lcl_vDebug,@"Web Service returned hash: %@",wsHash);
    
    if ([[wsHash uppercaseString] isEqualToString:[aHash uppercaseString]]) {
        result = YES;
    } else {
        logit(lcl_vError,@"Hashes did not match. Plugin is not valid.")
        logit(lcl_vDebug,@"Web Service hash: %@",wsHash);
        logit(lcl_vDebug,@"Plugin hash: %@",aHash);
    }
    
    return result;
}

- (NSString *)getPluginHash:(NSString *)aFullPath
{
    MPCrypto *mpc = [[MPCrypto alloc] init];
    NSBundle *_pluginBundle = [NSBundle bundleWithPath:aFullPath];
    NSDictionary *_pluginBundleDict = [_pluginBundle infoDictionary];
    NSString *_pluginBinary = [[aFullPath stringByAppendingString:@"/Contents/MacOS"] stringByAppendingPathComponent:[_pluginBundleDict valueForKey:@"CFBundleName"]];
    NSString *_pluginBinHash = [mpc getHashForFileForType:_pluginBinary type:@"SHA1"];
    NSString *_pluginHashString = [NSString stringWithFormat:@"%@%@%@",[_pluginBundleDict valueForKey:@"CFBundleIdentifier"],[_pluginBundleDict valueForKey:@"CFBundleShortVersionString"], _pluginBinHash];
    NSData *_dataIn = [_pluginHashString dataUsingEncoding:NSASCIIStringEncoding];
    NSMutableData *_macOut = [NSMutableData dataWithLength:CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(_dataIn.bytes, (CC_LONG)_dataIn.length,  _macOut.mutableBytes);
    
    NSString *hexHash = [self hexforData:_macOut];
    return hexHash;
}

- (NSString *)hexforData:(NSData *)theData
{
    NSUInteger dataLength = [theData length];
    NSMutableString *string = [NSMutableString stringWithCapacity:dataLength*2];
    const unsigned char *dataBytes = [theData bytes];
    for (NSInteger idx = 0; idx < dataLength; ++idx)
    {
        [string appendFormat:@"%02x", dataBytes[idx]];
    }
    
    return string;
}

@end
