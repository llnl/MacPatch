//
//  CheckIn.m
//  MPAgent
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

#import "CheckIn.h"
#import "MPAgent.h"
#import "MacPatch.h"
#import "MPSettings.h"
#import "Software.h"
#import "TaskScheduler.h"
#import <signal.h>

@implementation CheckIn

- (void)runClientCheckIn
{
	// Collect Agent Checkin Data
	MPClientInfo *ci = [[MPClientInfo alloc] init];
	NSDictionary *agentData = [ci agentData];
	if (!agentData)
	{
		LogError(@"Agent data is nil, can not post client checkin data.");
		return;
	}
	
	// Post Client Checkin Data to WS
	NSError *error = nil;
	NSDictionary *revsDict;
	MPRESTfull *rest = [[MPRESTfull alloc] init];
	revsDict = [rest postClientCheckinData:agentData error:&error];
	if (error) {
		LogError(@"Running client check in had an error.");
		LogError(@"%@", error.localizedDescription);
	}
	else
	{
		[self updateGroupSettings:revsDict];
		[self installRequiredSoftware:revsDict];
	}
	
	LogInfo(@"Running client check in completed.");
	return;
}

- (void)updateGroupSettings:(NSDictionary *)settingRevisions
{
	// Query for Revisions
	// Call MPSettings to update if nessasary
	LogInfo(@"Check and Update Agent Settings.");
	//LogInfo(@"Setting Revisions from server: %@", settingRevisions);
    
    
    NSDictionary *local = [NSDictionary dictionaryWithContentsOfFile:MP_AGENT_SETTINGS];
    //LogInfo(@"[updateGroupSettings][local]: %@", local);
    
    NSNumber *currTasksRev = [local valueForKeyPath:@"revs.tasks"];
    NSNumber *newTasksRev = [settingRevisions valueForKeyPath:@"revs.tasks"];
    
    if (!newTasksRev || !currTasksRev) {
        LogInfo(@"Missing revision information");
    } else if ([newTasksRev compare:currTasksRev] == NSOrderedDescending) {
        LogInfo(@"Update available: %@ -> %@", currTasksRev, newTasksRev);
        // Perform update
    } else if ([newTasksRev compare:currTasksRev] == NSOrderedSame) {
        LogInfo(@"Revisions match, no update needed");
    } else {
        LogInfo(@"Local revision is newer");
    }
    
	MPSettings *set = [MPSettings sharedInstance];
	[set compareAndUpdateSettings:settingRevisions];
    
    if (newTasksRev > currTasksRev) {
        LogInfo(@"[updateGroupSettings]: Reloading scheduled tasks with updated values.");
        [[TaskScheduler sharedScheduler] listAllTasks];
        [[TaskScheduler sharedScheduler] reloadTasksFromConfig];
        [[TaskScheduler sharedScheduler] listAllTasks];
        //TaskScheduler *scheduler = [[TaskScheduler alloc] init];
        //[scheduler stopAllTasks];
        //[scheduler reloadTasksFromConfig];
        //[scheduler listAllTasks];
    }
	return;
}

- (void)installRequiredSoftware:(NSDictionary *)checkinResult
{
	LogInfo(@"Install required client group software.");
	
	NSArray *swTasks;
	if (!checkinResult[@"swTasks"]) {
		LogError(@"Checkin result did not contain sw tasks object.");
		return;
	}
	
	swTasks = checkinResult[@"swTasks"];
	if (swTasks.count >= 1)
	{
		Software *sw = [[Software alloc] init];
		for (NSDictionary *t in swTasks)
		{
			NSString *task = t[@"tuuid"];
			if ([sw isSoftwareTaskInstalled:task])
			{
				continue;
			}
			else
			{
				NSError *err = nil;
				MPRESTfull *mpRest = [[MPRESTfull alloc] init];
				NSDictionary *swTask = [mpRest getSoftwareTaskUsingTaskID:task error:&err];
				if (err) {
					LogError(@"%@",err.localizedDescription);
					continue;
				}
				LogInfo(@"Begin installing %@.",swTask[@"name"]);
				int res = [sw installSoftwareTask:swTask];
				if (res != 0) {
					LogError(@"Required software, %@ failed to install.",swTask[@"name"]);
				}
			}
		}
	}
}



@end
