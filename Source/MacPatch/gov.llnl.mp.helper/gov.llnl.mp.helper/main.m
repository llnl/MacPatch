//
//  main.m
/*
 Copyright (c) 2026, Lawrence Livermore National Security, LLC.
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
#import "Logger.h"
#import "XPCWorker.h"

static void setUpLogging(void);

int main(int argc, const char * argv[])
{
    @autoreleasepool
    {
        if (argc >= 2) {
            if (strcmp(argv[1], "-v") == 0) {
                printf("4.2.3\n");
                return (0);
            }
        }
        
        setUpLogging();
        
		XPCWorker *worker = [[XPCWorker alloc] init];
        [worker run];
    }
    return 0;
}

static void setUpLogging (void)
{
    // Setup logging
    BOOL enableDebug = NO;

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *appPrefsPath = @"/Library/Preferences/gov.llnl.mp.helper.plist";

    if ([fileManager fileExistsAtPath:appPrefsPath] == YES) {
        NSDictionary *appPrefs = [NSDictionary dictionaryWithContentsOfFile:appPrefsPath];
        BOOL containsKey = ([appPrefs objectForKey:@"DeBug"] != nil);
        if (containsKey) {
            enableDebug = [[appPrefs objectForKey:@"DeBug"] boolValue];
        }
    }

    // Setup new Logger
    Logger *logger = [Logger sharedLogger];
    [logger setupWithLogPath:@"/Library/Logs/gov.llnl.mp.helper.log"
                   subsystem:@"gov.llnl.mp.helper"
                    category:@"helper"];
    logger.enableFileLogging = YES;
    logger.enableConsoleLogging = NO;
    logger.enableStderrLogging = YES;
    logger.minimumLogLevel = enableDebug ? LogLevelDebug : LogLevelInfo;

    if (enableDebug) {
        LogInfo(@"***** gov.llnl.mp.helper started -- Debug Enabled *****");
    } else {
        LogInfo(@"***** gov.llnl.mp.helper started *****");
    }
}
