//
//  AgentController.m
/*
 Copyright (c) 2021, Lawrence Livermore National Security, LLC.
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

#import "AgentController.h"
#import "MPAgent.h"
#import "MPTasks.h"
#import "MPTaskValidate.h"
#import "MPOperation.h"

// Operations
#import "ClientCheckInOperation.h"
#import "AgentScanAndUpdateOperation.h"
#import "AntiVirusScanAndUpdateOperation.h"
#import "InventoryOperation.h"
#import	"PatchScanAndUpdateOperation.h"
#import "MPSWDistTaskOperation.h"
#import "Profiles.h"
#import "PostFailedWSRequests.h"

#import "CheckIn.h"
#import "MPAgentUpdater.h"

@interface AgentController ()
{
    NSOperationQueue                *queue;
    MPSettings                      *settings;

    ClientCheckInOperation          *clientOp;
    AgentScanAndUpdateOperation     *agentOp;
    AntiVirusScanAndUpdateOperation *avOp;
    InventoryOperation              *invOp;
    PatchScanAndUpdateOperation     *patchOp;
    MPSWDistTaskOperation           *swDistOp;
    Profiles                        *profilesOp;
    PostFailedWSRequests            *postFailedWSRequestsOp;
	
	NSThread 						*checkInThread;
}

@property NSSet          *tasksSet;
@property NSMutableArray *tasksArray;
@property NSString       *tasksRev;
@property NSDate         *settingsFileDate;

@property NSUInteger	checkInInterval;
@property NSUInteger	updaterInterval;

@end

@implementation AgentController

@synthesize iLoadMode;
@synthesize forceRun;
@synthesize checkInInterval;
@synthesize updaterInterval;

- (id)init 
{
    self = [super init];
    if (self)
    {
        queue = [[NSOperationQueue alloc] init];
        [queue setMaxConcurrentOperationCount:1];
        settings = [MPSettings sharedInstance];
		iLoadMode = NO;
		forceRun = NO;
		
		checkInInterval = 300;
		updaterInterval = 3600;
    }
    return self;
}

- (void)runWithType:(int)aArg
{
	[self runWithType:aArg typeInput:NULL];
}

- (void)runWithType:(int)aArg typeInput:(NSString *)typeData
{
    switch (aArg)
    {
        case 0:
            // Run as daemon
            [self runAsDaemon];
            break;
        case 1:
            // Run client checkin
            [self runClientCheckIn];
            break;
        case 2:
            // Run Inventory Collection
            [self runInventoryCollection];
            break;
        case 3:
            // Run PatchScan
            [self runPatchScan];
            break;
        case 4:
            [self runPatchScanAndUpdate];
            break;
        case 5:
            [self runAVInfoScan];
            break;
        case 6:
            [self runAVInfoScanAndDefsUpdate];
            break;
        case 7:
            [self scanAndUpdateAgentUpdater];
            break;
        case 8:
            [self runSWDistScanAndInstall];
            break;
        case 9:
            [self runProfilesScanAndInstall];
            break;
        case 10:
            [self runGetServerListOperation];
            break;
        case 11:
            [self runPostFailedWSRequests];
            break;
        case 13:
            [self runGetSUServerListOperation];
            break;
        case 8888:
            [self authRestartCheck];
            break;
        case 99:
            // Run as daemon
            [self runAsDaemon];
            break;	
        default:
            // Run as daemon
            [self runAsDaemon];
            break;
    }
}

// Updated for MP 3.1
- (void)runAsDaemon
{
    logit(lcl_vDebug,@"Run as daemon.");
    [NSThread detachNewThreadSelector:@selector(watchSettingsForChanges:) toTarget:self withObject:MP_AGENT_SETTINGS];
    [NSThread detachNewThreadSelector:@selector(loadTasksAndWatchForChanges) toTarget:self withObject:nil];
	[NSThread detachNewThreadSelector:@selector(clientCheckInMethod) toTarget:self withObject:nil];
	[NSThread detachNewThreadSelector:@selector(agentUpdaterMethod) toTarget:self withObject:nil];
    [NSThread detachNewThreadSelector:@selector(runTasksLoop) toTarget:self withObject:nil];
    [[NSRunLoop currentRunLoop] run];
}

// New MP 3.1
- (void)loadTasksAndWatchForChanges
{
    @autoreleasepool
    {
        [settings refresh];
        logit(lcl_vInfo,@"Client ID: %@",[settings ccuid]);
        
        MPTasks *mpTask = [[MPTasks alloc] init];
        _tasksArray = [[mpTask setNextRunForTasks:settings.tasks] mutableCopy];
        _tasksSet = [NSSet setWithArray:_tasksArray]; // Initial Task Hash
    }
}

// New MP 3.1
- (void)updateChangedTasks
{
    [NSThread sleepForTimeInterval:2.0]; // Add small delay so that the atomic write can happen on settings file
    [settings refresh];
    
    MPTasks *mpTask = [[MPTasks alloc] init];
    NSMutableArray *newTasksArray = [[mpTask setNextRunForTasks:settings.tasks] mutableCopy];
    
    NSSet *newTasksSet = [NSSet setWithArray:newTasksArray];
    if (![self.tasksSet isEqual:newTasksSet]) // If they dont match
    {
        self.tasksArray = newTasksArray;
        self.tasksSet = newTasksSet;
    }
}

// New MP 3.1
- (void)watchSettingsForChanges:(NSString *)path
{
    @autoreleasepool
    {
        qlinfo(@"Watching %@ for changes.",path.lastPathComponent);
        
        dispatch_queue_t _watchQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
        int filedes = open([path UTF8String], O_EVTONLY);
        
        __block typeof(self) blockSelf = self;
        __block dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, filedes,
                                                                  DISPATCH_VNODE_DELETE | DISPATCH_VNODE_WRITE | DISPATCH_VNODE_EXTEND |
                                                                  DISPATCH_VNODE_ATTRIB | DISPATCH_VNODE_LINK | DISPATCH_VNODE_RENAME |
                                                                  DISPATCH_VNODE_REVOKE, _watchQueue);
        dispatch_source_set_event_handler(source, ^{
            unsigned long flags = dispatch_source_get_data(source);
            if(flags & DISPATCH_VNODE_DELETE)
            {
                dispatch_source_cancel(source);
                //
                // DO WHAT YOU NEED HERE
                qlinfo(@"%@ has changes. Updating changed tasks.",path.lastPathComponent);
                [self updateChangedTasks];
                
                [blockSelf watchSettingsForChanges:path];
            }
        });
        dispatch_source_set_cancel_handler(source, ^(void) {
            close(filedes);
        });
        dispatch_resume(source);
    }
}

// Updated for MP 3.1
- (void)runTasksLoop
{
    @autoreleasepool
    {
		qlinfo(@"Waiting for tasks...");
		while (self.tasksArray.count <= 0)
		{
			[NSThread sleepForTimeInterval:1.0];
		}
		
        qlinfo(@"Starting tasks...");
        NSDate *d;
        MPTaskValidate *taskValid = [[MPTaskValidate alloc] init];
		BOOL firstRun = YES;
        BOOL keepRunning = YES;
        while (keepRunning)
        {
            @autoreleasepool
            {
                //@try
                //{                    
                    NSDictionary *taskDict;
                    NSTimeInterval _now = 0;
                    // Need to begin loop for tasks
                    for (taskDict in self.tasksArray)
                    {
                        // If task is Active
                        if ([[taskDict objectForKey:@"active"] isEqualToString:@"1"])
                        {
                            _now = [[NSDate now] timeIntervalSince1970];
							/*
							qlinfo(@"taskDict date: %@",[NSDate date]);
							qlinfo(@"taskDict now: %0.0f",_now);
							qlinfo(@"taskDict next: %0.0f",[taskDict[@"nextrun"] doubleValue]);
							qlinfo(@"taskDict: %0.0f [%@][now] >: %0.0f [%@][startdate]", _now,[NSDate now], [[NSDate shortDateFromString:taskDict[@"startdate"]] timeIntervalSince1970],taskDict[@"startdate"]);
                            qlinfo(@"taskDict %0.0f [now] <: %0.0f [enddate]", _now, [[NSDate shortDateFromString:taskDict[@"enddate"]] timeIntervalSince1970]);
							qlinfo(@"%@",[NSTimeZone localTimeZone]);
							*/

                            if ( _now > [[NSDate shortDateFromString:taskDict[@"startdate"]] timeIntervalSince1970]
								&& _now < [[NSDate shortDateFromString:taskDict[@"enddate"]] timeIntervalSince1970])
                            {
                                // Check if task is valid
                                int isValid = [taskValid validateTask:taskDict];
                                if (isValid != 0)
								{
									qlinfo(@"isValid != 0");
                                    //	1 = Error, replace with default cmd
                                    //	2 = Invalid Interval, we will reset startdate and endate as well
                                    //	3 = End Date has to be updated, due to bug in 10.8 NSDate. NSDate cant be older than 3512-12-31
                                    //	99 = Not a valid command type, should disable it.
                                    
                                    // Need a web service to report this...
                                    qlerror(@"Task %@ is not valid. Can not run this task.",taskDict[@"cmd"]);
                                    
                                    // Update the next run.
                                    [self updateNextRunForTask:taskDict missedTask:NO];
                                    continue;
                                }
                                
                                d = [[NSDate alloc] init]; // Get current date/time
                                // Compare as long value, thus removing the floating point.
								//NSLog(@"[%ld]%ld : %ld",(long)_now,(long)[d timeIntervalSince1970],[taskDict[@"nextrun"] longValue]);
								
								
								if (firstRun)
								{
									// Reschedule, we missed out date
									// Schedule for 30 seconds out
									if ([taskDict[@"cmd"] isEqualToString:@"kMPCheckIn"]) {
										continue;
									} else if ([taskDict[@"cmd"] isEqualToString:@"kMPAgentCheck"]) {
										continue;
                                    } else if ([taskDict[@"cmd"] isEqualToString:@"kMPVulUpdate"]) {
                                        continue;
									} else {
										logit(lcl_vInfo,@"Scheduling first run of task (%@) to run in 30 seconds.",taskDict[@"cmd"]);
										[self updateNextRunForTask:taskDict missedTask:YES];
									}
								}
								// If Equal, run task
                                else if ((long)[d timeIntervalSince1970] == [taskDict[@"nextrun"] longValue])
                                {
                                    if ([queue.operations count] >= 20)
									{
                                        logit(lcl_vError,@"Queue appears to be stuck with %lu waiting in queue. Purging queue now.",[queue.operations count]);
                                        [queue cancelAllOperations];
                                        [queue waitUntilAllOperationsAreFinished];
                                    }
									
									BOOL taskInQueue = NO;
									for (MPOperation *o in queue.operations)
									{
										if ([o.taskName isEqualToString:taskDict[@"cmd"]]) {
											qlinfo(@"Task %@ already waiting in queue.",o.taskName);
											taskInQueue = YES;
											break;
										}
									}
									
                                    if (taskInQueue)
									{
										continue;
									}
									
									if (![taskDict[@"cmd"] isEqualToString:@"kMPCheckIn"] && ![taskDict[@"cmd"] isEqualToString:@"kMPAgentCheck"]) {
										logit(lcl_vInfo,@"Run task (%@) via queue (%lu).",taskDict[@"cmd"],[queue.operations count]);
									}
									
									if ([taskDict[@"cmd"] isEqualToString:@"kMPCheckIn"])
									{
										/* Moved to seperate thread
										clientOp = [[ClientCheckInOperation alloc] init];
										clientOp.taskName = @"kMPCheckIn";
										[queue addOperation:clientOp];
										clientOp = nil;
										 */
									}
									else if ([taskDict[@"cmd"] isEqualToString:@"kMPAgentCheck"])
									{
										/* Moved to seperate thread
										agentOp = [[AgentScanAndUpdateOperation alloc] init];
										agentOp.taskName = @"kMPAgentCheck";
										[queue addOperation:agentOp];
										agentOp = nil;
										 */
									}
									if ([taskDict[@"cmd"] isEqualToString:@"kMPAVInfo"])
									{
										avOp = [[AntiVirusScanAndUpdateOperation alloc] init];
										avOp.taskName = @"kMPAVInfo";
										[avOp setScanType:0];
										[queue addOperation:avOp];
										avOp = nil;
									}
									else if ([taskDict[@"cmd"] isEqualToString:@"kMPAVCheck"])
									{
										avOp = [[AntiVirusScanAndUpdateOperation alloc] init];
										avOp.taskName = @"kMPAVCheck";
										[avOp setScanType:1];
										[queue addOperation:avOp];
										avOp = nil;
									}
									else if ([taskDict[@"cmd"] isEqualToString:@"kMPInvScan"])
									{
										@autoreleasepool
										{
											InventoryOperation __autoreleasing *invOps = [[InventoryOperation alloc] init];
											invOps.queuePriority = NSOperationQueuePriorityLow;
											if (floor(NSAppKitVersionNumber) >= NSAppKitVersionNumber10_10)
											{
												NSOperatingSystemVersion version = [[NSProcessInfo processInfo] operatingSystemVersion];
												if (version.minorVersion >= 10)
												{
													invOps.qualityOfService = NSOperationQualityOfServiceBackground;
												}
											}
											invOps.taskName = @"kMPInvScan";
											[queue addOperation:invOps];
											invOps = nil;
										}
									}
									else if ([taskDict[@"cmd"] isEqualToString:@"kMPVulScan"])
									{
										patchOp = [[PatchScanAndUpdateOperation alloc] init];
										patchOp.taskName = @"kMPVulScan";
										[queue addOperation:patchOp];
										patchOp = nil;
									}
									else if ([taskDict[@"cmd"] isEqualToString:@"kMPVulUpdate"])
									{
										MPPatching *p = [MPPatching new];
										if (![p patchingForHostIsPaused])
										{
											patchOp = [[PatchScanAndUpdateOperation alloc] init];
											patchOp.taskName = @"kMPVulUpdate";
											[patchOp setScanType:1];
											[queue addOperation:patchOp];
											patchOp = nil;
										}
										p = nil;
									}
									else if ([taskDict[@"cmd"] isEqualToString:@"kMPSWDistMan"])
									{
										swDistOp = [[MPSWDistTaskOperation alloc] init];
										swDistOp.taskName = @"kMPSWDistMan";
										[queue addOperation:swDistOp];
										swDistOp = nil;
									}
									else if ([taskDict[@"cmd"] isEqualToString:@"kMPProfiles"])
									{
										profilesOp = [[Profiles alloc] init];
										profilesOp.taskName = @"kMPProfiles";
										[queue addOperation:profilesOp];
										profilesOp = nil;
									}
									else if ([taskDict[@"cmd"] isEqualToString:@"kMPWSPost"])
									{
										postFailedWSRequestsOp = [[PostFailedWSRequests alloc] init];
										postFailedWSRequestsOp.taskName = @"kMPWSPost";
										[queue addOperation:postFailedWSRequestsOp];
										postFailedWSRequestsOp = nil;
									}
									else if ([taskDict[@"cmd"] isEqualToString:@"kMPPatchCrit"])
									{
										patchOp = [[PatchScanAndUpdateOperation alloc] init];
										patchOp.taskName = @"kMPPatchCrit";
										[patchOp setScanType:1];
										[queue addOperation:patchOp];
										patchOp = nil;
									}
									
									// Set Next Run Date Time
									[self updateNextRunForTask:taskDict missedTask:NO];
									
                                    
                                }
								// If time has passed next run
								else if ((long)[d timeIntervalSince1970] > [taskDict[@"nextrun"] longValue])
								{
									if (![taskDict[@"cmd"] isEqualToString:@"kMPVulUpdate"])
									{
										// Reschedule, we missed out date
										// Schedule for 30 seconds out
										logit(lcl_vInfo,@"We missed our task (%@), rescheduled to run in 30 seconds.",taskDict[@"cmd"]);
										[self updateNextRunForTask:taskDict missedTask:YES];
									} else {
										[self updateNextRunForTask:taskDict missedTask:NO];
									}
                                }
                                d = nil;
                            }
                        }
                    }
					if (firstRun) firstRun = NO;
               // }
               // @catch (NSException *exception) {
               //     qlerror(@"%@",exception);
               // }
            }
            sleep(1);
        }
    }
}

// New MP 3.1
// Used to be run from MPTask class
- (void)updateNextRunForTask:(NSDictionary *)task missedTask:(BOOL)wasMissed
{
    NSMutableArray *tasksArrayCopy = [self.tasksArray mutableCopy];
    NSDictionary *t = [self taskWithNewRunDate:task missed:wasMissed];
    [tasksArrayCopy replaceObjectAtIndex:[self.tasksArray indexOfObject:task] withObject:t];
    self.tasksArray = tasksArrayCopy;
}

// New MP 3.1
// Used to be run from MPTask class
- (NSDictionary *)taskWithNewRunDate:(NSDictionary *)aTask missed:(BOOL)wasMissed
{
    NSString *intervalStr = 0;
    double next_run = 0;
    NSMutableDictionary *_task = [[NSMutableDictionary alloc] initWithDictionary:aTask];
    
    if (wasMissed)
    {
        next_run = (double)[[NSDate now] timeIntervalSince1970];
        next_run = next_run + 30.0;
    }
    else
    {
        /* Once@Time; Recurring@Daily,Weekly,Monthly@Time;Every@seconds */
        
        NSArray *intervalArray = [[_task objectForKey:@"interval"] componentsSeparatedByString:@"@"];
        if ([[[intervalArray objectAtIndex:0] uppercaseString] isEqualToString:@"EVERY"])
        {
            intervalStr = [intervalArray objectAtIndex:1];
            next_run = [[_task objectForKey:@"nextrun"] doubleValue] + [[intervalArray objectAtIndex:1] intValue];
        }
        else if ([[[intervalArray objectAtIndex:0] uppercaseString] isEqualToString:@"EVERYRAND"])
        {
            int r = arc4random() % [[intervalArray objectAtIndex:1] intValue];
			intervalStr = [NSString stringWithFormat:@"%d",r];
            next_run = [[_task objectForKey:@"nextrun"] doubleValue] + r;
        }
        else if ([[[intervalArray objectAtIndex:0] uppercaseString] isEqualToString:@"RECURRING"])
        {
            if ([[[intervalArray objectAtIndex:1] uppercaseString] isEqualToString:@"DAILY"])
            {
                next_run = [[NSDate addDayToInterval:[[_task objectForKey:@"nextrun"] doubleValue]] timeIntervalSince1970];
            }
            else if ([[[intervalArray objectAtIndex:1] uppercaseString] isEqualToString:@"WEEKLY"])
            {
                next_run = [[NSDate addWeekToInterval:[[_task objectForKey:@"nextrun"] doubleValue]] timeIntervalSince1970];
            }
            else if ([[[intervalArray objectAtIndex:1] uppercaseString] isEqualToString:@"MONTHLY"])
            {
                next_run = [[NSDate addMonthToInterval:[[_task objectForKey:@"nextrun"] doubleValue]] timeIntervalSince1970];
            }
        }
        else if ([[[intervalArray objectAtIndex:0] uppercaseString] isEqualToString:@"ONCE"])
        {
            next_run = [[_task objectForKey:@"nextrun"] doubleValue]; // Leave the value as is
            if ([[_task objectForKey:@"nextrun"] doubleValue] < [[NSDate date] timeIntervalSince1970])
            {
                [_task setObject:@"0" forKey:@"active"]; // Disable the task
            }
        }
    }
    
    [_task setObject:[NSNumber numberWithDouble:next_run] forKey:@"nextrun"];
    NSString *nextRun = [[NSDate dateWithTimeIntervalSince1970:next_run] descriptionWithCalendarFormat:@"%Y-%m-%d %H:%M:%S %z" timeZone:[NSTimeZone localTimeZone] locale:nil];
    if ([[aTask objectForKey:@"active"] isEqualTo:@"1"]) {
        logit(lcl_vInfo,@"%@ next run at %@",_task[@"name"],nextRun);
    } else {
        logit(lcl_vInfo,@"%@ next run at %@ (DISABLED TASK)",_task[@"name"],nextRun);
    }
    return [(NSDictionary *)_task copy];
}

#pragma mark - Single Methods
-(void)runClientCheckIn
{
    clientOp = [[ClientCheckInOperation alloc] init];
    [queue addOperation:clientOp];
    clientOp = nil;

    if ([NSThread isMainThread]) {
        while ([[queue operations] count] > 0) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
        }
    } else {
        [queue waitUntilAllOperationsAreFinished];
    }

	exit(0);
}

-(void)runInventoryCollection
{
    invOp = [[InventoryOperation alloc] init];
    [queue addOperation:invOp];
    invOp = nil;
    
    if ([NSThread isMainThread]) {
        while ([[queue operations] count] > 0) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
        }
    } else {
        [queue waitUntilAllOperationsAreFinished];
    }
    
	exit(0);
}

-(void)runPatchScan
{
	return [self runPatchScan:kAllPatches forceRun:NO];
}

- (void)runPatchScan:(MPPatchContentType)contentType forceRun:(BOOL)aForceRun
{
	patchOp = [[PatchScanAndUpdateOperation alloc] init];
	[patchOp setScanType:0];
	[patchOp setPatchFilter:contentType];
	[patchOp setForceRun:aForceRun];
	if (iLoadMode) [patchOp setILoadMode:iLoadMode];
	[queue addOperation:patchOp];
	patchOp = nil;
	
	if ([NSThread isMainThread]) {
		while ([[queue operations] count] > 0) {
			[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
		}
	} else {
		[queue waitUntilAllOperationsAreFinished];
	}
	
	exit(0);
}

- (void)runPatchScanAndUpdate
{
	return [self runPatchScanAndUpdate:kAllPatches bundleID:NULL];
}

- (void)runPatchScanAndUpdate:(MPPatchContentType)contentType bundleID:(NSString *)bundleID
{
	patchOp = [[PatchScanAndUpdateOperation alloc] init];
	[patchOp setScanType:1];
	[patchOp setPatchFilter:contentType];
	[patchOp setBundleID:bundleID];
	[patchOp setForceRun:forceRun];
	if (iLoadMode) [patchOp setILoadMode:iLoadMode];
	[queue addOperation:patchOp];
	patchOp = nil;
	
	if ([NSThread isMainThread]) {
		while ([[queue operations] count] > 0) {
			[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
		}
	} else {
		[queue waitUntilAllOperationsAreFinished];
	}
	
	exit(0);
}

-(void)runCritialPatchScanAndUpdate
{
    patchOp = [[PatchScanAndUpdateOperation alloc] init];
    [patchOp setScanType:2];
    [queue addOperation:agentOp];
    patchOp = nil;
    
    if ([NSThread isMainThread]) {
        while ([[queue operations] count] > 0) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
        }
    } else {
        [queue waitUntilAllOperationsAreFinished];
    }
    
    exit(0);
}

- (void)runAVInfoScan
{
    avOp = [[AntiVirusScanAndUpdateOperation alloc] init];
    [avOp setScanType:0];
    [queue addOperation:avOp];
    avOp = nil;
    
    if ([NSThread isMainThread]) {
        while ([[queue operations] count] > 0) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
        }
    } else {
        [queue waitUntilAllOperationsAreFinished];
    }
    
	exit(0);
}

- (void)runAVInfoScanAndDefsUpdate
{
    avOp = [[AntiVirusScanAndUpdateOperation alloc] init];
    [avOp setScanType:1];
    [queue addOperation:avOp];
    avOp = nil;
    
    if ([NSThread isMainThread]) {
        while ([[queue operations] count] > 0) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
        }
    } else {
        [queue waitUntilAllOperationsAreFinished];
    }
    
	exit(0);
}

-(void)scanAndUpdateAgentUpdater
{
    agentOp = [[AgentScanAndUpdateOperation alloc] init];
    [queue addOperation:agentOp];
    agentOp = nil;
    
    if ([NSThread isMainThread]) {
        while ([[queue operations] count] > 0) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
        }
    } else {
        [queue waitUntilAllOperationsAreFinished];
    }
    
    exit(0);
}

- (void)runSWDistScanAndInstall
{
    swDistOp = [[MPSWDistTaskOperation alloc] init];
    [queue addOperation:swDistOp];
    swDistOp = nil;

    if ([NSThread isMainThread]) {
        while ([[queue operations] count] > 0) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
        }
    } else {
        [queue waitUntilAllOperationsAreFinished];
    }

    exit(0);
}

- (void)runProfilesScanAndInstall
{
    profilesOp = [[Profiles alloc] init];
    [queue addOperation:profilesOp];
    profilesOp = nil;

    if ([NSThread isMainThread]) {
        while ([[queue operations] count] > 0) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
        }
    } else {
        [queue waitUntilAllOperationsAreFinished];
    }

    exit(0);
}

- (void)runGetServerListOperation
{
    /*
    serverListOp = [[GetServerListOperation alloc] init];
    [queue addOperation:serverListOp];
    serverListOp = nil;

    if ([NSThread isMainThread]) {
        while ([[queue operations] count] > 0) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
        }
    } else {
        [queue waitUntilAllOperationsAreFinished];
    }
     */
    exit(0);
}

- (void)runPostFailedWSRequests
{
    postFailedWSRequestsOp = [[PostFailedWSRequests alloc] init];
    [queue addOperation:postFailedWSRequestsOp];
    postFailedWSRequestsOp = nil;

    if ([NSThread isMainThread]) {
        while ([[queue operations] count] > 0) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
        }
    } else {
        [queue waitUntilAllOperationsAreFinished];
    }

    exit(0);
}

- (void)runGetSUServerListOperation
{
    /*
    suServerListOp = [[GetASUSListOperation alloc] init];
    [queue addOperation:suServerListOp];
    suServerListOp = nil;
    
    if ([NSThread isMainThread]) {
        while ([[queue operations] count] > 0) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
        }
    } else {
        [queue waitUntilAllOperationsAreFinished];
    }
    */
    exit(0);
}

#pragma mark - Check In Thread - NEW

- (NSUInteger)clientCheckInInterval
{
	static NSString *settingsPath = @"/Library/Application Support/MacPatch/gov.llnl.mp.plist";
	NSUInteger result = self.checkInInterval;
	if ([[NSFileManager defaultManager] fileExistsAtPath:settingsPath])
	{
		NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:settingsPath];
		NSDictionary *tasksDict = d[@"settings"][@"tasks"];
		if(tasksDict[@"data"])
		{
			NSDictionary *taskData = nil;
			NSArray *tasks = tasksDict[@"data"];
			for (NSDictionary *t in tasks)
			{
				if ([t[@"cmd"] isEqualToString:@"kMPCheckIn"]) {
					taskData = [t copy];
					break;
				}
			}
			
			if (taskData)
			{
				NSString *i = taskData[@"interval"]; // EVERY@300
				NSArray *ia = [i componentsSeparatedByString:@"@"];
				if ([ia[1] intValue]) {
					result = [ia[1] intValue];
				}
			}
		}
	}
	qldebug(@"clientCheckInInterval: %lu",(unsigned long)result);
	return result;
}

- (void)clientCheckInMethod
{
	@autoreleasepool
	{
		NSUInteger xCheckInInterval = 30;
		NSUInteger counter = 0;
		
		BOOL keepRunning = YES;
		while (keepRunning)
		{
			// Every 30 Seconds Check to see if the tasks plist has been updated.
			if (counter >= xCheckInInterval)
			{
				counter = 0;
				xCheckInInterval = [self clientCheckInInterval];
				// Run CheckIn
				logit(lcl_vInfo,@"Tasks have been changed, reading in changes.");
				CheckIn *ci = [CheckIn new];
				NSLock *lock = [NSLock new];
				[lock lock];
				[ci runClientCheckIn];
				[lock unlock];
				ci = nil;
				
				NSDate *d = [[NSDate now] dateByAddingTimeInterval:xCheckInInterval];
				NSString *nextRun = [d descriptionWithCalendarFormat:@"%Y-%m-%d %H:%M:%S %z" timeZone:[NSTimeZone localTimeZone] locale:nil];
				qlinfo(@"Next client checkin scheduled for %@",nextRun);
			}
			sleep(1);
			counter++;
		}
	}
}

- (NSUInteger)updateAgentUpdaterInterval
{
	static NSString *settingsPath = @"/Library/Application Support/MacPatch/gov.llnl.mp.plist";
	NSUInteger result = self.checkInInterval;
	if ([[NSFileManager defaultManager] fileExistsAtPath:settingsPath])
	{
		NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:settingsPath];
		NSDictionary *tasksDict = d[@"settings"][@"tasks"];
		if(tasksDict[@"data"])
		{
			NSDictionary *taskData = nil;
			NSArray *tasks = tasksDict[@"data"];
			for (NSDictionary *t in tasks)
			{
				if ([t[@"cmd"] isEqualToString:@"kMPAgentCheck"]) {
					taskData = [t copy];
					break;
				}
			}
			
			if (taskData)
			{
				NSString *i = taskData[@"interval"]; // EVERY@300
				NSArray *ia = [i componentsSeparatedByString:@"@"];
				if ([ia[1] intValue]) { // Make sure value is a int
					result = [ia[1] intValue];
				}
			}
		}
	}
	return result;
}

- (void)agentUpdaterMethod
{
	@autoreleasepool
	{
		NSUInteger xInterval = 120;
		NSUInteger counter = 0;
		
		BOOL keepRunning = YES;
		while (keepRunning)
		{
			// Every 30 Seconds Check to see if the tasks plist has been updated.
			if (counter >= xInterval)
			{
				counter = 0;
				xInterval = [self updateAgentUpdaterInterval];
				// Run CheckIn
				logit(lcl_vInfo,@"Running agent updater scan and update.");
				MPAgentUpdater *mpu = [MPAgentUpdater new];
				NSLock *lock = [NSLock new];
				[lock lock];
				[mpu scanAndUpdateAgentUpdater];
				[lock unlock];
				mpu = nil;
				NSDate *d = [[NSDate now] dateByAddingTimeInterval:xInterval];
				//NSString *nextRun = [d descriptionWithCalendarFormat:@"%Y-%m-%d %H:%M:%S %z" timeZone:[NSTimeZone localTimeZone] locale:nil];
				qlinfo(@"Next agent updater scan and update scheduled for %@",d);
			}
			sleep(1);
			counter++;
		}
	}
}

- (void)authRestartCheck
{
    NSError *err = nil;
    BOOL isValid = NO;
    MPFileCheck *fu = [MPFileCheck new];
    if ([fu fExists:MP_AUTHSTATUS_FILE])
    {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:MP_AUTHSTATUS_FILE];
        if ([d[@"enabled"] boolValue])
        {
            [self cliPrint:@"AuthRestart is enabled."];
            
            if ([d[@"useRecovery"] boolValue])
            {
                [self cliPrint:@"AuthRestart is using recovery key."];
                MPSimpleKeychain *kc = [[MPSimpleKeychain alloc] initWithKeychainFile:MP_AUTHSTATUS_KEYCHAIN];
                MPPassItem *pi = [kc retrievePassItemForService:@"mpauthrestart" error:&err];
                if (!err)
                {
                    isValid = [self recoveryKeyIsValid:pi.userPass];
                    [self cliPrint:@"AuthRestart Recovery Key %@ valid.",isValid ? @"is":@"is not"];
                } else {
                    [self cliPrint:@"Error retrieving password item for service."];
                    [self cliPrint:@"Error: %@",err.localizedDescription];
                }
            } else {
                DHCachedPasswordUtil *dh = [DHCachedPasswordUtil new];
                MPSimpleKeychain *kc = [[MPSimpleKeychain alloc] initWithKeychainFile:MP_AUTHSTATUS_KEYCHAIN];
                MPPassItem *pi = [kc retrievePassItemForService:@"mpauthrestart" error:&err];
                if (!err)
                {
                    isValid = [dh checkPassword:pi.userPass forUserWithName:pi.userName];
                    [self cliPrint:@"AuthRestart UserName and Password %@ valid.",isValid ? @"is":@"is not"];
                } else {
                    [self cliPrint:@"Error retrieving password item for service."];
                    [self cliPrint:@"Error: %@",err.localizedDescription];
                }
            }
        } else {
            [self cliPrint:@"AuthRestart is not enabled."];
        }
    }
}

- (BOOL)recoveryKeyIsValid:(NSString *)rKey
{
    BOOL isValid = NO;

    NSString *script = [NSString stringWithFormat:@"#!/bin/bash \n"
    "/usr/bin/expect -f- << EOT \n"
    "spawn /usr/bin/fdesetup validaterecovery; \n"
    "expect \"Enter the current recovery key:*\" \n"
    "send -- %@ \n"
    "send -- \"\\r\" \n"
    "expect \"true\" \n"
    "expect eof; \n"
    "EOT",rKey];
    
    MPScript *mps = [MPScript new];
    NSString *res = [mps runScriptReturningResult:script];
    // Now Look for our result ...
    NSArray *arr = [res componentsSeparatedByString:@"\n"];
    for (NSString *l in arr) {
        if ([l containsString:@"fdesetup"]) {
            continue;
        }
        if ([l containsString:@"Enter the "]) {
            continue;
        }
        if ([[l trim] isEqualToString:@"false"]) {
            isValid = NO;
            break;
        }
        if ([[l trim] isEqualToString:@"true"]) {
            isValid = YES;
            break;
        }
    }

    return isValid;
}

- (void)cliPrint:(NSString *)text,...
{
    @try {
        va_list args;
        va_start(args, text);
        NSString *textStr = [[NSString alloc] initWithFormat:text arguments:args];
        va_end(args);
        
        printf("%s\n", [textStr cStringUsingEncoding:[NSString defaultCStringEncoding]]);
    }
    @catch (NSException *exception) {
        qlerror(@"%@",exception);
    }
}

#pragma mark - Provisioning

- (int)provisionSetupAndConfig
{
    int result = 1;
    NSArray *provCriteria = [NSArray array];
    NSError *err = nil;
    
    MPRESTfull *mpr = [MPRESTfull new];
    provCriteria = [mpr getProvisioningCriteriaUsingScope:@"prod" error:&err];
    if (err) {
        qlerror(@"Error downloading provisioning criteria.");
        qlerror(@"%@",err.localizedDescription);
    } else {
        if (provCriteria.count >= 1)
        {
            MPBundle    *mpbndl;
            MPFileCheck *mpfile;
            MPScript    *mpscript;
            
            int count = 0; // Copunt must equal the array length for all to be true.
            // Loop vars
            /*
             typeQuery       = [qryArr objectAtIndex:1];
             typeQueryString = [qryArr objectAtIndex:2];
             typeResult      = [qryArr objectAtIndex:3];
             */
            
            for (NSDictionary *q in provCriteria)
            {
                qldebug(@"Process %@",q);
                NSArray *qryArr = [[q objectForKey:@"qstr"] componentsSeparatedByString:@"@" escapeString:@"@@"];
                qldebug(@"qryArr %@",qryArr);
                
                if ([@"BundleID" isEqualToString:[qryArr objectAtIndex:0]]) {
                    mpbndl = [[MPBundle alloc] init];
                    if ([qryArr count] != 4) {
                        qlerror(@"Error, not enough args for BundleID criteria query.");
                        continue;
                    }

                    if ([mpbndl queryBundleID:[qryArr objectAtIndex:2] action:[qryArr objectAtIndex:1] result:[qryArr objectAtIndex:3]]) {
                        qlinfo(@"BundleID=TRUE: %@",[qryArr objectAtIndex:1]);
                        count++;
                    } else {
                        qlinfo(@"BundleID=FALSE: %@",[qryArr objectAtIndex:1]);
                    }
                }
                
                if ([@"File" isEqualToString:[qryArr objectAtIndex:0]]) {
                    mpfile = [[MPFileCheck alloc] init];
                    if ([qryArr count] != 4) {
                        qlerror(@"Error, not enough args for File criteria query.");
                        continue;
                    }

                    if ([mpfile queryFile:[qryArr objectAtIndex:2] action:[qryArr objectAtIndex:1] param:[qryArr objectAtIndex:3]]) {
                        qlinfo(@"File=TRUE: %@",[qryArr objectAtIndex:1]);
                        count++;
                    } else {
                        qlinfo(@"File=FALSE: %@",[qryArr objectAtIndex:1]);
                    }
                }
                
                if ([@"Script" isEqualToString:[qryArr objectAtIndex:0]]) {
                    mpscript = [[MPScript alloc] init];
                    if ([qryArr count] > 2) {
                        qlerror(@"Error, too many args. Sript will not be run.");
                        continue;
                    }
                    NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:[qryArr objectAtIndex:1] options:0];
                    NSString *decodedString = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
                    qldebug(@"Script: %@",decodedString);
                    if ([mpscript runScript:decodedString]) {
                        qlinfo(@"SCRIPT=TRUE");
                        count++;
                    } else {
                        qlinfo(@"SCRIPT=FALSE");
                    }
                }
            }
            qldebug(@"provCriteria.count %d == %d count",provCriteria.count,count);
            if (provCriteria.count == count)
            {
                // Criteria is a pass, write .MPProvisionBegin file
                err = nil;
                [@"GO" writeToFile:MP_PROVISION_BEGIN atomically:NO encoding:NSUTF8StringEncoding error:&err];
                if (err) {
                    qlerror(@"Error writing %@ file.",MP_PROVISION_BEGIN);
                    qlerror(@"%@",err.localizedDescription);
                }
            }
        }
    }
    
    // This can be downloaded any time
    result = [self getProvisioningConfig];
    return result;
    
}

- (int)getProvisioningConfig
{
    NSString *configJSON = nil;
    NSError *err = nil;
    MPRESTfull *mpr = [MPRESTfull new];
    configJSON = [mpr getProvisioningConfig:&err];
    if (err) {
        qlerror(@"Error downloading provisioning configuration.");
        qlerror(@"%@",err.localizedDescription);
        return 1;
    }
    
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir;
    BOOL exists = [fm fileExistsAtPath:MP_PROVISION_DIR isDirectory:&isDir];
    if (exists) {
        /* file exists */
        if (!isDir) {
            qlerror(@"Error, %@ exists but is not a directory.",MP_PROVISION_DIR);
            qlerror(@"%@",err.localizedDescription);
            return 1;
        } else {
            // if config exists, remove so we can write a new one
            if ([fm fileExistsAtPath:MP_PROVISION_DATA_FILE])
            {
                [fm removeItemAtPath:MP_PROVISION_DATA_FILE error:&err]; // File exists, remove it
                if (err) {
                    qlerror(@"Error, unable to remove existsing %@ file.",[MP_PROVISION_DATA_FILE lastPathComponent]);
                    qlerror(@"%@",err.localizedDescription);
                    return 1;
                }
            }
            
            // Write new config file
            [configJSON writeToFile:MP_PROVISION_DATA_FILE atomically:NO encoding:NSUTF8StringEncoding error:&err];
            if (err) {
                qlerror(@"Error writing provisioning configuration to disk.");
                qlerror(@"%@",err.localizedDescription);
            }
            
            qldebug(@"%@",configJSON);
        }
    } else {
        [fm createDirectoryRecursivelyAtPath:MP_PROVISION_DIR];
        [configJSON writeToFile:MP_PROVISION_DATA_FILE atomically:NO encoding:NSUTF8StringEncoding error:&err];
        if (err) {
            qlerror(@"Error writing provisioning configuration to disk.");
            qlerror(@"%@",err.localizedDescription);
            return 1;
        }
        qldebug(@"%@",configJSON);
    }
    
    return 0;
}

@end
