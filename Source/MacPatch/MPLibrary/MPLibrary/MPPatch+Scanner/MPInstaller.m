//
//  MPInstaller.m
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

#import "MPInstaller.h"
#import "MPFileUtils.h"
#import <SystemConfiguration/SystemConfiguration.h>


#undef  ql_component
#define ql_component lcl_cMPInstaller

@interface MPInstaller ()
{
	NSPipe			*pipe_task;
	NSFileHandle	*fh_task;
}

@property (nonatomic, assign, readwrite) BOOL taskIsRunning;
@property (nonatomic, assign, readwrite) int taskResult;
@property (nonatomic, strong) NSTask *task;

@end

@implementation MPInstaller

@synthesize taskIsRunning;
@synthesize task;
@synthesize taskResult;


/**
 Installs all packages from a given path

 @param aPath directory containing package(s)
 @param aEnv installer environment string
 @return int (0 = Sucess)
 */
- (int)installPkgFromPath:(NSString *)aPath environment:(NSString *)aEnv
{
	int result = 0;
	
	NSArray *dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:aPath error:nil];
	NSPredicate *fltr = [NSPredicate predicateWithFormat:@"(SELF like [cd] '*.pkg') OR (SELF like [cd] '*.mpkg')"];
	NSArray *onlyPkgs = [dirContents filteredArrayUsingPredicate:fltr];
	
	int pkgInstallResult = -1;
	for (NSString *pkg in onlyPkgs)
	{
		NSString *pkgPath = [aPath stringByAppendingPathComponent:pkg];
		pkgInstallResult = [self installPkgToRoot:pkgPath env:aEnv];
		if (pkgInstallResult != 0) {
			result++;
		}
	}
	
	return result;
}

- (int)installPkgToRoot:(NSString *)pkgPath
{
	return [self installPkg:pkgPath target:@"/" env:nil];
}

- (int)installPkgToRoot:(NSString *)pkgPath env:(NSString *)aEnv;
{
	if([aEnv isKindOfClass:[NSNull class]]) {
		aEnv = nil;
	}
	return [self installPkg:pkgPath target:@"/" env:aEnv];
}

- (int)installPkg:(NSString *)pkgPath target:(NSString *)aTarget env:(NSString *)aEnv
{
	[self setTaskIsRunning:NO];
	[self setTaskResult:99];
	
	if([aEnv isKindOfClass:[NSNull class]]) {
		aEnv = nil;
	}
	/*
	[self runInstallPkgTask:pkgPath target:aTarget env:aEnv];
	
	while (taskIsRunning && [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]]);
	 */
	NSError *taskErr = nil;
	NSString *result = [self runInstallPkgTask:pkgPath target:aTarget env:aEnv error:&taskErr];
	qldebug(@"Task Result: %@",result);
	return taskResult;
}

- (NSString *)runInstallPkgTask:(NSString *)pkg target:(NSString *)target env:(NSString *)aEnv error:(NSError **)err
{
	if([aEnv isKindOfClass:[NSNull class]]) {
		aEnv = nil;
	}
	// CEH - Improvement, add setting to allow configuration of install from unsigned pkgs -allowUntrusted
	NSArray *appArgs = @[@"-verboseR", @"-allow", @"-pkg", pkg, @"-target", target];
	qldebug(@"Pkg Install Args: %@",appArgs);
	
	NSError *taskErr = nil;
	MPNSTask *mpTask = [MPNSTask new];
	
	NSDictionary *defaultEnvironment = [[NSProcessInfo processInfo] environment];
	NSMutableDictionary *environment = [[NSMutableDictionary alloc] initWithDictionary:defaultEnvironment];
	[environment setObject:@"YES" forKey:@"NSUnbufferedIO"];
	[environment setObject:@"1" forKey:@"COMMAND_LINE_INSTALL"];
	
	if (aEnv)
	{
		if ([aEnv isEqualToString:@"NA"] == NO && [[aEnv trim] length] > 0)
		{
			NSArray *l_envArray;
			NSArray *l_envItems;
			l_envArray = [aEnv componentsSeparatedByString:@","];
			for (id item in l_envArray)
			{
				l_envItems = nil;
				l_envItems = [item componentsSeparatedByString:@"="];
				if ([l_envItems count] == 2)
				{
					qldebug(@"Setting env variable(%@=%@).",[l_envItems objectAtIndex:0],[l_envItems objectAtIndex:1]);
					[environment setObject:[l_envItems objectAtIndex:1] forKey:[l_envItems objectAtIndex:0]];
				}
				else
				{
					qlerror(@"Unable to set env variable. Variable not well formed %@",item);
				}
			}
		}
	}
	 
	NSString *result = [mpTask runTask:INSTALLER_BIN_PATH binArgs:appArgs environment:environment error:&taskErr];
	if (taskErr)
	{
		*err = taskErr;
		qlerror(@"Error: %@",taskErr.localizedDescription);
		self.taskResult = 1;
	} else {
		self.taskResult = 0;
	}
	
	return result;
}

- (int)installDotAppFrom:(NSString *)aDir action:(MPAppInstallType)installType
{
	int result = 0;
	NSFileManager *fm = [NSFileManager defaultManager];
	NSArray *dirContents = [fm contentsOfDirectoryAtPath:aDir error:nil];
	NSPredicate *fltr = [NSPredicate predicateWithFormat:@"self ENDSWITH '.app'"];
	NSArray *onlyApps = [dirContents filteredArrayUsingPredicate:fltr];
	
	NSError *err = nil;
	for (NSString *app in onlyApps)
	{
		if ([fm fileExistsAtPath:[@"/Applications"  stringByAppendingPathComponent:app]])
		{
			qldebug(@"Found, %@. Now remove it.",[@"/Applications" stringByAppendingPathComponent:app]);
			[fm removeItemAtPath:[@"/Applications" stringByAppendingPathComponent:app] error:&err];
			if (err)
			{
				qlerror(@"%@",err.localizedDescription);
				result = 3;
				break;
			}
		}
		// Install The Application
		err = nil;
		switch (installType)
		{
			case kAppCopyTo:
				[fm copyItemAtPath:[aDir stringByAppendingPathComponent:app] toPath:[@"/Applications" stringByAppendingPathComponent:app] error:&err];
				break;
			case kAppMoveTo:
				[fm moveItemAtPath:[aDir stringByAppendingPathComponent:app] toPath:[@"/Applications" stringByAppendingPathComponent:app] error:&err];
				break;
			default:
				[fm copyItemAtPath:[aDir stringByAppendingPathComponent:app] toPath:[@"/Applications" stringByAppendingPathComponent:app] error:&err];
				break;
		}
		
		if (err)
		{
			qlerror(@"%@",err.localizedDescription);
			result = 2;
			break;
		}
		
		MPFileUtils *fu = [MPFileUtils new];
		err = nil;
		[fu setOwnership:[@"/Applications" stringByAppendingPathComponent:app] owner:@"root" group:@"admin" error:&err];
		if (err) qlwarning(@"%@",err.localizedDescription);
	}
	
	return result;
}

- (int)installPkgFromDMG:(NSString *)dmgPath environment:(NSString *)aEnv
{
	int result = 0;
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *mountID = [[NSUUID UUID] UUIDString];
	NSString *mountPoint = [@"/private/tmp" stringByAppendingPathComponent:mountID];
	
	result = [self mountDMG:dmgPath mountID:mountID];
	if (result != 0) return result;
	
	NSArray *dmgContents = [fm contentsOfDirectoryAtPath:mountPoint error:nil];
	NSPredicate *fltr = [NSPredicate predicateWithFormat:@"(SELF like [cd] '*.pkg') OR (SELF like [cd] '*.mpkg')"];
	NSArray *onlyPkgs = [dmgContents filteredArrayUsingPredicate:fltr];
	
	int pkgInstallResult = -1;
	for (NSString *pkg in onlyPkgs)
	{
		qlinfo(@"Begin installing %@",pkg);
		pkgInstallResult = [self installPkgToRoot:[mountPoint stringByAppendingPathComponent:pkg] env:aEnv];
		if (pkgInstallResult != 0) {
			qlerror(@"Failed to install package %@",[mountPoint stringByAppendingPathComponent:pkg]);
			result++;
		}
	}
	
	[self unmountDMG:mountID];
	return result;
}

- (int)installDotAppFromDMG:(NSString *)dmgPath
{
	int result = 0;
	NSString *mountID = [[NSUUID UUID] UUIDString];
	NSString *mountPoint = [@"/private/tmp" stringByAppendingPathComponent:mountID];
	
	result = [self mountDMG:dmgPath mountID:mountID];
	if (result != 0) return result;

	result = [self installDotAppFrom:mountPoint action:kAppCopyTo];
	
	[self unmountDMG:mountID];
	return result;
}

#pragma mark Reboot Methods
- (void)setLogoutHook
{
    // MP 2.2.0 & Mac OS X 10.9 Support, now using /private/tmp/.MPAuthRun
    NSString *_atFile = @"/private/tmp/.MPAuthRun";
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

- (void)taskCompleted:(NSNotification *)aNotification
{
	[self setTaskIsRunning:NO];
    int exitCode = [[aNotification object] terminationStatus];
	[self setTaskResult:exitCode];
	
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Private

- (int)mountDMG:(NSString *)aDMG mountID:(NSString *)mountID
{
	qlinfo(@"Mounting DMG %@",aDMG);
	/*
	NSString *swLoc = NULL;
	NSString *swLocBase = [[mp_SOFTWARE_DATA_DIR path] stringByAppendingPathComponent:@"sw"];
	swLoc = [NSString pathWithComponents:[NSArray arrayWithObjects:swLocBase,pkgID,[aDMG lastPathComponent], nil]];
	*/
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *mountPoint = [@"/private/tmp" stringByAppendingPathComponent:mountID];
	
	NSError *err = nil;
	if ([fm fileExistsAtPath:mountPoint])
	{
		[self unmountDMG:mountID];
		[fm createDirectoryAtPath:mountPoint withIntermediateDirectories:YES attributes:nil error:&err];
		if (err) logit(lcl_vError,@"%@",err.localizedDescription);
	}
	else
	{
		[fm createDirectoryAtPath:mountPoint withIntermediateDirectories:YES attributes:nil error:&err];
		if (err) logit(lcl_vError,@"%@",err.localizedDescription);
	}
	
	NSArray *args = [NSArray arrayWithObjects:@"attach", @"-mountpoint", mountPoint, aDMG, @"-nobrowse", nil];
	NSTask  *aTask = [[NSTask alloc] init];
	NSPipe  *pipe = [NSPipe pipe];
	
	[aTask setLaunchPath:@"/usr/bin/hdiutil"];
	[aTask setArguments:args];
	[aTask setStandardInput:pipe];
	[aTask setStandardOutput:[NSFileHandle fileHandleWithNullDevice]];
	[aTask setStandardError:[NSFileHandle fileHandleWithStandardError]];
	[aTask launch];
	//[[pipe fileHandleForWriting] writeData:[@"password" dataUsingEncoding:NSUTF8StringEncoding]];
	//[[pipe fileHandleForWriting] closeFile];
	[aTask waitUntilExit];
	int result = [aTask terminationStatus];
	if (result == 0) {
		qlinfo(@"DMG Mounted at %@",mountPoint);
	}
	return result;
}

- (int)unmountDMG:(NSString *)mountID
{
	qlinfo(@"Un-Mounting DMG");
	NSString *mountPoint = [@"/private/tmp" stringByAppendingPathComponent:mountID];
	
	NSArray       *args  = [NSArray arrayWithObjects:@"detach", mountPoint, @"-force", nil];
	NSTask        *aTask = [[NSTask alloc] init];
	NSPipe        *pipe  = [NSPipe pipe];
	
	[aTask setLaunchPath:@"/usr/bin/hdiutil"];
	[aTask setArguments:args];
	[aTask setStandardInput:pipe];
	[aTask setStandardOutput:[NSFileHandle fileHandleWithNullDevice]];
	[aTask setStandardError:[NSFileHandle fileHandleWithStandardError]];
	[aTask launch];
	//[[pipe fileHandleForWriting] writeData:[@"password" dataUsingEncoding:NSUTF8StringEncoding]];
	//[[pipe fileHandleForWriting] closeFile];
	[aTask waitUntilExit];
	
	int result = [aTask terminationStatus];
	if (result == 0) {
		qlinfo(@"DMG Un-mounted %@",mountPoint);
	}
	return result;
}
@end
