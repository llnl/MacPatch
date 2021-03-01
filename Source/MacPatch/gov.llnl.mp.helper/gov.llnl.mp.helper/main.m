//
//  main.m
//  gov.llnl.mp.worker
//
//  Created by Charles Heizer on 2/8/17.
//  Copyright © 2017 Lawrence Livermore Nat'l Lab. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "lcl.h"
#import "XPCWorker.h"

static void setUpLogging(void);

int main(int argc, const char * argv[])
{
    @autoreleasepool
    {
        if (argc >= 2) {
            if (strcmp(argv[1], "-v") == 0) {
                printf("1.0.0\n");
                return (0);
            }
        }
        
        setUpLogging();
        
		XPCWorker *worker = [[XPCWorker alloc] init];
        [worker run];
    }
    return 0;
}

static void setUpLogging ()
{
    // Setup logging
    BOOL enableDebug = NO;
    [MPLog setupLogging:@"/Library/Logs/gov.llnl.mp.helper.log" level:lcl_vDebug];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *appPrefsPath = @"/Library/Preferences/gov.llnl.mp.helper.plist";
    
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
        logit(lcl_vInfo,@"***** gov.llnl.mp.helper started -- Debug Enabled *****");
    } else {
        // enable logging for all components up to level Info
        //lcl_configure_by_name("*", lcl_vInfo);
        lcl_configure_by_name("*", lcl_vDebug);
        [MPLog MirrorMessagesToStdErr:YES];
        logit(lcl_vInfo,@"***** gov.llnl.mp.helper started *****");
    }
}
