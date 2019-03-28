//
//  InventoryOperation.m
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

#import "InventoryOperation.h"
#import "MPAgent.h"
#import "MacPatch.h"
#import "MPInv.h"

@interface InventoryOperation (Private)

- (void)runInventoryCollection;

@end

@implementation InventoryOperation

@synthesize isExecuting;
@synthesize isFinished;

- (id)init
{
	if ((self = [super init])) {
		isExecuting = NO;
        isFinished  = NO;
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
    isExecuting = NO;
    isFinished = YES;
    [self didChangeValueForKey:@"isExecuting"];
    [self didChangeValueForKey:@"isFinished"];
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
		[self runInventoryCollection];
	}
	@catch (NSException * e) {
		logit(lcl_vError,@"[NSException]: %@",e);
	}
	[self finish];
}

- (void)runInventoryCollection
{
	@autoreleasepool
    {
		logit(lcl_vInfo,@"Running client inventory scan.");

        int res = -1;
        MPInv __autoreleasing *inv = [[MPInv alloc] init];
        res = [inv collectInventoryData];
        inv = nil;
        
		logit(lcl_vDebug,@"[collectInventoryData]: Result =  %d",(int)res);
		logit(lcl_vInfo,@"Inventory collection has been completed.");
		logit(lcl_vInfo,@"See the MPInventory.log file for more information.");
	}
}

@end
