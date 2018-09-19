//
//  Software.m
//  MPAgent
//
//  Created by Charles Heizer on 7/26/18.
//  Copyright © 2018 LLNL. All rights reserved.
//

#import "Software.h"
#import "MacPatch.h"
#import <SystemConfiguration/SystemConfiguration.h>

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

@interface Software ()
{
	NSFileManager *fm;
	
	// Task Vars
	NSTask              *task;
	NSPipe              *pipe_task;
	NSFileHandle        *fh_task;
	MPSettings			*settings;
}

@property (strong)              NSTimer     *timeoutTimer;
@property (nonatomic, assign)   int         taskTimeoutValue;
@property (nonatomic, assign)   BOOL        taskTimedOut;
@property (nonatomic, assign)   BOOL        taskIsRunning;
@property (nonatomic, assign)   int         installtaskResult;

@end

@implementation Software

@synthesize timeoutTimer;
@synthesize taskTimeoutValue;
@synthesize taskTimedOut;
@synthesize taskIsRunning;
@synthesize installtaskResult;

- (id)init
{
	self = [super init];
	if (self) {
		fm = [NSFileManager defaultManager];
		
		[self setTaskTimeoutValue:1800];
		[self setTaskIsRunning:NO];
		[self setTaskTimedOut:NO];
		settings = [MPSettings sharedInstance];
		
	}
	return self;
}

- (BOOL)downloadSWTask:(NSDictionary *)swTask error:(NSError **)err
{
	BOOL taskCanBeInstalled = [self softwareTaskCriteriaCheck:swTask];
	if (!taskCanBeInstalled) {
		NSMutableDictionary *errorDetail = [NSMutableDictionary dictionary];
		[errorDetail setValue:@"Software Task failed basic criteria check." forKey:NSLocalizedDescriptionKey];
		*err = [NSError errorWithDomain:@"gov.llnl.mp.sw.install" code:1001 userInfo:errorDetail];
		return NO;
	}
	
	logit(lcl_vInfo,@"Installing %@ (%@).",swTask[@"name"],swTask[@"id"]);
	logit(lcl_vInfo,@"INFO: %@",[swTask valueForKeyPath:@"Software.sw_type"]);
	
	// Create Path to download software to
	NSString *swLoc = NULL;
	NSString *swLocBase = [SOFTWARE_DATA_DIR stringByAppendingPathComponent:@"sw"];
	swLoc = [NSString pathWithComponents:@[swLocBase, swTask[@"id"]]];
	
	// Verify Disk space requirements before downloading and installing
	long long stringToLong = 0;
	stringToLong = [[swTask valueForKeyPath:@"Software.sw_size"] longLongValue];
	
	MPDiskUtil *mpd = [[MPDiskUtil alloc] init];
	if ([mpd diskHasEnoughSpaceForPackage:stringToLong] == NO)
	{
		logit(lcl_vError,@"This system does not have enough free disk space to install the following software %@",swTask[@"name"]);
		return NO;
	}
	
	// Create Download URL
	NSString *_url = [@"/mp-content" stringByAppendingPathComponent:[swTask valueForKeyPath:@"Software.sw_url"]];
	logit(lcl_vDebug,@"Download software from: %@",[swTask valueForKeyPath:@"Software.sw_type"]);
	
	NSError *dlErr = nil;
	MPHTTPRequest *req = [[MPHTTPRequest alloc] init];
	NSString *dlPath = [req runSyncFileDownload:_url downloadDirectory:NSTemporaryDirectory() error:&dlErr];
	
	if (dlErr) {
		logit(lcl_vError,@"Error[%d], trying to download file.",(int)[dlErr code]);
		return NO;
	}
	if (!dlPath) {
		logit(lcl_vError,@"Error, downloaded file path is nil.");
		logit(lcl_vError,@"No install will occure.");
		return NO;
	}
	
	// Create Destination Dir
	dlErr = nil;
	if ([fm fileExistsAtPath:swLoc] == NO) {
		[fm createDirectoryAtPath:swLoc withIntermediateDirectories:YES attributes:nil error:&dlErr];
		if (dlErr) {
			logit(lcl_vError,@"Error[%d], trying to create destination directory. %@.",(int)[dlErr code],swLoc);
		}
	}
	
	// Move Downloaded File to Destination
	if ([fm fileExistsAtPath:[swLoc stringByAppendingPathComponent:[dlPath lastPathComponent]]]) {
		// File Exists, remove it first
		dlErr = nil;
		[fm removeItemAtPath:[swLoc stringByAppendingPathComponent:[dlPath lastPathComponent]] error:&dlErr];
		if (dlErr) {
			logit(lcl_vError,@"%@",dlErr.localizedDescription);
			return NO;
		}
	}
	dlErr = nil;
	[fm moveItemAtPath:dlPath toPath:[swLoc stringByAppendingPathComponent:[dlPath lastPathComponent]] error:&dlErr];
	if (dlErr) {
		logit(lcl_vError,@"Error[%d], trying to move downloaded file to %@.",(int)[dlErr code],swLoc);
		logit(lcl_vError,@"No install will occure.");
		return NO;
	}
	return YES;
}


- (int)installSoftwareTask:(NSDictionary *)swTaskDict
{
	NSError *err = nil;
	// Download SW
	if (![self downloadSWTask:swTaskDict error:&err]) {
		return 1;
	}
	
	
	int result = 0;
	NSString *pkgType = [[swTaskDict valueForKeyPath:@"Software.sw_type"] uppercaseString];
	MPCrypto *mpCrypto = [[MPCrypto alloc] init];
	NSString *fHash;
	MPAsus *mpa = [[MPAsus alloc] init];
	NSArray *pathComp;
	NSString *zipFileName;
	NSString *dmgFile;
	err = nil;
	
	if ([pkgType isEqualToString:@"SCRIPTZIP"])
	{
		zipFileName = [[swTaskDict valueForKeyPath:@"Software.sw_url"] lastPathComponent];
		NSString *zipFile = [NSString pathWithComponents:@[SOFTWARE_DATA_DIR,@"sw",swTaskDict[@"id"],zipFileName]];
		logit(lcl_vInfo,@"Verify %@ (%@)",swTaskDict[@"name"],zipFileName);
		
		fHash = [mpCrypto md5HashForFile:zipFile];
		logit(lcl_vInfo,@"%@: %@",zipFile,fHash);
		logit(lcl_vInfo,@"== %@",[swTaskDict valueForKeyPath:@"Software.sw_hash"]);
		if (![[fHash uppercaseString] isEqualToString:[swTaskDict valueForKeyPath:@"Software.sw_hash"]]) {
			logit(lcl_vError,@"Error unable to verify software hash for file %@.",[zipFile lastPathComponent]);
			return 1;
		}
		
		logit(lcl_vInfo,@"Unzipping file %@.",zipFile);
		[mpa unzip:zipFile error:&err];
		if (err) {
			logit(lcl_vError,@"Error unzipping file %@. %@",zipFile,[err description]);
			return 1;
		}
		
		// Run Pre Install Script
		if ([self runInstallScript:swTaskDict[@"Software"] type:0] == NO) {
			result = 1;
			return result;
		}
		
		// Copy App To Applications
		NSString *mountPoint = NULL;
		NSString *mountPointBase = [SOFTWARE_DATA_DIR stringByAppendingPathComponent:@"sw"];
		mountPoint = [mountPointBase stringByAppendingPathComponent:swTaskDict[@"id"]];
		result = [self runScript:mountPoint];
		
		// Run Post Install Script, if copy was good
		if (result == 0)
		{
			if ([self runInstallScript:swTaskDict[@"Software"] type:1] == NO) {
				logit(lcl_vTrace,@"Error running post install script. Just log it as the install was good.");
			}
		}
		
	}
	else if ([pkgType isEqualToString:@"PACKAGEZIP"])
	{
		zipFileName = [[swTaskDict valueForKeyPath:@"Software.sw_url"] lastPathComponent];
		pathComp = @[SOFTWARE_DATA_DIR,@"sw",swTaskDict[@"id"],zipFileName];
		NSString *zipFile = [NSString pathWithComponents:pathComp];
	
		fHash = [mpCrypto md5HashForFile:zipFile];
		if (![[fHash uppercaseString] isEqualToString:[swTaskDict valueForKeyPath:@"Software.sw_hash"]]) {
			logit(lcl_vError,@"Error unable to verify software hash for file %@.",[zipFile lastPathComponent]);
			return 1;
		}
		
		logit(lcl_vInfo,@"Unzipping file %@.",zipFile);
		[mpa unzip:zipFile error:&err];
		if (err) {
			logit(lcl_vError,@"Error unzipping file %@. %@",zipFile,[err description]);
			return 1;
		}
		// Run Pre Install Script
		if ([self runInstallScript:swTaskDict[@"Software"] type:0] == NO) {
			result = 1;
			return result;
		}
		
		result = [self installPkgFromZIP:swTaskDict[@"id"] environment:swTaskDict[@"pkgEnv"]];
		
		// Run Post Install Script, if copy was good
		if (result == 0)
		{
			if ([self runInstallScript:swTaskDict[@"Software"] type:1] == NO) {
				logit(lcl_vTrace,@"Error running post install script. Just log it as the install was good.");
			}
		}
		
	}
	else if ([pkgType isEqualToString:@"APPZIP"])
	{
		zipFileName = [[swTaskDict valueForKeyPath:@"Software.sw_url"] lastPathComponent];
		pathComp = @[SOFTWARE_DATA_DIR,@"sw",swTaskDict[@"id"],zipFileName];
		NSString *zipFile = [NSString pathWithComponents:pathComp];
		
		fHash = [mpCrypto md5HashForFile:zipFile];
		if (![[fHash uppercaseString] isEqualToString:[swTaskDict valueForKeyPath:@"Software.sw_hash"]]) {
			logit(lcl_vError,@"Error unable to verify software hash for file %@.",[zipFile lastPathComponent]);
			return 1;
		}

		logit(lcl_vInfo,@"Unzipping file %@.",zipFile);
		[mpa unzip:zipFile error:&err];
		if (err) {
			logit(lcl_vError,@"Error unzipping file %@. %@",zipFile,[err description]);
			return 1;
		}
		
		// Run Pre Install Script
		if ([self runInstallScript:swTaskDict[@"Software"] type:0] == NO) {
			result = 1;
			return result;
		}
		
		// Copy App To Applications
		NSString *mountPoint = NULL;
		NSString *mountPointBase = [SOFTWARE_DATA_DIR stringByAppendingPathComponent:@"sw"];
		mountPoint = [mountPointBase stringByAppendingPathComponent:swTaskDict[@"id"]];
		result = [self copyAppFrom:mountPoint action:1];
		
		// Run Post Install Script, if copy was good
		if (result == 0)
		{
			if ([self runInstallScript:swTaskDict[@"Software"] type:1] == NO) {
				logit(lcl_vTrace,@"Error running post install script. Just log it as the install was good.");
			}
		}
		
	}
	else if ([pkgType isEqualToString:@"PACKAGEDMG"])
	{
		dmgFile = [self downloadedSWPath:swTaskDict];
		
		fHash = [mpCrypto md5HashForFile:dmgFile];
		logit(lcl_vInfo,@"%@: %@",dmgFile,fHash);
		logit(lcl_vInfo,@"== %@",[swTaskDict valueForKeyPath:@"Software.sw_hash"]);
		if (![[fHash uppercaseString] isEqualToString:[swTaskDict valueForKeyPath:@"Software.sw_hash"]]) {
			logit(lcl_vError,@"Error unable to verify software hash for file %@.",[dmgFile lastPathComponent]);
			return 1;
		}
		
		int m = -1;
		m = [self mountDMG:[swTaskDict valueForKeyPath:@"Software.sw_url"] packageID:swTaskDict[@"id"]];
		if (m == 0) {
			// Run Pre Install Script
			if ([self runInstallScript:swTaskDict[@"Software"] type:0] == NO) {
				result = 1;
				return result;
			}
			
			// Run PKG Installs
			result = [self installPkgFromDMG:swTaskDict[@"id"] environment:[swTaskDict valueForKeyPath:@"Software.sw_env_var"]];
			
			// Run Post Install Script, if copy was good
			if (result == 0)
			{
				if ([self runInstallScript:swTaskDict[@"Software"] type:1] == NO) {
					logit(lcl_vTrace,@"Error running post install script. Just log it as the install was good.");
				}
			}
		}
		
	}
	else if ([pkgType isEqualToString:@"APPDMG"])
	{
		dmgFile = [self downloadedSWPath:swTaskDict];
		
		fHash = [mpCrypto md5HashForFile:dmgFile];
		if (![[fHash uppercaseString] isEqualToString:[swTaskDict valueForKeyPath:@"Software.sw_hash"]]) {
			logit(lcl_vError,@"Error unable to verify software hash for file %@.",[dmgFile lastPathComponent]);
			logit(lcl_vError,@"%@: %@ (%@)",dmgFile,fHash,[swTaskDict valueForKeyPath:@"Software.sw_hash"]);
			return 1;
		}
		
		int m = -1;
		m = [self mountDMG:[swTaskDict valueForKeyPath:@"Software.sw_url"] packageID:swTaskDict[@"id"]];
		if (m == 0) {
			// Run Pre Install Script
			if ([self runInstallScript:swTaskDict[@"Software"] type:0] == NO) {
				result = 1;
				return result;
			}
			
			// Copy App To Applications
			result = [self copyAppFromDMG:swTaskDict[@"id"]];
			
			// Run Post Install Script, if copy was good
			if (result == 0)
			{
				if ([self runInstallScript:swTaskDict[@"Software"] type:1] == NO) {
					logit(lcl_vTrace,@"Error running post install script. Just log it as the install was good.");
				}
			}
		}
		
	}
	else
	{
		// Install Type Not Supported
		result = 2;
	}
	
	// ***********************************************************
	// Software was installed, now patch if bundle_id is present
	//
	if (result == 0)
	{
		[self recordInstalledRequiredSoftware:swTaskDict[@"id"]];
		if ([[swTaskDict valueForKeyPath:@"Software.auto_patch"] intValue] == 1)
		{
			NSString *bundle_id = [swTaskDict valueForKeyPath:@"Software.patch_bundle_id"];
			if (bundle_id.length >= 2) {
				[self scanAndUpdateUsingBundleID:bundle_id];
			}
		}
	}

	return result;
}

- (BOOL)recordRequiredSoftware:(NSArray *)ids
{
	[settings refresh];
	NSString *cGroupID = settings.agent.groupId;
	NSMutableDictionary *reqPlist = [NSMutableDictionary dictionaryWithContentsOfFile:SOFTWARE_REQUIRED_PLIST];
	
	NSMutableArray *array = reqPlist[@"requiredSoftware"];
	for (NSMutableDictionary *cg in array)
	{
		// Find our dictionary for our client group
		if ([cg[@"clientGroup"] isEqualToString:cGroupID])
		{
			NSMutableSet *newSet = [NSMutableSet new];
			[newSet addObjectsFromArray:[cg[@"required"] copy]];
			[newSet addObjectsFromArray:ids];
			cg[@"required"] = [[newSet allObjects] mutableCopy];
		}
	}
	
	[reqPlist writeToFile:SOFTWARE_REQUIRED_PLIST atomically:NO];
	return YES;
}

- (BOOL)recordInstalledRequiredSoftware:(NSString *)tuuid
{
	[settings refresh];
	NSString *cGroupID = settings.agent.groupId;
	
	NSMutableDictionary *reqPlist = [NSMutableDictionary dictionaryWithContentsOfFile:SOFTWARE_REQUIRED_PLIST];
	NSMutableArray *array = reqPlist[@"requiredSoftware"];
	
	for (NSMutableDictionary *cg in array)
	{
		// Find our dictionary for our client group
		if ([cg[@"clientGroup"] isEqualToString:cGroupID])
		{
			NSMutableArray *iArr = [cg[@"installed"] mutableCopy];
			[iArr addObject:@{@"tuuid":tuuid,@"idate":[NSDate date]}];
			cg[@"installed"] = iArr;
		}
	}
	
	[reqPlist writeToFile:SOFTWARE_REQUIRED_PLIST atomically:NO];
	return YES;
}

- (BOOL)isSoftwareTaskInstalled:(NSString *)tuuid
{
	[settings refresh];
	NSString *cGroupID = settings.agent.groupId;
	NSMutableDictionary *reqPlist = [NSMutableDictionary dictionaryWithContentsOfFile:SOFTWARE_REQUIRED_PLIST];
	NSArray *array = reqPlist[@"requiredSoftware"];

	for (NSDictionary *cg in array)
	{
		// Find our dictionary for our client group
		if ([cg[@"clientGroup"] isEqualToString:cGroupID])
		{
			NSArray *installed = cg[@"installed"];
			NSPredicate *predicate = [NSPredicate predicateWithFormat:@"tuuid CONTAINS[cd] %@",tuuid];
			NSArray *filteredArray = [installed filteredArrayUsingPredicate:predicate];
			if (filteredArray.count == 1) {
				return YES; // Found
			}
		}
	}

	return NO;
}

#pragma mark - Private Methods

- (NSString *)downloadedSWPath:(NSDictionary *)dict
{
	NSString *swFile;
	NSString *swFileName = [[dict valueForKeyPath:@"Software.sw_url"] lastPathComponent];
	swFile = [NSString pathWithComponents:@[SOFTWARE_DATA_DIR,@"sw",dict[@"id"],swFileName]];
	return swFile;
}

// Private
- (BOOL)softwareTaskCriteriaCheck:(NSDictionary *)aTask
{
	logit(lcl_vInfo,@"Checking %@ criteria.",[aTask objectForKey:@"name"]);
	
	MPOSCheck *mpos = [[MPOSCheck alloc] init];
	NSDictionary *_SoftwareCriteria = [aTask objectForKey:@"SoftwareCriteria"];
	
	// OSArch
	if ([mpos checkOSArch:[_SoftwareCriteria objectForKey:@"arch_type"]]) {
		logit(lcl_vDebug,@"OSArch=TRUE: %@",[_SoftwareCriteria objectForKey:@"arch_type"]);
	} else {
		logit(lcl_vInfo,@"OSArch=FALSE: %@",[_SoftwareCriteria objectForKey:@"arch_type"]);
		return NO;
	}
	
	// OSType
	if ([mpos checkOSType:[_SoftwareCriteria objectForKey:@"os_type"]]) {
		logit(lcl_vDebug,@"OSType=TRUE: %@",[_SoftwareCriteria objectForKey:@"os_type"]);
	} else {
		logit(lcl_vInfo,@"OSType=FALSE: %@",[_SoftwareCriteria objectForKey:@"os_type"]);
		return NO;
	}
	// OSVersion
	if ([mpos checkOSVer:[_SoftwareCriteria objectForKey:@"os_vers"]]) {
		logit(lcl_vDebug,@"OSVersion=TRUE: %@",[_SoftwareCriteria objectForKey:@"os_vers"]);
	} else {
		logit(lcl_vInfo,@"OSVersion=FALSE: %@",[_SoftwareCriteria objectForKey:@"os_vers"]);
		return NO;
	}
	
	mpos = nil;
	return YES;
}

#pragma mark Task methods
- (int)runTask:(NSString *)aBinPath binArgs:(NSArray *)aBinArgs environment:(NSString *)env
{
	NSString		*tmpStr;
	NSMutableData	*data;
	NSData			*dataChunk = nil;
	NSException		*error = nil;
	
	
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
	
	// Parse the Environment variables for the install
	NSDictionary *defaultEnvironment = [[NSProcessInfo processInfo] environment];
	NSMutableDictionary *environment = [[NSMutableDictionary alloc] initWithDictionary:defaultEnvironment];
	[environment setObject:@"YES" forKey:@"NSUnbufferedIO"];
	[environment setObject:@"1" forKey:@"COMMAND_LINE_INSTALL"];
	
	if ([env isEqualToString:@"NA"] == NO && [[env trim] length] > 0)
	{
		NSArray *l_envArray;
		NSArray *l_envItems;
		l_envArray = [env componentsSeparatedByString:@","];
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
	
	[task setEnvironment:environment];
	logit(lcl_vDebug,@"[task][environment]: %@",environment);
	[task setLaunchPath:aBinPath];
	logit(lcl_vDebug,@"[task][setLaunchPath]: %@",aBinPath);
	[task setArguments:aBinArgs];
	logit(lcl_vDebug,@"[task][setArguments]: %@",aBinArgs);
	
	// Launch The NSTask
	@try {
		[task launch];
		// If timeout is set start it ...
		if (taskTimeoutValue != 0) {
			[NSThread detachNewThreadSelector:@selector(taskTimeoutThread) toTarget:self withObject:nil];
		}
	}
	@catch (NSException *e)
	{
		logit(lcl_vError,@"Install returned error. %@\n%@",[e reason],[e userInfo]);
		taskResult = 1;
		goto done;
	}
	
	data = [[NSMutableData alloc] init];
	dataChunk = nil;
	error = nil;
	
	while(taskTimedOut == NO && ((dataChunk = [[aPipe fileHandleForReading] availableDataOrError:&error]) && [dataChunk length] && error == nil))
	{
		// If the data is not null, then post the data back to the client and log it locally
		tmpStr = [[NSString alloc] initWithData:dataChunk encoding:NSUTF8StringEncoding];
		if ([[tmpStr trim] length] != 0)
		{
			if ([tmpStr containsString:@"PackageKit: Missing bundle path"] == NO) {
				logit(lcl_vInfo,@"%@",tmpStr);
			} else {
				logit(lcl_vDebug,@"%@",tmpStr);
			}
		}
		
		[data appendData:dataChunk];
		tmpStr = nil;
	}
	
	[[aPipe fileHandleForReading] closeFile];
	
	if (taskTimedOut == YES) {
		logit(lcl_vError,@"Task was terminated due to timeout.");
		[NSThread sleepForTimeInterval:5.0];
		[task terminate];
		taskResult = 1;
		goto done;
	}
	
	if([data length] && error == nil)
	{
		if ([task isRunning])
		{
			for (int i = 0; i < 30; i++)
			{
				if ([task isRunning]) {
					[NSThread sleepForTimeInterval:1.0];
				} else {
					break;
				}
			}
			// Task should be complete
			logit(lcl_vInfo,@"Terminate Software Task.");
			[task terminate];
		}
		
		int status = [task terminationStatus];
		logit(lcl_vInfo,@"swTask terminationStatus: %d",status);
		if (status == 0) {
			taskResult = 0;
		} else {
			taskResult = 1;
		}
	} else {
		logit(lcl_vError,@"Install returned error. Code:[%d]",[task terminationStatus]);
		taskResult = 1;
	}
	
done:
	
	if(timeoutTimer) {
		[timeoutTimer invalidate];
	}
	
	[self setTaskIsRunning:NO];
	return taskResult;
}

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
	[self setInstalltaskResult:exitCode];
}

- (void)taskTimeoutThread
{
	@autoreleasepool
	{
		[timeoutTimer invalidate];
		
		logit(lcl_vInfo,@"Timeout is set to %d",taskTimeoutValue);
		NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:taskTimeoutValue
														  target:self
														selector:@selector(taskTimeout:)
														userInfo:nil
														 repeats:NO];
		[self setTimeoutTimer:timer];
		
		while (taskTimedOut == NO && [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]]);
		
	}
	
}

- (void)taskTimeout:(NSNotification *)aNotification
{
	logit(lcl_vInfo,@"Task timedout, killing task.");
	[timeoutTimer invalidate];
	[self setTaskTimedOut:YES];
	[task terminate];
}

#pragma mark Install methods
- (int)installPkgFromDMG:(NSString *)pkgID environment:(NSString *)aEnv
{
	int result = 0;
	NSString *mountPoint = NULL;
	NSString *mountPointBase = [SOFTWARE_DATA_DIR stringByAppendingPathComponent:@"dmg"];
	mountPoint = [mountPointBase stringByAppendingPathComponent:pkgID];
	
	NSArray *dirContents = [fm contentsOfDirectoryAtPath:mountPoint error:nil];
	NSPredicate *fltr = [NSPredicate predicateWithFormat:@"(SELF like [cd] '*.pkg') OR (SELF like [cd] '*.mpkg')"];
	NSArray *onlyPkgs = [dirContents filteredArrayUsingPredicate:fltr];
	
	int pkgInstallResult = -1;
	NSArray *installArgs;
	for (NSString *pkg in onlyPkgs)
	{
		installArgs = @[@"-verboseR", @"-pkg", [mountPoint stringByAppendingPathComponent:pkg], @"-target", @"/"];
		pkgInstallResult = [self runTask:INSTALLER_BIN_PATH binArgs:installArgs environment:aEnv];
		if (pkgInstallResult != 0) {
			result++;
		}
	}
	
	[self unmountDMG:mountPoint packageID:pkgID];
	return result;
}

- (int)installPkgFromZIP:(NSString *)pkgID environment:(NSString *)aEnv
{
	int result = 0;
	NSString *mountPoint = NULL;
	mountPoint = [NSString pathWithComponents:@[SOFTWARE_DATA_DIR,@"sw",pkgID]];
	
	NSArray *dirContents = [fm contentsOfDirectoryAtPath:mountPoint error:nil];
	NSPredicate *fltr = [NSPredicate predicateWithFormat:@"(SELF like [cd] '*.pkg') OR (SELF like [cd] '*.mpkg')"];
	NSArray *onlyPkgs = [dirContents filteredArrayUsingPredicate:fltr];
	
	int pkgInstallResult = -1;
	NSArray *installArgs;
	for (NSString *pkg in onlyPkgs)
	{
		installArgs = [NSArray arrayWithObjects:@"-verboseR", @"-pkg", [NSString pathWithComponents:[NSArray arrayWithObjects:SOFTWARE_DATA_DIR,@"sw",pkgID, pkg, nil]], @"-target", @"/", nil];
		pkgInstallResult = [self runTask:INSTALLER_BIN_PATH binArgs:installArgs environment:aEnv];
		if (pkgInstallResult != 0) {
			result++;
		}
	}
	
	return result;
}

- (BOOL)runInstallScript:(NSDictionary *)aSWDict type:(int)aScriptType
{
	MPScript *mps = [[MPScript alloc] init];
	NSString *_script;
	if (aScriptType == 0)
	{
		if ([aSWDict hasKey:@"sw_pre_install"]) {
			if ([[aSWDict objectForKey:@"sw_pre_install"] isEqualToString:@""] == NO)
			{
				@try
				{
					_script = [[aSWDict objectForKey:@"sw_pre_install"] decodeBase64AsString];
					if (![mps runScript:_script]) {
						logit(lcl_vError,@"Error running pre install script. No install will occure.");
						return NO;
					} else {
						return YES;
					}
				}
				@catch (NSException *exception) {
					logit(lcl_vError,@"Exception Error running pre install script. No install will occure.");
					logit(lcl_vError,@"%@",exception);
					return NO;
				}
			} else {
				return YES;
			}
		} else {
			return YES;
		}
	}
	else if (aScriptType == 1)
	{
		if ([aSWDict hasKey:@"sw_post_install"]) {
			if ([[aSWDict objectForKey:@"sw_post_install"] isEqualToString:@""] == NO)
			{
				@try
				{
					_script = [[aSWDict objectForKey:@"sw_post_install"] decodeBase64AsString];
					if (![mps runScript:_script]) {
						logit(lcl_vError,@"Error running post install script.");
						return NO;
					} else {
						return YES;
					}
				}
				@catch (NSException *exception) {
					logit(lcl_vError,@"Exception Error running post install script.");
					logit(lcl_vError,@"%@",exception);
					return NO;
				}
			} else {
				return YES;
			}
		} else {
			return YES;
		}
	} else {
		return NO;
	}
}

- (int)runScript:(NSString *)aDir
{
	int result = 0;
	NSArray *dirContents = [fm contentsOfDirectoryAtPath:aDir error:nil];
	NSPredicate *fltr = [NSPredicate predicateWithFormat:@"(SELF like [cd] '*.sh') OR (SELF like [cd] '*.rb') OR (SELF like [cd] '*.py')"];
	NSArray *onlyScripts = [dirContents filteredArrayUsingPredicate:fltr];
	
	NSError *err = nil;
	NSString *scriptText = nil;
	MPScript *mps = nil;
	for (NSString *scpt in onlyScripts)
	{
		err = nil;
		scriptText = [NSString stringWithContentsOfFile:[aDir stringByAppendingPathComponent:scpt] encoding:NSUTF8StringEncoding error:&err];
		if (err) {
			logit(lcl_vError,@"Error reading script string: %@",[err description]);
			logit(lcl_vError,@"%@",[err description]);
			result = 3;
			break;
		}
		mps = [[MPScript alloc] init];
		if ([mps runScript:scriptText]) {
			result = 0;
		} else {
			result = 1;
			break;
		}
		mps = nil;
	}
	
	return result;
}

- (int)copyAppFrom:(NSString *)aDir action:(int)action
{
	int result = 0;
	NSArray *dirContents = [fm contentsOfDirectoryAtPath:aDir error:nil];
	NSPredicate *fltr = [NSPredicate predicateWithFormat:@"self ENDSWITH '.app'"];
	NSArray *onlyApps = [dirContents filteredArrayUsingPredicate:fltr];
	
	NSError *err = nil;
	for (NSString *app in onlyApps) {
		if ([fm fileExistsAtPath:[@"/Applications"  stringByAppendingPathComponent:app]]) {
			logit(lcl_vInfo,@"Found, %@. Now remove it.",[@"/Applications" stringByAppendingPathComponent:app]);
			[fm removeItemAtPath:[@"/Applications" stringByAppendingPathComponent:app] error:&err];
			if (err) {
				logit(lcl_vError,@"%@",[err description]);
				result = 3;
				break;
			}
		}
		err = nil;
		if (action == 0) {
			[fm copyItemAtPath:[aDir stringByAppendingPathComponent:app] toPath:[@"/Applications" stringByAppendingPathComponent:app] error:&err];
		} else if (action == 1) {
			[fm moveItemAtPath:[aDir stringByAppendingPathComponent:app] toPath:[@"/Applications" stringByAppendingPathComponent:app] error:&err];
		} else {
			[fm copyItemAtPath:[aDir stringByAppendingPathComponent:app] toPath:[@"/Applications" stringByAppendingPathComponent:app] error:&err];
		}
		
		if (err) {
			logit(lcl_vError,@"%@",[err description]);
			result = 2;
			break;
		}
		
		[self changeOwnershipOfApp:[@"/Applications" stringByAppendingPathComponent:app] owner:@"root" group:@"admin"];
	}
	
	return result;
}

- (int)copyAppFromDMG:(NSString *)pkgID
{
	int result = 0;
	NSString *mountPoint = NULL;
	NSString *mountPointBase = [SOFTWARE_DATA_DIR stringByAppendingPathComponent:@"dmg"];
	mountPoint = [mountPointBase stringByAppendingPathComponent:pkgID];
	
	result = [self copyAppFrom:mountPoint action:0];
	
	[self unmountDMG:mountPoint packageID:pkgID];
	return result;
}

- (int)mountDMG:(NSString *)aDMG packageID:(NSString *)pkgID
{
	
	NSString *swLoc = NULL;
	NSString *swLocBase = [SOFTWARE_DATA_DIR stringByAppendingPathComponent:@"sw"];
	swLoc = [NSString pathWithComponents:@[swLocBase,pkgID,[aDMG lastPathComponent]]];
	
	NSString *mountPoint = NULL;
	NSString *mountPointBase = [SOFTWARE_DATA_DIR stringByAppendingPathComponent:@"dmg"];
	mountPoint = [mountPointBase stringByAppendingPathComponent:pkgID];
	
	NSError *err = nil;
	if (![fm fileExistsAtPath:mountPoint]) {
		[fm createDirectoryAtPath:mountPoint withIntermediateDirectories:YES attributes:nil error:&err];
		if (err) {
			logit(lcl_vError,@"%@",[err description]);
		}
	} else {
		[self unmountDMG:aDMG packageID:pkgID];
		[fm createDirectoryAtPath:mountPoint withIntermediateDirectories:YES attributes:nil error:&err];
		if (err) {
			logit(lcl_vError,@"%@",[err description]);
		}
	}
	
	if ([fm fileExistsAtPath:swLoc] == NO) {
		logit(lcl_vError,@"File \"%@\" does not exist.",swLoc);
		return 1;
	}
	
	NSArray *args = [NSArray arrayWithObjects:@"attach", @"-mountpoint", mountPoint, swLoc, @"-nobrowse", nil];
	NSTask  *aTask = [[NSTask alloc] init];
	NSPipe  *pipe = [NSPipe pipe];
	
	[aTask setLaunchPath:@"/usr/bin/hdiutil"];
	[aTask setArguments:args];
	[aTask setStandardInput:pipe];
	[aTask setStandardOutput:[NSFileHandle fileHandleWithNullDevice]];
	[aTask setStandardError:[NSFileHandle fileHandleWithStandardError]];
	[aTask launch];
	[aTask waitUntilExit];
	int result = [aTask terminationStatus];
	if (result == 0) {
		//
	}
	return result;
}

- (int)unmountDMG:(NSString *)aDMG packageID:(NSString *)pkgID
{
	NSString *mountPoint = NULL;
	NSString *mountPointBase = [SOFTWARE_DATA_DIR stringByAppendingPathComponent:@"dmg"];
	mountPoint = [mountPointBase stringByAppendingPathComponent:pkgID];
	
	NSArray       *args  = [NSArray arrayWithObjects:@"detach", mountPoint, @"-force", nil];
	NSTask        *aTask = [[NSTask alloc] init];
	NSPipe        *pipe  = [NSPipe pipe];
	
	[aTask setLaunchPath:@"/usr/bin/hdiutil"];
	[aTask setArguments:args];
	[aTask setStandardInput:pipe];
	[aTask setStandardOutput:[NSFileHandle fileHandleWithNullDevice]];
	[aTask setStandardError:[NSFileHandle fileHandleWithStandardError]];
	[aTask launch];
	[aTask waitUntilExit];
	
	int result = [aTask terminationStatus];
	if (result == 0) {
		
	}
	return result;
}

- (void)changeOwnershipOfApp:(NSString *)aApp owner:(NSString *)aOwner group:(NSString *)aGroup
{
	NSDictionary *permDict = [NSDictionary dictionaryWithObjectsAndKeys:
							  aOwner,NSFileOwnerAccountName,
							  aGroup,NSFileGroupOwnerAccountName,nil];
	
	NSError *error = nil;
	[fm setAttributes:permDict ofItemAtPath:aApp error:&error];
	if(error){
		qlerror(@"Error settings permission %@",[error description]);
		return;
	}
	
	error = nil;
	NSArray *aContents = [fm subpathsOfDirectoryAtPath:aApp error:&error];
	if(error){
		qlerror(@"Error subpaths of Directory %@.\n%@",aApp,[error description]);
		return;
	}
	if (!aContents) {
		qlerror(@"No contents found for %@",aApp);
		return;
	}
	
	for (NSString *i in aContents)
	{
		error = nil;
		[[NSFileManager defaultManager] setAttributes:permDict ofItemAtPath:[aApp stringByAppendingPathComponent:i] error:&error];
		if(error){
			qlerror(@"Error settings permission %@",[error description]);
		}
	}
	
}

#pragma mark Patching Methods

- (NSDictionary *)scanForPatchUsingBundleID:(NSString *)aBundleID error:(NSError **)error
{
	NSDictionary 		*result = nil;
	NSMutableArray      *approvedUpdatesArray = [NSMutableArray new];
	NSMutableDictionary *tmpDict;
	
	// Get Patch Data For BundleID
	// Get patch data from web service based using bundle id
	MPRESTfull *mprest = [[MPRESTfull alloc] init];
	NSError *err = nil;
	NSDictionary *patchForBundleID = [mprest getPatchForBundleID:aBundleID error:&err];
	if (err) {
		logit(lcl_vError,@"%@",err.localizedDescription);
		*error = err;
		return result;
	}
	
	if (!patchForBundleID) {
		logit(lcl_vError,@"There was a issue getting the approved patch data for the bundle id, scan will exit.");
		return result;
	}
	
	logit(lcl_vInfo,@"Scanning for custom patch vulnerabilities...");
	logit(lcl_vInfo,@"Scanning for custom patch vulnerabilities for %@", aBundleID);
	MPAsus *mpAsus = [[MPAsus alloc] init];
	NSMutableArray *customPatchesFound = (NSMutableArray *)[mpAsus scanForCustomUpdateUsingBundleID:aBundleID];
	
	logit(lcl_vDebug,@"Custom Patches Needed: %@",customPatchesFound);
	logit(lcl_vDebug,@"Approved Patches: %@",patchForBundleID);
	
	// Filter List of Patches containing only the approved patches
	NSDictionary *customPatch;
	logit(lcl_vInfo,@"Building approved patch list...");
	for (int i=0; i < [customPatchesFound count]; i++)
	{
		customPatch	= [customPatchesFound objectAtIndex:i];
		if ([customPatch[@"patch_id"] isEqualTo:patchForBundleID[@"puuid"]])
		{
			logit(lcl_vInfo,@"Patch %@ approved for update.",customPatch[@"patch"]);
			tmpDict = [[NSMutableDictionary alloc] init];
			[tmpDict setObject:customPatch[@"patch"] forKey:@"patch"];
			[tmpDict setObject:customPatch[@"description"] forKey:@"description"];
			[tmpDict setObject:customPatch[@"restart"] forKey:@"restart"];
			[tmpDict setObject:customPatch[@"version"] forKey:@"version"];
			[tmpDict setObject:customPatch[@"patch_id"] forKey:@"patch_id"];
			[tmpDict setObject:customPatch[@"bundleID"] forKey:@"bundleID"];
			[tmpDict setObject:patchForBundleID forKey:@"patchData"];
			
			[approvedUpdatesArray addObject:tmpDict];
			tmpDict = nil;
			break;
		}
	}
	
	if (approvedUpdatesArray.count == 1) {
		result = [approvedUpdatesArray[0] copy];
		logit(lcl_vInfo,@"Patch found, %@ (%@)",result[@"patch"],result[@"patch_id"]);
	} else {
		logit(lcl_vInfo,@"No update found for %@",aBundleID);
	}
	
	return result;
}

- (void)scanAndUpdateUsingBundleID:(NSString *)aBundleID
{
	// Scan for update
	NSError *err = nil;
	NSDictionary *patch;
	patch = [self scanForPatchUsingBundleID:aBundleID error:&err];
	if (err) {
		qlerror(@"%@",err.localizedDescription);
		return;
	}
	if (!patch) {
		qlerror(@"No patch found for %@.",aBundleID);
		return;
	}
	
	// ***************************************************
	// Vars
	//
	int	launchRebootWindow = 0;
	
	// ***************************************************
	// Check for console user
	//
	logit(lcl_vInfo, @"Checking for any logged in users.");
	BOOL hasConsoleUserLoggedIn = TRUE;
	@try {
		hasConsoleUserLoggedIn = [self isLocalUserLoggedIn];
	}
	@catch (NSException * e) {
		logit(lcl_vInfo, @"Error getting console user status. %@",e);
	}
	
	if (hasConsoleUserLoggedIn == YES)
	{
		// Check if patch needs a reboot
		if ([patch[@"restart"] stringToBoolValue] == YES)
		{
			logit(lcl_vInfo,@"%@(%@) requires a reboot, this patch will be installed on logout.",patch[@"patch"],patch[@"version"]);
			launchRebootWindow++;
		}
	}
	
	if (launchRebootWindow > 0)
	{
		// ***************************************************
		// Check for valid patch
		//
		NSDictionary *patchData = nil;
		if (patch[@"patchData"])
		{
			if ([patch[@"patchData"] isKindOfClass:[NSDictionary class]]) {
				patchData = patch[@"patchData"];
			} else {
				logit(lcl_vInfo,@"patchData Object found was not of type dictionary. No install will occur.");
				return;
			}
		}
		
		// ***************************************************
		// Start patch install
		//
		
		// Vars
		MPAsus 	 	*mpAsus = [[MPAsus alloc] init];
		MPScript 	*mpScript = nil;
		MPInstaller *mpInstaller;
		MPCrypto *crypto;
		NSString *dlURL;
		NSString *dlPatchLoc;
		
		logit(lcl_vInfo,@"Start install for patch %@.",patch[@"patch"]);
		// *****************************
		// First we need to download the update
		//
		@try {
			logit(lcl_vInfo,@"Start download for patch from %@",[patchData[@"pkg_url"] lastPathComponent]);
			//Pre Proxy Config
			dlURL = [NSString stringWithFormat:@"/mp-content%@",patchData[@"pkg_url"]];
			logit(lcl_vInfo,@"Download patch from: %@",dlURL);
			err = nil;
			dlPatchLoc = [mpAsus downloadUpdate:dlURL error:&err];
			if (err) {
				logit(lcl_vError,@"Error downloading a patch, skipping %@. Err Message: %@",patch[@"patch"],err.localizedDescription);
				return;
			}
			logit(lcl_vInfo,@"File downloaded to %@",dlPatchLoc);
		}
		@catch (NSException *e) {
			logit(lcl_vError,@"%@", e);
			return;
		}
		
		// *****************************
		// Validate hash, before install
		//
		logit(lcl_vInfo,@"Validating downloaded patch.");
		crypto = [[MPCrypto alloc] init];
		NSString *fileHash = [crypto md5HashForFile:dlPatchLoc];
		crypto = nil;
		logit(lcl_vInfo,@"Downloaded file hash: %@ (%@)",fileHash,patchData[@"pkg_hash"]);
		if ([[patchData[@"pkg_hash"] uppercaseString] isEqualTo:[fileHash uppercaseString]] == NO)
		{
			logit(lcl_vError,@"The downloaded file did not pass the file hash validation. No install will occur.");
			return;
		}
		
		// *****************************
		// Now we need to unzip
		//
		logit(lcl_vInfo,@"Uncompressing patch, to begin install.");
		logit(lcl_vInfo,@"Begin decompression of file, %@",dlPatchLoc);
		err = nil;
		[mpAsus unzip:dlPatchLoc error:&err];
		if (err) {
			logit(lcl_vError,@"Error decompressing a patch, skipping %@. Err Message:%@",patch[@"patch"],err.localizedDescription);
			return;
		}
		logit(lcl_vInfo,@"Patch has been decompressed.");
		
		// *****************************
		// Run PreInstall Script
		//
		if ([patchData[@"pkg_preinstall"] length] > 0 && [patchData[@"pkg_preinstall"] isEqualTo:@"NA"] == NO) {
			logit(lcl_vInfo,@"Begin pre install script.");
			NSString *preInstScript = [patchData[@"pkg_preinstall"] decodeBase64AsString];
			logit(lcl_vDebug,@"preInstScript=%@",preInstScript);
			
			mpScript = [[MPScript alloc] init];
			if ([mpScript runScript:preInstScript] == NO)
			{
				logit(lcl_vError,@"Error running pre-install script.");
				mpScript = nil;
				return;
			}
			mpScript = nil;
		}
		
		// *****************************
		// Install the update
		//
		@try
		{
			NSString *pkgPath;
			NSString *pkgBaseDir = [dlPatchLoc stringByDeletingLastPathComponent];
			NSString *pkgFileName = [dlPatchLoc lastPathComponent];
			NSPredicate *pkgPredicate = [NSPredicate predicateWithFormat:@"(SELF like [cd] '*.pkg') OR (SELF like [cd] '*.mpkg')"];
			NSArray *pkgList = [[fm contentsOfDirectoryAtPath:pkgBaseDir error:NULL] filteredArrayUsingPredicate:pkgPredicate];
			int installResult = -1;
			
			// Install pkg(s)
			for (int i = 0; i < [pkgList count]; i++)
			{
				pkgPath = [pkgBaseDir stringByAppendingPathComponent:[pkgList objectAtIndex:i]];
				logit(lcl_vInfo,@"Installing %@",pkgFileName);
				logit(lcl_vInfo,@"Start install of %@",pkgPath);
				mpInstaller = [[MPInstaller alloc] init];
				installResult = [mpInstaller installPkg:pkgPath target:@"/" env:patchData[@"pkg_env_var"]];
				if (installResult != 0) {
					logit(lcl_vError,@"Error installing package, error code %d.",installResult);
					return;
				} else {
					logit(lcl_vInfo,@"%@ was installed successfully.",pkgPath);
				}
			} // End Loop
		}
		@catch (NSException *e) {
			logit(lcl_vError,@"%@", e);
			logit(lcl_vError,@"Error attempting to install patch, skipping %@. Err Message:%@",[patch objectForKey:@"patch"],err.localizedDescription);
			return;
		}
		
		// *****************************
		// Run PostInstall Script
		//
		if ([patchData[@"pkg_postinstall"] length] > 0 && [patchData[@"pkg_postinstall"] isEqualTo:@"NA"] == NO) {
			logit(lcl_vInfo,@"Begin post install script.");
			NSString *postInstScript = [patchData[@"pkg_postinstall"] decodeBase64AsString];
			logit(lcl_vDebug,@"postInstScript=%@",postInstScript);
			
			mpScript = [[MPScript alloc] init];
			if ([mpScript runScript:postInstScript] == NO)
			{
				logit(lcl_vError,@"Error running post-install script.");
			}
			mpScript = nil;
		}
		
		// *****************************
		// Install is complete, post result to web service
		//
		@try
		{
			NSString *urlPath = [NSString stringWithFormat:@"/api/v1/client/patch/install/%@/%@/%@",patch[@"patch_id"],@"third",settings.ccuid];
			logit(lcl_vInfo,@"Posting patch (%@) install to web service.",patch[@"patch_id"]);
			[self postDataToWS:urlPath data:nil];
		}
		@catch (NSException *e) {
			logit(lcl_vError,@"%@", e);
		}
		
		logit(lcl_vInfo,@"Patch install completed.");
	}
	else
	{
		logit(lcl_vInfo,@"Patches that require reboot need to be installed. Opening reboot dialog now.");
		// 10.9 support
		NSString *_rbFile = @"/private/tmp/.MPRebootRun.plist";
		NSString *_rbText = @"reboot";
		// Mac OS X 10.9 Support, now using /private/tmp/.MPAuthRun
		NSDictionary *rebootPlist = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:@"reboot"];
		[rebootPlist writeToFile:_rbFile atomically:YES];
		[_rbText writeToFile:MP_AUTHRUN_FILE atomically:YES encoding:NSUTF8StringEncoding error:NULL];
		NSDictionary *_fileAttr =  [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedLong:0777],@"NSFilePosixPermissions",nil];
		[fm setAttributes:_fileAttr ofItemAtPath:_rbFile error:NULL];
		[fm setAttributes:_fileAttr ofItemAtPath:MP_AUTHRUN_FILE error:NULL];
	}
}

- (BOOL)postDataToWS:(NSString *)urlPath data:(NSDictionary *)data
{
	MPHTTPRequest *req;
	MPWSResult *result;
	
	req = [[MPHTTPRequest alloc] init];
	result = [req runSyncPOST:urlPath body:data];
	
	if (result.statusCode >= 200 && result.statusCode <= 299) {
		logit(lcl_vInfo,@"[Software][postDataToWS]: Data post to web service (%@), returned true.", urlPath);
		logit(lcl_vDebug,@"Data Result: %@",result.result);
	} else {
		logit(lcl_vError,@"Data post to web service (%@), returned false.", urlPath);
		logit(lcl_vDebug,@"%@",result.toDictionary);
		return NO;
	}
	
	return YES;
}

- (BOOL)isLocalUserLoggedIn
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
		result = NO;
	}
	
	return result;
}

@end
