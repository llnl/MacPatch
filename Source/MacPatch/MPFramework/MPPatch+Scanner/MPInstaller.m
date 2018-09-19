//
//  MPInstaller.m
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

#import "MPInstaller.h"
#import <SystemConfiguration/SystemConfiguration.h>

#undef  ql_component
#define ql_component lcl_cMPInstaller

@implementation MPInstaller

@synthesize taskIsRunning;
@synthesize task;
@synthesize taskResult;

// Proxy Method
- (int)installAppleSoftwareUpdate:(NSString *)approvedUpdate
{		
	NSArray *appArgs = [NSArray arrayWithObjects:@"-i", approvedUpdate, nil];
	
	// Define Install Environment Variables
	NSDictionary *defaultEnvironment = [[NSProcessInfo processInfo] environment];
	NSMutableDictionary *environment = [[NSMutableDictionary alloc] initWithDictionary:defaultEnvironment];
	[environment setObject:@"YES" forKey:@"NSUnbufferedIO"];
	[environment setObject:@"1" forKey:@"COMMAND_LINE_INSTALL"];
	
	NSTask *l_task = [[NSTask alloc] init];
	NSPipe *pipe = [NSPipe pipe];
	
	NSData *l_data = nil;
	NSMutableData *l_taskData = [NSMutableData data];
	
	[l_task setLaunchPath:ASUS_BIN_PATH];
    [l_task setArguments:appArgs];
	[l_task setEnvironment:environment];
	[l_task setStandardOutput: pipe];
	[l_task setStandardError: pipe];
	
	NSFileHandle *fileHandle = [pipe fileHandleForReading];
	[l_task launch];
	
	NSString *tmpStr;
	while ((l_data = [fileHandle availableData]) && [l_data length])
	{
		tmpStr = [[NSString alloc] initWithData:l_data encoding:NSUTF8StringEncoding];
		logit(lcl_vDebug,@"%@",tmpStr);
		NSMutableDictionary *notificationInfo = [NSMutableDictionary dictionary];
		[notificationInfo setObject:tmpStr forKey:@"iData"];
		[[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"MPDataAvailableNotification" object:nil userInfo:(NSDictionary *)notificationInfo deliverImmediately:YES];
		tmpStr = nil;
	}
	
	[l_task waitUntilExit];
	NSString *taskDataString = [[NSString alloc] initWithData:l_taskData encoding:NSUTF8StringEncoding];
	logit(lcl_vDebug,@"Install Results: %@",taskDataString);
	
	int l_taskResult = [l_task terminationStatus];
	if (l_taskResult != 0)
	{
		logit(lcl_vError,@"Install returned error. Code:[%d]",l_taskResult);
	}
    
	[self setTaskIsRunning:NO];
	sleep(1);
	
	return l_taskResult;
}

- (int)installPkgToRoot:(NSString *)pkgPath
{
	return [self installPkg:pkgPath target:@"/" env:nil];
}

- (int)installPkgToRoot:(NSString *)pkgPath env:(NSString *)aEnv;
{
	return [self installPkg:pkgPath target:@"/" env:aEnv];
}

- (int)installPkg:(in bycopy NSString *)pkgPath target:(in bycopy NSString *)aTarget env:(in bycopy NSString *)aEnv
{
	[self setTaskIsRunning:NO];
	[self setTaskResult:99];
	
	[self runInstallPkgTask:pkgPath target:aTarget env:aEnv];
	
	while (taskIsRunning && [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]]);
	return taskResult;
}

-(void)runInstallPkgTask:(NSString *)pkg target:(NSString *)target env:(NSString *)aEnv
{
    
	NSArray *appArgs = [NSArray arrayWithObjects:@"-verboseR", @"-allow", @"-pkg", pkg, @"-target", target, nil];
	logit(lcl_vDebug,@"Pkg Install Args: %@",appArgs);
	
	task = [[NSTask alloc] init];
    [task setLaunchPath: INSTALLER_BIN_PATH];
    [task setArguments: appArgs];
	
	NSDictionary *defaultEnvironment = [[NSProcessInfo processInfo] environment];
	NSMutableDictionary *environment = [[NSMutableDictionary alloc] initWithDictionary:defaultEnvironment];
	[environment setObject:@"YES" forKey:@"NSUnbufferedIO"];
	[environment setObject:@"1" forKey:@"COMMAND_LINE_INSTALL"];
	
	if (aEnv) {
		if ([aEnv isEqualToString:@"NA"] == NO && [[aEnv trim] length] > 0) {
			NSArray *l_envArray;
			NSArray *l_envItems;
			l_envArray = [aEnv componentsSeparatedByString:@","];
			for (id item in l_envArray) {
				l_envItems = nil;
				l_envItems = [item componentsSeparatedByString:@"="];
				if ([l_envItems count] == 2) {
					logit(lcl_vDebug,@"Setting env variable(%@=%@).",[l_envItems objectAtIndex:0],[l_envItems objectAtIndex:1]);
					[environment setObject:[l_envItems objectAtIndex:1] forKey:[l_envItems objectAtIndex:0]];
				} else {
					logit(lcl_vError,@"Unable to set env variable. Variable not well formed %@",item);
				}
			}	
		}	
	}
	
	[task setEnvironment:environment];
	
    pipe_task = [NSPipe pipe];
    [task setStandardOutput: pipe_task];
    [task setStandardError: pipe_task];
	
    fh_task = [pipe_task fileHandleForReading];
	
	[[NSNotificationCenter defaultCenter] addObserver:self 
											 selector:@selector(taskCompleted:) 
												 name:NSTaskDidTerminateNotification 
											   object:task];
	
	[[NSNotificationCenter defaultCenter] addObserver: self
											 selector: @selector(taskDataAvailable:)
												 name: NSFileHandleReadCompletionNotification
											   object: fh_task];
	
	[self setTaskIsRunning:YES];
	[task launch];
	[fh_task readInBackgroundAndNotify];
}

#pragma mark Reboot Methods
- (void)setLogoutHook
{
    // MP 2.2.0 & Mac OS X 10.9 Support, now using /private/tmp/.MPAuthRun
    NSString *_atFile = MP_AUTHRUN_FILE;
    NSString *_rbFile = @"/private/tmp/.MPRebootRun.plist";
    NSString *_rbText = @"reboot";
    // Mac OS X 10.9 Support, now using /private/tmp/.MPAuthRun
    NSDictionary *rebootPlist = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:@"reboot"];
    [rebootPlist writeToFile:_rbFile atomically:YES];
    [_rbText writeToFile:_atFile atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    NSDictionary *_fileAttr =  [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedLong:0777],@"NSFilePosixPermissions",nil];
    [[NSFileManager defaultManager] setAttributes:_fileAttr ofItemAtPath:_rbFile error:NULL];
    [[NSFileManager defaultManager] setAttributes:_fileAttr ofItemAtPath:_atFile error:NULL];
}

#pragma mark Notifications
- (void)taskDataAvailable:(NSNotification *)aNotification
{
    NSData *incomingData = [[aNotification userInfo] objectForKey:NSFileHandleNotificationDataItem];
    if (incomingData && [incomingData length])
    {
        NSString *incomingText = [[NSString alloc] initWithData:incomingData encoding:NSASCIIStringEncoding];
        logit(lcl_vDebug,@"%@",incomingText);
		
        [fh_task readInBackgroundAndNotify];
        return;
    }
}

+ (BOOL)isConsoleUserLoggedIn
{
    BOOL result = YES;
	
	SCDynamicStoreRef store = SCDynamicStoreCreate(NULL, (CFStringRef)@"LocalUserLoggedIn", NULL, NULL);
	CFStringRef consoleUserName;
    consoleUserName = SCDynamicStoreCopyConsoleUser(store, NULL, NULL);
	
    if (consoleUserName != NULL)
    {
		logit(lcl_vInfo,@"%@ is currently logged in.",(__bridge NSString *)consoleUserName);
        CFRelease(consoleUserName);
    } else {
		logit(lcl_vInfo,@"No console user logged in.");
		result = NO;
	}
	
    return result;
}

- (void)openRebootApp
{
	NSString *rebootApp = [NSString stringWithFormat:@"%@/MPReboot.app", MP_ROOT_CLIENT];
	
	NSString *identifier = [[NSBundle bundleWithPath:rebootApp] bundleIdentifier];
	NSWorkspace *ws = [NSWorkspace sharedWorkspace];	
	NSArray *apps = [ws valueForKeyPath:@"launchedApplications.NSApplicationBundleIdentifier"];
	if ([apps containsObject:identifier] == NO) {
		[[NSWorkspace sharedWorkspace] openFile:rebootApp];
	} else {
		logit(lcl_vInfo,@"%@, is already running.",rebootApp);
	}
}

- (void)taskCompleted:(NSNotification *)aNotification
{
	[self setTaskIsRunning:NO];
    int exitCode = [[aNotification object] terminationStatus];
	[self setTaskResult:exitCode];
	
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}


@end
