//
//  ClientCheckInOperation.m
/*
 Copyright (c) 2023, Lawrence Livermore National Security, LLC.
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

#import "ClientCheckInOperation.h"
#import "MPAgent.h"
#import "MacPatch.h"
#import "MPSettings.h"
#import "Software.h"

@interface ClientCheckInOperation (Private)

- (void)runCheckIn;

@end


@implementation ClientCheckInOperation

- (id)init
{
	self = [super init];
	if (self) {
		self.isExecuting = NO;
        self.isFinished  = NO;
		settings	= [MPSettings sharedInstance];
		fm          = [NSFileManager defaultManager];
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
		[self runCheckIn];
	}
	@catch (NSException * e) {
		logit(lcl_vError,@"[NSException]: %@",e);
	}
	[self finish];
}

- (void)runCheckIn
{
    // Collect Agent Checkin Data
    MPClientInfo *ci = [[MPClientInfo alloc] init];
    NSDictionary *agentData = [ci agentData];
    if (!agentData)
    {
        logit(lcl_vError,@"Agent data is nil, can not post client checkin data.");
        return;
    }
    
    // Post Client Checkin Data to WS
    NSError *error = nil;
    NSDictionary *revsDict;
    MPRESTfull *rest = [[MPRESTfull alloc] init];
    revsDict = [rest postClientCheckinData:agentData error:&error];
    if (error) {
        logit(lcl_vError,@"Running client check in had an error.");
        logit(lcl_vError,@"%@", error.localizedDescription);
    }
    else
    {
        [self updateGroupSettings:revsDict];
		[self installRequiredSoftware:revsDict];
    }

    logit(lcl_vInfo,@"Running client check in completed.");
    return;
}

- (void)updateGroupSettings:(NSDictionary *)settingRevisions
{
    // Query for Revisions
    // Call MPSettings to update if nessasary
    logit(lcl_vInfo,@"Check and Update Agent Settings.");
    logit(lcl_vDebug,@"Setting Revisions from server: %@", settingRevisions);
    MPSettings *set = [MPSettings sharedInstance];
    [set compareAndUpdateSettings:settingRevisions];
	return;
}

- (void)installRequiredSoftware:(NSDictionary *)checkinResult
{
	logit(lcl_vInfo,@"Install required client group software.");
	
	NSArray *swTasks;
	if (!checkinResult[@"swTasks"]) {
		logit(lcl_vError,@"Checkin result did not contain sw tasks object.");
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
					logit(lcl_vError,@"%@",err.localizedDescription);
					continue;
				}
				logit(lcl_vInfo,@"Begin installing %@.",swTask[@"name"]);
				int res = [sw installSoftwareTask:swTask];
				if (res != 0) {
					logit(lcl_vError,@"Required software, %@ failed to install.",swTask[@"name"]);
				}
			}
		}
	}
}



@end
