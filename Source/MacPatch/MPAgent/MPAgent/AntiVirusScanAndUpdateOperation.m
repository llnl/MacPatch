//
//  AntiVirusScanAndUpdateOperation.m
/*
 Copyright (c) 2017, Lawrence Livermore National Security, LLC.
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

#import "AntiVirusScanAndUpdateOperation.h"
#import "MPAgent.h"
#import "MacPatch.h"

@interface AntiVirusScanAndUpdateOperation (Private)

@property (nonatomic, readwrite) NSString *taskFile;

- (void)runAVInfoScan;
- (void)runAVInfoScanAndDefsUpdate;
- (int)runAVDefsUpdate;

@end

@implementation AntiVirusScanAndUpdateOperation

@synthesize scanType;
@synthesize taskPID;
@synthesize taskFile;
@synthesize isExecuting;
@synthesize isFinished;

- (id)init
{
	if ((self = [super init])) {
		scanType = 0;
        taskPID = -99;
		isExecuting = NO;
        isFinished  = NO;
		si	= [MPAgent sharedInstance];
		fm	= [NSFileManager defaultManager];
        taskFile = [@"/private/tmp" stringByAppendingPathComponent:kMPAVUpdate];
	}	
	
	return self;
}

- (BOOL)isConcurrent
{
    return YES;
}

- (void)cancel
{
    [self finish];
}

- (void)finish
{
    [self willChangeValueForKey:@"isFinished"];
    [self willChangeValueForKey:@"isExecuting"];
    isExecuting = NO;
    isFinished = YES;
    [self didChangeValueForKey:@"isExecuting"];
    [self didChangeValueForKey:@"isFinished"];

    [self killTaskUsingPID];
}

- (void)start 
{
    if ([self isCancelled]) {
        [self willChangeValueForKey:@"isFinished"];
        isFinished = YES;
        [self didChangeValueForKey:@"isFinished"];
    } else {
        [self willChangeValueForKey:@"isExecuting"];
		[self performSelectorInBackground:@selector(main) withObject:nil];
        isExecuting = YES;
        [self didChangeValueForKey:@"isExecuting"];
    }
}

- (void)main
{
	@try {
		if (scanType == 0) {
			[self runAVInfoScan];
		} else if (scanType == 1) {
			[self runAVInfoScanAndDefsUpdate];
		}
	}
	@catch (NSException * e) {
		logit(lcl_vError,@"[NSException]: %@",e);
	}
	[self finish];
}

- (void)runAVInfoScan
{
	@autoreleasepool {
		logit(lcl_vInfo,@"Running client AV scan.");
		NSString *appPath = [MP_ROOT_CLIENT stringByAppendingPathComponent:@"MPAgentExec"];
		
		if (![fm fileExistsAtPath:appPath]) {
			logit(lcl_vError,@"Unable to find MPAgentExec app.");
		} else {
            NSError *err = nil;
            MPCodeSign *cs = [[MPCodeSign alloc] init];
            BOOL result = [cs verifyAppleDevBinary:appPath error:&err];
            if (err) {
                logit(lcl_vError,@"%ld: %@",err.code,err.localizedDescription);
            }
            cs = nil;
            if (result == YES)
            {
				NSError *error = nil;
				NSString *result;
				MPNSTask *mpr = [[MPNSTask alloc] init];
				result = [mpr runTask:appPath binArgs:[NSArray arrayWithObjects:@"-a", nil] error:&error];
				
				if (error) {
					logit(lcl_vError,@"%@",[error description]);
				}
				
				logit(lcl_vDebug,@"%@",result);
				logit(lcl_vInfo,@"AV info collection has been completed.");
			}
		}	
	}
}

- (void)runAVInfoScanAndDefsUpdate
{
	@autoreleasepool {
		logit(lcl_vInfo,@"Running client AV scan and update.");
		NSString *appPath = [MP_ROOT_CLIENT stringByAppendingPathComponent:@"MPAgentExec"];
		
		if (![fm fileExistsAtPath:appPath]) {
			logit(lcl_vError,@"Unable to find MPAgentExec app.");
		}

        NSError *err = nil;
        MPCodeSign *cs = [[MPCodeSign alloc] init];
        BOOL result = [cs verifyAppleDevBinary:appPath error:&err];
        if (err) {
            logit(lcl_vError,@"%ld: %@",err.code,err.localizedDescription);
        }
        cs = nil;
        if (result == YES)
		{
			NSError *error = nil;
			NSString *result;
			MPNSTask *mpr = [[MPNSTask alloc] init];
			result = [mpr runTask:appPath binArgs:[NSArray arrayWithObjects:@"-U", nil] error:&error];
			
			if (error) {
				logit(lcl_vError,@"%@",[error description]);
			}
			
			logit(lcl_vDebug,@"%@",result);
			logit(lcl_vInfo,@"AV inventory and defs update has been completed.");
		}	
	}
}

- (int)runAVDefsUpdate
{
    return 0;
}

- (void)killTaskUsingPID
{
    NSError *err = nil;
    // If File Does Not Exists, not PID to kill
    if (![fm fileExistsAtPath:self.taskFile]) {
        return;
    } else {
        NSString *strPID = [NSString stringWithContentsOfFile:self.taskFile encoding:NSUTF8StringEncoding error:&err];
        if (err) {
            logit(lcl_vError,@"%ld: %@",err.code,err.localizedDescription);
        }
        if ([strPID intValue] > 0) {
            [self setTaskPID:[strPID intValue]];
        }
    }
    
    if (self.taskPID == -99) {
        logit(lcl_vWarning,@"No task PID was defined");
        return;
    }
    
    // Make Sure it's running before we send a SIGKILL
    NSArray *procArr = [MPSystemInfo bsdProcessList];
    NSArray *filtered = [procArr filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"processID == %i", self.taskPID]];
    if ([filtered count] <= 0) {
        return;
    } else if ([filtered count] == 1 ) {
        kill( self.taskPID, SIGKILL );
    } else {
        logit(lcl_vError,@"Can not kill task using PID. Found to many using the predicate.");
        logit(lcl_vDebug,@"%@",filtered);
    }
}

@end
