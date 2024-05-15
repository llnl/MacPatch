//
//  main.m
//  gov.llnl.mp.status.ui
//
/*
 Copyright (c) 2024, Lawrence Livermore National Security, LLC.
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

#import <Foundation/Foundation.h>
#import "lcl.h"
#import "XPCStatus.h"

static void setUpLogging(void);

int main(int argc, const char * argv[])
{
    @autoreleasepool
    {
        if (argc >= 2) {
            if (strcmp(argv[1], "-v") == 0) {
                printf("3.7.0\n");
                return (0);
            }
        }
        
        setUpLogging();
        
        XPCStatus *worker = [[XPCStatus alloc] init];
        [worker run];
    }
    return 0;
}

static void setUpLogging ()
{
    // Setup logging
    BOOL enableDebug = NO;
    [MPLog setupLogging:@"/Library/Logs/gov.llnl.mp.status.ui.log" level:lcl_vInfo];
    //NSString *_logFile = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/gov.llnl.mp.status.ui.log"];
    //[MPLog setupLogging:_logFile level:lcl_vInfo];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *appPrefsPath = @"/Library/Preferences/gov.llnl.mp.status.ui.plist";
    
    if ([fileManager fileExistsAtPath:appPrefsPath] == YES) {
        NSDictionary *appPrefs = [NSDictionary dictionaryWithContentsOfFile:appPrefsPath];
        BOOL containsKey = ([appPrefs objectForKey:@"DeBug"] != nil);
        if (containsKey) {
            enableDebug = [[appPrefs objectForKey:@"DeBug"] boolValue];
        }
    }
    
    if (enableDebug) {
        // enable logging for all components up to level Debug
        lcl_configure_by_name("*", lcl_vDebug);
        [MPLog MirrorMessagesToStdErr:YES];
        logit(lcl_vInfo,@"***** gov.llnl.mp.status.ui started -- Debug Enabled *****");
    } else {
        // enable logging for all components up to level Info
        lcl_configure_by_name("*", lcl_vInfo);
        [MPLog MirrorMessagesToStdErr:YES];
        logit(lcl_vInfo,@"***** gov.llnl.mp.status.ui started *****");
    }
}
