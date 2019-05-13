//
//  MPNSTask.m
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

#import "MPNSTask.h"
#import "MacPatch.h"
#import "MPTimer.h"

@interface NSFileHandle (MPNSFileHandleAdditions)
- (NSData *)availableDataOrError:(NSException **)returnError;
@end

@implementation NSFileHandle (MPNSFileHandleAdditions)
- (NSData *)availableDataOrError:(NSException **)returnError
{
	for(;;)
	{
		@try
		{
			return [self availableData];
		}
		@catch (NSException *e)
		{
			if ([[e name] isEqualToString:NSFileHandleOperationException]) {
				if ([[e reason] isEqualToString:@"*** -[NSConcreteFileHandle availableData]: Interrupted system call"]) {
					continue;
				}
				if (returnError) {
					*returnError = e;
				}
				return nil;
			}
			@throw;
		}
	}
}
@end

#undef  ql_component
#define ql_component lcl_cMPNSTask

@interface MPNSTask ()
{
	NSTask *task;
}

@property (strong)              		 NSTimer     *taskTimeoutTimer;
@property (nonatomic, assign, readwrite) BOOL        taskTimedOut;
@property (nonatomic, assign, readwrite) BOOL        taskIsRunning;

@property (nonatomic, strong) NSData *taskData;

@end

@implementation MPNSTask

@synthesize taskTimeoutTimer;
@synthesize taskTimeoutValue;
@synthesize taskTimedOut;
@synthesize taskIsRunning;

- (id)init
{
    self = [super init];
	if (self)
	{
		[self setTaskTimeoutValue:600];
		[self setTaskIsRunning:NO];
		[self setTaskTimedOut:NO];
    }
	
    return self;
}

- (NSString *)runTask:(NSString *)aBinPath binArgs:(NSArray *)aArgs error:(NSError **)err
{
	NSError *error = nil;
	NSString *result;
	result = [self runTask:aBinPath binArgs:aArgs environment:nil error:&error];
	if (error)
	{
		if (err != NULL) *err = error;
	}
	
    return [result trim];
}

- (NSString *)runTask:(NSString *)aBinPath binArgs:(NSArray *)aArgs environment:(NSDictionary *)aEnv error:(NSError **)err
{
	[self setTaskIsRunning:YES];
	[self setTaskTimedOut:NO];
	
	int taskResult = -1;
	
	if (task) {
		task = nil;
	}
	task = [[NSTask alloc] init];
	NSPipe *aPipe = [NSPipe pipe];
	
	[task setStandardOutput:aPipe];
	[task setStandardError:aPipe];
	if (aEnv != NULL) {
		qldebug(@"[task][environment]: %@",aEnv);
		[task setEnvironment:aEnv];
	}
	
	// CEH - Debug
	[task setLaunchPath:aBinPath];
	qldebug(@"[task][setLaunchPath]: %@",aBinPath);
	[task setArguments:aArgs];
	qldebug(@"[task][setArguments]: %@",aArgs);
	
		
	// Get a NSFileHandle from the pipe. This NSFileHandle will provide the stdout buffer
	NSFileHandle *fileHandle = [aPipe fileHandleForReading];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(mpTaskDataAvailable:)
												 name:NSFileHandleDataAvailableNotification
											   object:fileHandle];
		
	// Setup the file handle to work asynchronously and trigger the notification when there is data
	// in the stdout
	[fileHandle waitForDataInBackgroundAndNotify];
	
	// And finally launch the task, asynchronously
	// If timeout is set start it ...
	if (taskTimeoutValue != 0) {
		//[NSThread detachNewThreadSelector:@selector(taskTimeoutThread) toTarget:self withObject:nil];
	}
	
	[task launch];
	[task waitUntilExit];
	taskResult = [task terminationStatus];
	if (taskResult == 0) {
		qlinfo(@"Task succeeded: %d",taskResult);
	} else {
		qlerror(@"Task failed: %d",taskResult);
		NSDictionary *errorDetail = @{NSLocalizedDescriptionKey:@"Task failed."};
		NSError *error = [NSError errorWithDomain:@"gov.llnl.mptask" code:taskResult userInfo:errorDetail];
		if (err != NULL) *err = error;
	}
	
	[self setTaskIsRunning:NO];
	NSString *tmpStr = [[NSString alloc] initWithData:_taskData encoding:NSUTF8StringEncoding];
	return tmpStr;
}

// The notification will be captured and run this method,
// passing the NSFileHandle as the object property of the notification
- (void)mpTaskDataAvailable:(NSNotification *)notification
{
	NSMutableData *_data = [NSMutableData dataWithData:_taskData];
	NSData *newData = [notification.object availableData];
	if (newData && newData.length)
	{
		NSString *tmpStr = [[NSString alloc] initWithData:newData encoding:NSUTF8StringEncoding];
		if ([[tmpStr trim] length] != 0)
		{
			[self postStatusToDelegate:tmpStr];
			qlinfo(@"INCR: %@",tmpStr);
		}
		[_data appendData:newData];
		_taskData = (NSData *)[_data copy];
	}
	
	[notification.object waitForDataInBackgroundAndNotify];
}

#pragma mark - Private

- (void)taskTimeoutThread
{
	@autoreleasepool
	{
		for (int i = 0; i < taskTimeoutValue; i++)
		{
			[NSThread sleepForTimeInterval:1.0];
			if (!taskIsRunning) break;
		}
		if (taskIsRunning)taskTimedOut = YES;
		
		if (taskTimedOut)
		{
			qlinfo(@"Task timedout, killing task.");
			[task terminate];
		}
	}
	
}

- (void)taskTimeoutThreadOld
{
	@autoreleasepool
	{
		 qlinfo(@"[MPNSTask] Timeout is set to %d",taskTimeoutValue);
		 NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:taskTimeoutValue
														   target:self
														selector:@selector(taskTimeout:)
														 userInfo:nil
														 repeats:NO];
		 [self setTaskTimeoutTimer:timer];
		 while (taskTimedOut == NO && [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]]);
	}
	
}

- (void)taskTimeout:(NSNotification *)aNotification
{
	qlinfo(@"Task timedout, killing task.");
	//[taskTimeoutTimer invalidate];
	[self setTaskTimedOut:YES];
	[task terminate];
}

#pragma mark - Delegate Helper

- (void)postStatusToDelegate:(NSString *)str, ...
{
	va_list va;
	va_start(va, str);
	NSString *string = [[NSString alloc] initWithFormat:str arguments:va];
	va_end(va);
	
	[self.delegate taskStatus:self status:string];
}
@end
