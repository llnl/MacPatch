//
//  AntiVirusScanAndUpdateOperation.m
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

#import "AntiVirusScanAndUpdateOperation.h"
#import "MPAgent.h"
#import "MacPatch.h"
#import "AntiVirus.h"

static NSString * const _taskRunFile = @"/tmp/.mpAVUpdateRunning";

@interface AntiVirusScanAndUpdateOperation (Private)

@property (nonatomic, readwrite) NSString *taskFile;

- (void)runAVInfoScan;
- (void)runAVInfoScanAndDefsUpdate;
- (int)runAVDefsUpdate;

@end

@implementation AntiVirusScanAndUpdateOperation

@synthesize forceRun;
@synthesize scanType;
@synthesize taskPID;
@synthesize taskFile;

- (id)init
{
	self = [super init];
	if (self)
	{
		scanType = 0;
        taskPID = -99;
		self.isExecuting = NO;
        self.isFinished  = NO;
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
    self.isExecuting = NO;
    self.isFinished = YES;
    [self didChangeValueForKey:@"isExecuting"];
    [self didChangeValueForKey:@"isFinished"];

    [self killTask];
}

- (void)start 
{
    if ([self isCancelled]) {
        [self willChangeValueForKey:@"isFinished"];
        self.isFinished = YES;
        [self didChangeValueForKey:@"isFinished"];
    } else {
        [self willChangeValueForKey:@"isExecuting"];
		[self performSelectorInBackground:@selector(main) withObject:nil];
        self.isExecuting = YES;
        [self didChangeValueForKey:@"isExecuting"];
    }
}

- (void)main
{
	@try {
		if (scanType == 0) {
			[self runAVscan];
		} else if (scanType == 1) {
			[self runAVscanAndUpdate];
		}
	}
	@catch (NSException * e) {
		logit(lcl_vError,@"[NSException]: %@",e);
	}
	[self finish];
}

- (void)runAVscan
{
	@autoreleasepool
    {
		logit(lcl_vInfo,@"Running client AV scan.");
        
        if ([self isTaskRunning]) {
            logit(lcl_vInfo,@"Scanning for av defs is already running. Now exiting.");
            return;
        } else {
            [self writeTaskRunning];
        }
        
        logit(lcl_vInfo,@"Begin scan for AV defs.");
        AntiVirus *mpav = [[AntiVirus alloc] init];
        [mpav scanDefs];
        mpav = nil;
        
        logit(lcl_vInfo,@"Scan for AV defs complete.");
        [self removeTaskRunning];
	}
}

- (void)runAVscanAndUpdate
{
	@autoreleasepool
    {
        if ([self isTaskRunning]) {
            logit(lcl_vInfo,@"Updating av defs is already running. Now exiting.");
            return;
        } else {
            [self writeTaskRunning];
        }
        
        logit(lcl_vInfo,@"Begin scan and update for AV defs.");
        AntiVirus *mpav = [[AntiVirus alloc] init];
        [mpav scanAndUpdateDefs];
        mpav = nil;
        
        logit(lcl_vInfo,@"Scan and update for AV defs complete.");
        [self removeTaskRunning];
	}
}

- (BOOL)isTaskRunning
{
    if (forceRun == YES) {
        return NO;
    }
    
    NSDate *cdate; // CDate of File
    NSDate *cdatePlus; // CDate of file plus ... hrs
    NSDate *ndate = [NSDate date]; // Now

    if ([fm fileExistsAtPath:_taskRunFile]) {
        cdate = [[fm attributesOfItemAtPath:_taskRunFile error:nil] fileCreationDate];
        cdatePlus = [cdate dateByAddingTimeInterval:14400]; // Add 4 Hours
        NSComparisonResult result = [ndate compare:cdatePlus];
        if( result == NSOrderedAscending ) {
            // cdatePlus is in the future
            return YES;
        } else if(result==NSOrderedDescending) {
            // cdatePlus is in the past
            [self killTask];
            logit(lcl_vError, @"Task file %@ found. File older than 4 hours. Deleting file.",_taskRunFile);
            
            [self removeTaskRunning];
            return NO;
        }
        // Both dates are the same
        return NO;
    }
    
    return NO;
}

-(void)writeTaskRunning
{
    if (forceRun == NO) {
        NSString *_id = [@([[NSProcessInfo processInfo] processIdentifier]) stringValue];
        [_id writeToFile:_taskRunFile atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    }
}

-(void)removeTaskRunning
{
    logit(lcl_vInfo,@"Remove Task Running file %@.",_taskRunFile);
    if ([fm fileExistsAtPath:_taskRunFile]) {
        logit(lcl_vInfo,@"File exists %@",_taskRunFile);
        if (forceRun == NO) {
            logit(lcl_vInfo,@"File remove %@",_taskRunFile);
            NSError *err = nil;
            [fm removeItemAtPath:_taskRunFile error:&err];
            if (err) {
                logit(lcl_vError,@"File remove %@\nError=%@",_taskRunFile,[err description]);
            }
        } else {
            logit(lcl_vInfo,@"Force run is set to true for %@. No file will be removed.",_taskRunFile);
        }
    }
}

- (void)killTask
{
    int _taskPID = -99;
    NSError *err = nil;
    // If File Does Not Exists, not PID to kill
    if (![fm fileExistsAtPath:_taskRunFile]) {
        return;
    } else {
        NSString *strPID = [NSString stringWithContentsOfFile:_taskRunFile encoding:NSUTF8StringEncoding error:&err];
        if (err) {
            logit(lcl_vError,@"%ld: %@",err.code,err.localizedDescription);
        }
        if ([strPID intValue] > 0) {
            _taskPID = [strPID intValue];
        }
    }
    
    if (_taskPID == -99) {
        logit(lcl_vWarning,@"No task PID was defined");
        return;
    }
    
    // Make Sure it's running before we send a SIGKILL
    NSArray *procArr = [MPSystemInfo bsdProcessList];
    NSArray *filtered = [procArr filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"processID == %i", _taskPID]];
    if ([filtered count] <= 0) {
        return;
    } else if ([filtered count] == 1 ) {
        kill( _taskPID, SIGKILL );
    } else {
        logit(lcl_vError,@"Can not kill task using PID. Found to many using the predicate.");
        logit(lcl_vDebug,@"%@",filtered);
    }
}


@end
