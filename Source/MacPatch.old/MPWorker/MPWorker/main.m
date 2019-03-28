//
//  main.m
//  MPWorker
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

#import <Foundation/Foundation.h>
#import "MPWorkerProtocol.h"
#import "WorkerConnectionMonitor.h"
#import "MPWorker.h"

static void setUpLogging(void);

int main(int argc, const char * argv[])
{
    @autoreleasepool
    {
        NSPort *receivePort = nil;
        if (argc >= 2) {
		if (strcmp(argv[1], "-v") == 0) {
                printf("2.1.2\n");
			return (0);
            }
        }
        
        setUpLogging();
	
        WorkerConnectionMonitor *monitor = [[WorkerConnectionMonitor alloc] init];
        MPWorker *worker = [[MPWorker alloc] init];
        
        if (receivePort == nil) {
            receivePort = [NSMachPort port];
        }
        if (receivePort == nil) {
            NSLog(@"Receive port could not be made");
        }
        
        NSConnection *connection = [NSConnection connectionWithReceivePort:receivePort sendPort:nil];
        if (![connection registerName: kMPWorkerPortName]) {
            NSLog(@"Could not register name");
            
        }
        
        [connection setRootObject: worker];
        [[NSRunLoop currentRunLoop] run];
        
    }
    return 0;
}

static void setUpLogging (void)
{
	// Setup logging
	BOOL enableDebug = NO;
	[MPLog setupLogging:@"/Library/MacPatch/Client/Logs/MPWorker.log" level:lcl_vDebug];
	
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *appPrefsPath = @"/Library/Preferences/gov.llnl.MPWorker.plist";
	
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
		logit(lcl_vInfo,@"***** MPWorker started -- Debug Enabled *****");
	} else {
		// enable logging for all components up to level Info
		lcl_configure_by_name("*", lcl_vInfo);
		logit(lcl_vInfo,@"***** MPWorker started *****");
	}
}

