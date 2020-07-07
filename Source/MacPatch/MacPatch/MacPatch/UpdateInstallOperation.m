//
//  UpdateInstallOperation.m
//  MacPatch
//
//  Created by Charles Heizer on 11/21/18.
//  Copyright © 2018 Heizer, Charles. All rights reserved.
//

#import "UpdateInstallOperation.h"
#import "LongPatchWindow.h"
#import "AppDelegate.h"

@interface UpdateInstallOperation ()

@property (nonatomic, assign) int showRebootWindow; // 0 = Off, 1 = Restart, 2 = Shutdown

@end

@interface UpdateInstallOperation (Private)

- (void)runPatchInstall;

// XPC Connection

- (void)connectToHelperTool;
- (void)connectAndExecuteCommandBlock:(void(^)(NSError *))commandBlock;

- (void)postPatchStatus:(NSString *)status;

@end

@implementation UpdateInstallOperation
{
	NSString *cellStartNote;
	NSString *cellProgressNote;
	NSString *cellStopNote;
}

@synthesize isExecuting;
@synthesize isFinished;
@synthesize workerConnection;
@synthesize userInfo;
@synthesize patch;
@synthesize showRebootWindow;

- (id)init
{
	self = [super init];
	if (self)
	{
		isExecuting = NO;
		isFinished  = NO;
		fm	= [NSFileManager defaultManager];
		patch = nil;
		showRebootWindow = 0;
	}
	return self;
}

- (void)setPatch:(NSDictionary *)arg1
{
	patch = arg1;
	
	NSString *pID = @"NA";
	if ([patch[@"type"] isEqualToString:@"Apple"]) {
		pID = patch[@"patch"];
	} else {
		pID = patch[@"patch_id"];
	}
	
	if (pID) {
		cellStartNote = [NSString stringWithFormat:@"patchStart-%@",pID];
		cellProgressNote = [NSString stringWithFormat:@"patchProg-%@",pID];
		cellStopNote = [NSString stringWithFormat:@"patchStop-%@",pID];
	} else {
		cellStartNote = [NSString stringWithFormat:@"patchStart-%@",@"NA"];
		cellProgressNote = [NSString stringWithFormat:@"patchProg-%@",@"NA"];
		cellStopNote = [NSString stringWithFormat:@"patchStop-%@",@"NA"];
	}
	
	qldebug(@"Setup Set Patch");
	qltrace(@"cellStartNote: %@",cellStartNote);
	qltrace(@"cellProgressNote: %@",cellProgressNote);
	qltrace(@"cellStopNote: %@",cellStopNote);
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
	qltrace(@"-(void)finish ... calling %@",cellStopNote);
	[[NSNotificationCenter defaultCenter] postNotificationName:cellStopNote object:nil userInfo:userInfo];
	qlinfo(@"finish");
	qlinfo(@"showRebootWindow: %d",showRebootWindow);
	AppDelegate *appDelegate;
	if (showRebootWindow == 1) {
		qlinfo(@"showRebootWindow == 1");
		appDelegate = (AppDelegate *)NSApp.delegate;
		dispatch_async(dispatch_get_main_queue(), ^{
			[appDelegate showRestartWindow:0];
		});
	} else if (showRebootWindow == 2) {
		qlinfo(@"showRebootWindow == 2");
		appDelegate = (AppDelegate *)NSApp.delegate;
		dispatch_async(dispatch_get_main_queue(), ^{
			[appDelegate showRestartWindow:1];
		});
	}
	qlinfo(@"finish");
}

- (void)start
{
	if ([self isCancelled]) {
		[self willChangeValueForKey:@"isFinished"];
		isFinished = YES;
		[self didChangeValueForKey:@"isFinished"];
	} else {
		[[NSNotificationCenter defaultCenter] postNotificationName:cellStartNote object:nil userInfo:nil];
		[self willChangeValueForKey:@"isExecuting"];
		[self performSelectorInBackground:@selector(main) withObject:nil];
		isExecuting = YES;
		[self didChangeValueForKey:@"isExecuting"];
	}
}

- (void)main
{
	@try
	{
		[self runPatchInstall];
	}
	@catch (NSException * e) {
		qlerror(@"[NSException]: %@",e);
	}
	[self finish];
}

- (void)runPatchInstall
{
	dispatch_semaphore_t sem = dispatch_semaphore_create(0);
	
	[self connectAndExecuteCommandBlock:^(NSError * connectError) {
		if (connectError != nil) {
			qlerror(@"workerConnection[connectError]: %@",connectError.localizedDescription);
			[self willChangeValueForKey:@"userInfo"];
			self->userInfo = @{@"status":connectError.localizedDescription, @"error":connectError};
			[self didChangeValueForKey:@"userInfo"];
			dispatch_semaphore_signal(sem);
		} else {

			int aRebPtch = [[NSUserDefaults standardUserDefaults] boolForKey:@"allowRebootPatchInstalls"] ? 1 : 0;
			
			[[self.workerConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
				qlerror(@"%@",proxyError);
				dispatch_semaphore_signal(sem);
			}] installPatch:self->patch userInstallRebootPatch:aRebPtch withReply:^(NSError *error, NSInteger resultCode) {
				
				qldebug(@"installPatch:self->patch withReply");
				qldebug(@"resultCode: %ld",resultCode);
				
				if (error) {
					qlerror(@"%@",error.localizedDescription);
				}
				
				if (resultCode == 0 || resultCode == 1000) // 1000 is a signal for patch that needs a halt
				{
					qlinfo(@"Install was sucessful");
					[self willChangeValueForKey:@"userInfo"];
					self->userInfo = nil;
					[self didChangeValueForKey:@"userInfo"];
					if (aRebPtch == 1)
					{
						//AppDelegate *appDelegate = (AppDelegate *)NSApp.delegate;
						if (resultCode == 1000) {
							qlinfo(@"resultCode == 1000");
							self->showRebootWindow = 2;
							qlinfo(@"runPatchInstall: showRebootWindow: %d",self->showRebootWindow);
						} else {
							qlinfo(@"resultCode == 0");
							self->showRebootWindow = 1;
							qlinfo(@"runPatchInstall: showRebootWindow: %d",self->showRebootWindow);
						}
					}
				} else {
					if (!error) {
						// No error obj, need to create one
						error = [NSError errorWithDomain:@"gov.llnl.patch.oper" code:1001 userInfo:@{NSLocalizedDescriptionKey:@"Error installing patch. See helper logs for more details."}];
					}
					
					qlerror(@"Error[%ld] installing %@", resultCode, self->patch[@"patch"]);
					// Set Error info
					[self willChangeValueForKey:@"userInfo"];
					self->userInfo = @{@"status":@"", @"error":error};
					[self didChangeValueForKey:@"userInfo"];
					qlerror(@"Setting userInfo: %@",self->userInfo);
				}
				
				dispatch_semaphore_signal(sem);
			}];
			
		}
	}];
	
	dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
}

- (void)showLongPatchInstallAlert
{
	if ([self.patch objectForKey:@"isLongPatch"])
	{
		if ([[self.patch objectForKey:@"isLongPatch"] isEqualTo:@"1"])
		{
			LongPatchWindow *lp = [[LongPatchWindow alloc] initWithPatch:self.patch];
			[lp show];
		}
	}
	
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

/*
#pragma mark - MPHelperProgress protocol

- (void)postStatus:(NSString *)status type:(MPPostDataType)type
{
	if (type == kMPPatchProcessStatus) {
		//[self postSWStatus:status];
	} else if (type == kMPPatchProcessProgress) {
		//
	}
}
*/

#pragma mark - MPHelperProgress protocol

- (void)postStatus:(NSString *)status type:(MPPostDataType)type
{
	qlinfo(@"UpdateInstallOperation[%lu]: %@",(unsigned long)type,status);
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
