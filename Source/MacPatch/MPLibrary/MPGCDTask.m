//
//  MPGCDTask.m
//  MPLibrary
//
//  Created by Charles Heizer on 5/9/19.
//

#import "MPGCDTask.h"
#import "GCDTask.h"

@interface MPGCDTask ()
{
	GCDTask             *gcdTask;
}

@property (nonatomic,strong)             NSThread *timeoutThread;
@property (nonatomic, assign)            int       taskTimeoutValue;
@property (nonatomic, assign)            int       taskTimeoutCount;
@property (nonatomic, assign, readwrite) BOOL      taskTimedOut;
@property (nonatomic, assign, readwrite) int       installtaskResult;

- (void)startTaskTimeoutThread;
- (void)taskTimeoutThread;
- (void)requestTaskTermination;

@end


@implementation MPGCDTask

@synthesize timeoutThread;
@synthesize taskTimeoutValue;
@synthesize taskTimeoutCount;
@synthesize taskTimedOut;
@synthesize installtaskResult;

- (id)init
{
	if (self = [super init])
	{
		[self setTaskTimeoutValue:600];
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
	// ---------------------------------------------
	// Default Installer Env Variables
	// ---------------------------------------------
	NSDictionary *defaultEnv = [[NSProcessInfo processInfo] environment];
	NSMutableDictionary *env = [[NSMutableDictionary alloc] initWithDictionary:defaultEnv];
	[env setObject:@"YES" forKey:@"NSUnbufferedIO"];
	[env setObject:@"1" forKey:@"COMMAND_LINE_INSTALL"];
	
	if (aEnv != NULL) {
		[env addEntriesFromDictionary:aEnv];
		qlinfo(@"[task][environment]: %@",env);
	}
	
	// ---------------------------------------------
	// Setup GCDTask
	// ---------------------------------------------
	
	GCDTask *gTask = [[GCDTask alloc] init];
	[gTask setArguments:aArgs];
	[gTask setLaunchPath:aBinPath];
	[gTask setEnvironment:env];
	gcdTask = gTask;
	
	// ---------------------------------------------
	// Start Install
	// ---------------------------------------------
	dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
	__block NSString *output = @"NA";
	__block int exitCode = 0;
	[gTask launchWithOutputBlock:^(NSData *stdOutData) {
		output = [[NSString alloc] initWithData:stdOutData encoding:NSUTF8StringEncoding];
		qlinfo(@"%@",output);
		
	} andErrorBlock:^(NSData *stdErrData) {
		NSString *output = [[NSString alloc] initWithData:stdErrData encoding:NSUTF8StringEncoding];
		qlerror(@"[stdErr]: %@",output);
		
	} onLaunch:^{
		qlinfo(@"Installer task has started running.");
		[self startTaskTimeoutThread];
		
	} onExit:^(int exitStatus) {
		if (exitStatus == 0) {
			qlinfo(@"Installer task has now exited. Exit status %d",exitStatus);
		} else {
			qlerror(@"Installer task has now exited. Exit status %d",exitStatus);
		}
		exitCode = exitStatus;
		dispatch_semaphore_signal(semaphore);
	}];
	
	dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
	
	[self setInstalltaskResult:exitCode];
	return output;
}


#pragma mark - Timeout

- (void)startTaskTimeoutThread
{
	qlinfo(@"Start timeout thread");
	timeoutThread = [[NSThread alloc] initWithTarget:self selector:@selector(taskTimeoutThread) object:nil];
	[timeoutThread start];
}

- (void)taskTimeoutThread
{
	@autoreleasepool
	{
		while (self.taskTimeoutValue > self.taskTimeoutCount)
		{
			[NSThread sleepForTimeInterval:1.0];
			taskTimeoutCount++;
		}
		[self requestTaskTermination]; // Task timed out
		[self setTaskTimedOut:YES];
	}
}

- (void)requestTaskTermination
{
	qlerror(@"Task timedout, killing task.");
	[gcdTask RequestTermination];
}

@end
