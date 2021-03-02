//
//  AgentScanAndUpdateOperation.m
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

#import "AgentScanAndUpdateOperation.h"
#import "MPAgent.h"
#import "MacPatch.h"
#import "MPAgentUpdater.h"

@interface AgentScanAndUpdateOperation (Private)

- (void)runAgentScanAndUpdate;

@end

@implementation AgentScanAndUpdateOperation

- (id)init
{
	self = [super init];
	if (self)
	{
		self.isExecuting = NO;
        self.isFinished  = NO;
		si	= [MPAgent sharedInstance];
		fm	= [NSFileManager defaultManager];
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
		[self runAgentScanAndUpdate];
	}
	@catch (NSException * e) {
		logit(lcl_vError,@"[NSException]: %@",e);
	}
	[self finish];
}

- (void)runAgentScanAndUpdate
{
	@autoreleasepool
    {
		logit(lcl_vInfo,@"Running agent update check.");
        MPAgentUpdater *mpu = [[MPAgentUpdater alloc] init];
        [mpu scanAndUpdateAgentUpdater];
        mpu = nil;
	}
}

@end

