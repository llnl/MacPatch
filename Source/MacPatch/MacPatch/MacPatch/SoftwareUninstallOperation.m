//
//  SoftwareUninstallOperation.m
/*
 Copyright (c) 2024, Lawrence Livermore National Security, LLC.
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

#import "SoftwareUninstallOperation.h"

@interface SoftwareUninstallOperation (Private)

- (void)runUninstall;

// XPC Connection

- (void)connectToHelperTool;
- (void)connectAndExecuteCommandBlock:(void(^)(NSError *))commandBlock;
- (void)postSWStatus:(NSString *)status;

@end

@implementation SoftwareUninstallOperation
{
	NSString *cellStartNote;
	NSString *cellProgressNote;
	NSString *cellStopNote;
}

@synthesize isExecuting;
@synthesize isFinished;
@synthesize workerConnection;
@synthesize userInfo;

@synthesize swTask;

- (id)init
{
	self = [super init];
	if (self)
	{
		isExecuting = NO;
		isFinished  = NO;
		fm	= [NSFileManager defaultManager];
	}
	return self;
}

- (void) setSWTask:(NSDictionary *)arg1
{
	if (arg1 != swTask)
	{
		swTask = arg1;
		if (swTask[@"id"]) {
			cellStartNote = [NSString stringWithFormat:@"swUnStart-%@",swTask[@"id"]];
			cellProgressNote = [NSString stringWithFormat:@"swUnProg-%@",swTask[@"id"]];
			cellStopNote = [NSString stringWithFormat:@"swUnStop-%@",swTask[@"id"]];
		} else {
			cellStartNote = [NSString stringWithFormat:@"swUnStart-%@",@"NA"];
			cellProgressNote = [NSString stringWithFormat:@"swUnProg-%@",@"NA"];
			cellStopNote = [NSString stringWithFormat:@"swUnStop-%@",@"NA"];
		}
	}
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
	
	[[NSNotificationCenter defaultCenter] postNotificationName:cellStopNote object:nil userInfo:userInfo];
}

- (void)start
{
	if ([self isCancelled]) {
		[self willChangeValueForKey:@"isFinished"];
		isFinished = YES;
		[self didChangeValueForKey:@"isFinished"];
	} else {
		[[NSNotificationCenter defaultCenter] postNotificationName:@"disableSWCatalogMenu" object:nil userInfo:@{}];
		[[NSNotificationCenter defaultCenter] postNotificationName:cellStartNote object:nil userInfo:nil];
		[self willChangeValueForKey:@"isExecuting"];
		[self performSelectorInBackground:@selector(main) withObject:nil];
		isExecuting = YES;
		[self didChangeValueForKey:@"isExecuting"];
	}
}

- (void)main
{
	@try {
		[self runUninstall];
	}
	@catch (NSException * e) {
		qlerror(@"[NSException]: %@",e);
	}
	[self finish];
}

- (void)runUninstall
{
	dispatch_semaphore_t sem = dispatch_semaphore_create(0);
	
	NSString *_tuuid = swTask[@"id"];
	NSString *_name = swTask[@"Software"][@"name"];
	
	qlinfo(@"Starting uninstall of software task %@ (%@).",_name,_tuuid);
	//qldebug(@"Install Software Task: %@",swTask);
	[self postSWStatus:@"Starting Uninstall operation"];
	
	
	[self connectAndExecuteCommandBlock:^(NSError * connectError)
	{
		if (connectError != nil)
		{
			qlerror(@"workerConnection[connectError]: %@",connectError.localizedDescription);
			[self willChangeValueForKey:@"userInfo"];
			self->userInfo = @{@"status":connectError.localizedDescription, @"error":connectError};
			[self didChangeValueForKey:@"userInfo"];
			dispatch_semaphore_signal(sem);
		}
		else
		{
			[[self.workerConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
				qlerror(@"workerConnection[proxyError]: %@",proxyError.localizedDescription);
				[self willChangeValueForKey:@"userInfo"];
				self->userInfo = @{@"status":proxyError.localizedDescription, @"error":proxyError};
				[self didChangeValueForKey:@"userInfo"];
				dispatch_semaphore_signal(sem);
				
			}] uninstallSoftware:_tuuid withReply:^(NSInteger resultCode) {
				
				if (resultCode == 0)
				{
					[self willChangeValueForKey:@"userInfo"];
					self->userInfo = nil;
					[self didChangeValueForKey:@"userInfo"];
				}
				else
				{
					NSString *errStr = [NSString stringWithFormat:@"Error uninstalling %@",_name];
					NSError *err = [NSError errorWithDomain:@"" code:1 userInfo:@{NSLocalizedDescriptionKey:errStr}];
					qlerror(@"%@",errStr);
					
					// Set Error info
					[self willChangeValueForKey:@"userInfo"];
					self->userInfo = @{@"status":@"", @"error":err};
					[self didChangeValueForKey:@"userInfo"];
				}
				
				dispatch_semaphore_signal(sem);
			}];
		}
	}];

	dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
}

#pragma mark - Helper

- (void)connectToHelperTool
// Ensures that we're connected to our helper tool.
{
	//assert([NSThread isMainThread]);
	if (self.workerConnection == nil) {
		self.workerConnection = [[NSXPCConnection alloc] initWithMachServiceName:kHelperServiceName options:NSXPCConnectionPrivileged];
		self.workerConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(MPHelperProtocol)];
		
		// Register Progress Messeges From Helper
		self.workerConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(MPHelperProgress)];
		self.workerConnection.exportedObject = self;
		
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
		// We can ignore the retain cycle warning because a) the retain taken by the
		// invalidation handler block is released by us setting it to nil when the block
		// actually runs, and b) the retain taken by the block passed to -addOperationWithBlock:
		// will be released when that operation completes and the operation itself is deallocated
		// (notably self does not have a reference to the NSBlockOperation).
		self.workerConnection.invalidationHandler = ^{
			// If the connection gets invalidated then, on the main thread, nil out our
			// reference to it.  This ensures that we attempt to rebuild it the next time around.
			self.workerConnection.invalidationHandler = nil;
			[[NSOperationQueue mainQueue] addOperationWithBlock:^{
				self.workerConnection = nil;
				qlerror(@"connection invalidated");
			}];
		};
#pragma clang diagnostic pop
		[self.workerConnection resume];
	}
}

- (void)connectAndExecuteCommandBlock:(void(^)(NSError *))commandBlock
// Connects to the helper tool and then executes the supplied command block on the
// main thread, passing it an error indicating if the connection was successful.
{
	//assert([NSThread isMainThread]);
	
	// Ensure that there's a helper tool connection in place.
	self.workerConnection = nil;
	[self connectToHelperTool];
	
	commandBlock(nil);
}

#pragma mark - MPHelperProgress protocol

- (void)postStatus:(NSString *)status type:(MPPostDataType)type
{
	if (type == kMPProcessStatus) {
		[self postSWStatus:status];
	}
}

#pragma mark - Notifications

- (void)postSWStatus:(NSString *)status
{
	[[NSNotificationCenter defaultCenter] postNotificationName:cellProgressNote object:nil userInfo:@{@"status":status}];
}

- (void)postStopHasError:(BOOL)arg1 errorString:(NSString *)arg2
{
	NSError *err = nil;
	if (arg1) {
		err = [NSError errorWithDomain:@"gov.llnl.sw.oper" code:1001 userInfo:@{NSLocalizedDescriptionKey:arg2}];
		[[NSNotificationCenter defaultCenter] postNotificationName:cellStopNote object:nil userInfo:@{@"error":err}];
	} else {
		[[NSNotificationCenter defaultCenter] postNotificationName:cellStopNote object:nil userInfo:@{}];
	}
}

@end
