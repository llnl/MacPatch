//
//  MPScanner.m
//  MPLoginAgent
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

#import "MPScanner.h"

@implementation MPScanner

- (NSArray *)scanForAppleUpdates
{
    logit(lcl_vInfo,@"Scanning for Apple software updates.");
    
    NSArray *appleUpdates = nil;
    
    NSTask *spTask = [[NSTask alloc] init];
    [spTask setLaunchPath: ASUS_BIN_PATH];
    [spTask setArguments: [NSArray arrayWithObjects: @"-l", nil]];
    
    NSPipe *pipe = [NSPipe pipe];
    [spTask setStandardOutput: pipe];
    [spTask setStandardError: pipe];
    
    NSFileHandle *file = [pipe fileHandleForReading];
    
    [spTask launch];
    logit(lcl_vInfo,@"Starting Apple software update scan.");
    [spTask waitUntilExit];
    
    int status = [spTask terminationStatus];
    if (status != 0) {
        logit(lcl_vError,@"Error: softwareupdate exit code = %d",status);
        return appleUpdates;
    } else {
        logit(lcl_vInfo,@"Apple software update scan was completed.");
    }
    
    NSData *data = [file readDataToEndOfFile];
    NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    logit(lcl_vInfo,@"Apple software update full scan results\n%@",string);
    
    if (!([string rangeOfString:@"No new"].location == NSNotFound)) {
        logit(lcl_vInfo,@"No new updates.");
        return appleUpdates;
    }
    
    // We have updates so we need to parse the results
    NSArray *strArr = [NSArray arrayWithArray:[string componentsSeparatedByString:@"\n"]];
    
    NSMutableArray *tmpAppleUpdates = [[NSMutableArray alloc] init];
    NSString *tmpStr;
    NSMutableDictionary *tmpDict;
    
    for (int i=0; i<[strArr count]; i++) {
        // Ignore empty lines
        if ([[strArr objectAtIndex:i] length] != 0) {
            
            //Clear the tmpDict object before populating it
            if (!([[strArr objectAtIndex:i] rangeOfString:@"Software Update Tool"].location == NSNotFound)) {
                continue;
            }
            if (!([[strArr objectAtIndex:i] rangeOfString:@"Copyright"].location == NSNotFound)) {
                continue;
            }
            
            // Strip the White Space and any New line data
            tmpStr = [[strArr objectAtIndex:i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            
            // If the object/string starts with *,!,- then allow it
            if ([[tmpStr substringWithRange:NSMakeRange(0,1)] isEqual:@"*"] || [[tmpStr substringWithRange:NSMakeRange(0,1)] isEqual:@"!"] || [[tmpStr substringWithRange:NSMakeRange(0,1)] isEqual:@"-"]) {
                tmpDict = [[NSMutableDictionary alloc] init];
                logit(lcl_vInfo,@"Apple Update: %@",[tmpStr substringWithRange:NSMakeRange(2,([tmpStr length]-2))]);
                [tmpDict setObject:[tmpStr substringWithRange:NSMakeRange(2,([tmpStr length]-2))] forKey:@"patch"];
                [tmpDict setObject:@"Apple" forKey:@"type"];
                [tmpDict setObject:[[[tmpStr substringWithRange:NSMakeRange(2,([tmpStr length]-2))] componentsSeparatedByString:@"-"] lastObject] forKey:@"version"];
                [tmpDict setObject:[[strArr objectAtIndex:(i+1)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] forKey:@"description"];
                [tmpDict setObject:[self getSizeFromDescription:[tmpDict objectForKey:@"description"]] forKey:@"size"];
                [tmpDict setObject:[self getRecommendedFromDescription:[tmpDict objectForKey:@"description"]] forKey:@"recommended"];
                if ([[[strArr objectAtIndex:(i+1)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] containsString:@"[restart]" ignoringCase:YES] == TRUE) {
                    [tmpDict setObject:@"Yes" forKey:@"restart"];
                } else {
                    [tmpDict setObject:@"No" forKey:@"restart"];
                }
                
                [tmpAppleUpdates addObject:tmpDict];
                tmpDict = nil;
            } // if is an update
        } // if / empty lines
    } // for loop
    appleUpdates = [NSArray arrayWithArray:tmpAppleUpdates];
    
    logit(lcl_vDebug,@"Apple Updates Found, %@",appleUpdates);
    return appleUpdates;
}

- (NSArray *)scanForCustomUpdates
{
    logit(lcl_vInfo,@"Scanning for custom software updates.");
    [[NSDistributedNotificationCenter defaultCenter] addObserver: self
                                                        selector: @selector(scanForNotification:)
                                                            name: @"ScanForNotification"
                                                          object: nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(scanForNotification:)
                                                 name:@"ScanForNotification"
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ScanForNotification" object:nil userInfo:nil];
    
    
    NSArray *result = nil;
    MPPatchScan *patchScanObj = [[MPPatchScan alloc] init];
    patchScanObj.delegate = self;
    [patchScanObj setUseDistributedNotification:NO];
    result = [NSArray arrayWithArray:[patchScanObj scanForPatches]];
    return result;
}

- (void)scanForNotification:(NSNotification *)notification
{
    NSDictionary *tmpDict = [notification userInfo];
    
    if(notification)
    {
        logit(lcl_vDebug,@"[scanForNotification]: %@",tmpDict);
    }
}

- (void)patchScan:(MPPatchScan *)patchScan didReciveStatusData:(NSString *)data
{
    //[self postDataToClient:data type:kMPProcessStatus];
    [_delegate scanData:self data:data];
}

#pragma mark - Misc
- (NSString *)getSizeFromDescription:(NSString *)aDesc
{
    NSArray *tmpArr1 = [aDesc componentsSeparatedByString:@","];
    NSArray *tmpArr2 = [[[tmpArr1 objectAtIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsSeparatedByString:@" "];
    return [[tmpArr2 objectAtIndex:0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSString *)getRecommendedFromDescription:(NSString *)aDesc
{
    NSRange textRange;
    textRange =[aDesc rangeOfString:@"recommended"];
    
    if(textRange.location != NSNotFound) {
        return @"Y";
    } else {
        return @"N";
    }
    
    return @"N";
}

@end
