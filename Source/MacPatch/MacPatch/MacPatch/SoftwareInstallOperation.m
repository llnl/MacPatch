//
//  SoftwareInstallOperation.m
//  MacPatch
//
//  Created by Charles Heizer on 11/5/18.
//  Copyright © 2018 Heizer, Charles. All rights reserved.
//

#import "SoftwareInstallOperation.h"

@interface SoftwareInstallOperation (Private)

- (void)runInstall;

// XPC Connection

- (void)connectToHelperTool;
- (void)connectAndExecuteCommandBlock:(void(^)(NSError *))commandBlock;
- (void)postSWStatus:(NSString *)status;

@end

@implementation SoftwareInstallOperation
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
			cellStartNote = [NSString stringWithFormat:@"swStart-%@",swTask[@"id"]];
			cellProgressNote = [NSString stringWithFormat:@"swProg-%@",swTask[@"id"]];
			cellStopNote = [NSString stringWithFormat:@"swStop-%@",swTask[@"id"]];
		} else {
			cellStartNote = [NSString stringWithFormat:@"swStart-%@",@"NA"];
			cellProgressNote = [NSString stringWithFormat:@"swProg-%@",@"NA"];
			cellStopNote = [NSString stringWithFormat:@"swStop-%@",@"NA"];
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
		[self runInstall];
	}
	@catch (NSException * e) {
		qlerror(@"[NSException]: %@",e);
	}
	[self finish];
}

- (void)runInstall
{
	dispatch_semaphore_t sem = dispatch_semaphore_create(0);

	qlinfo(@"Install Software Task: %@",swTask);
	[self postSWStatus:@"Starting Install operation"];
	NSDictionary *softwareObj = swTask[@"Software"];
	
	// -----------------------------------------
	// Verify Disk space requirements before
	// downloading and installing
	// -----------------------------------------
	NSScanner *scanner = [NSScanner scannerWithString:softwareObj[@"sw_size"]];
	long long stringToLong;
	if(![scanner scanLongLong:&stringToLong]) {
		qlerror(@"Unable to convert size %@",softwareObj[@"sw_size"]);
		[self postSWStatus:@"Unable to check disk size requirements"];
		[self postStopHasError:YES errorString:@"Unable to check disk size requirements"];
		return;
	}
	
	MPDiskUtil *mpd = [[MPDiskUtil alloc] init];
	if ([mpd diskHasEnoughSpaceForPackage:stringToLong] == NO)
	{
		qlerror(@"This system does not have enough free disk space to install the following software %@",softwareObj[@"name"]);
		[self postSWStatus:@"System does not have enough free disk space"];
		[self postStopHasError:YES errorString:@"System does not have enough free disk space"];
		return;
	}
	
	[self connectAndExecuteCommandBlock:^(NSError * connectError) {
		if (connectError != nil) {
			qlerror(@"workerConnection[connectError]: %@",connectError.localizedDescription);
			[self willChangeValueForKey:@"userInfo"];
			self->userInfo = @{@"status":connectError.localizedDescription, @"error":connectError};
			[self didChangeValueForKey:@"userInfo"];
			dispatch_semaphore_signal(sem);
		} else {
			[[self.workerConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
				qlerror(@"workerConnection[proxyError]: %@",proxyError.localizedDescription);
				[self willChangeValueForKey:@"userInfo"];
				self->userInfo = @{@"status":proxyError.localizedDescription, @"error":proxyError};
				[self didChangeValueForKey:@"userInfo"];
				dispatch_semaphore_signal(sem);
				
			}] installSoftware:self->swTask withReply:^(NSError *error, NSInteger resultCode, NSData *installData) {

				if (resultCode == 0) {
					[self willChangeValueForKey:@"userInfo"];
					self->userInfo = nil;
					[self didChangeValueForKey:@"userInfo"];
				} else {
					qlerror(@"Error installing software task %@",self->swTask[@"Software"][@"name"]);
					if (error) {
						qlerror(@"Error: %@",error.localizedDescription);
					} else {
						error = [NSError errorWithDomain:@"InstallError"
																 code:1
															 userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"Failed to install software task.", nil)}];
					}
					// Set Error info
					[self willChangeValueForKey:@"userInfo"];
					self->userInfo = @{@"status":@"Failed to install software task.", @"error":error};
					[self didChangeValueForKey:@"userInfo"];
					
					qlerror(@"Error userInfo: %@",self->userInfo);
				}
				
				// CEH - Post Install Result
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
	qlinfo(@"postStopHasError called %@",arg2);
	NSError *err = nil;
	if (arg1) {
		err = [NSError errorWithDomain:@"gov.llnl.sw.oper" code:1001 userInfo:@{NSLocalizedDescriptionKey:arg2}];
		[[NSNotificationCenter defaultCenter] postNotificationName:cellStopNote object:nil userInfo:@{@"error":err}];
	} else {
		[[NSNotificationCenter defaultCenter] postNotificationName:cellStopNote object:nil userInfo:@{}];
	}
}


@end
