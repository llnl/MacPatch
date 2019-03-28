//
//  MPAgentExecController.m
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

#import "MPAgentExecController.h"
#import "MacPatch.h"
#import "MPSettings.h"

#import <SystemConfiguration/SystemConfiguration.h>
#include <sys/reboot.h>

@interface MPAgentExecController ()
{
	NSFileManager *fm;
    MPSettings *settings;
}
@property (nonatomic, strong)            NSArray   *approvedPatches;
@property (nonatomic, assign, readwrite) int        errorCode;
@property (nonatomic, strong, readwrite) NSString  *errorMsg;
@property (nonatomic, assign, readwrite) int        needsReboot;

// Web Services
- (void)postInstallResults:(int)resultNo resultText:(NSString *)resultString task:(NSDictionary *)taskDict;

// Misc
- (void)iLoadStatus:(NSString *)str, ...;
- (void)killTaskUsing:(NSString *)aTaskName;

@end

@implementation MPAgentExecController

@synthesize errorCode;
@synthesize errorMsg;
@synthesize needsReboot;

@synthesize _appPid;
@synthesize iLoadMode;
@synthesize forceTaskRun;
@synthesize approvedPatches;

@synthesize mp_SOFTWARE_DATA_DIR;

- (id)init
{
    self = [super init];
    if (self)
    {
        fm          = [NSFileManager defaultManager];
        settings    = [MPSettings sharedInstance];
        
		[self setILoadMode:NO];
		[self setForceTaskRun:NO];
		[self setErrorCode:-1];
		[self setErrorMsg:@""];
    }
    return self;
}

// Scan Host for Patches
// Found patches are stored in self.appprovedPatches array
- (void)scanForPatches:(MPPatchContentType)contentType forceRun:(BOOL)aForceRun
{
	qlinfo(@"Begin scanning system for patches.");
	qlinfo(@"Scanning system for %@ type patches.",MPPatchContentType_toString[contentType]);
	
	MPPatching *scanner = [MPPatching new];
	NSArray *approvedUpdatesArray = [scanner scanForPatchesUsingTypeFilter:contentType forceRun:aForceRun];
	
    qlinfo(@"Approved patches: %d",(int)approvedUpdatesArray.count);
    qldebug(@"Approved patches to install: %@",approvedUpdatesArray);
	
    if (settings.agent.preStagePatches)
    {
        qlinfo(@"Staging Updates is enabled.");
		[self stagePatches:approvedUpdatesArray];
    }

    // Added a global notification to update image icon of MPClientStatus
    if (contentType != kCriticalPatches)
    {
        // We only update notification if a normal scan has run
		[[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"kRefreshStatusIconNotification" object:nil userInfo:nil options:NSNotificationPostToAllSessions];
        [self setApprovedPatches:[approvedUpdatesArray copy]];
		// CEH
		// Need to write approved updates to database
    }
	
    qlinfo(@"Patch Scan Completed.");
}

// Download and Stage approved patches
- (void)stagePatches:(NSArray *)patches
{
	if ([patches count] >= 1)
	{
		NSMutableArray *approvedUpdateIDsArray = [NSMutableArray new];
		MPAsus *mpa = [[MPAsus alloc] init];
		MPCrypto *crypto = [MPCrypto new];
		for (NSDictionary *patch in patches)
		{
			qlinfo(@"Pre staging update %@.",patch[@"patch"]);
			if ([patch[@"type"] isEqualToString:@"Apple"])
			{
				[mpa downloadAppleUpdate:patch[@"patch"]];
			}
			else
			{
				// This is to clean up non used patches
				[approvedUpdateIDsArray addObject:patch[@"patch_id"]];
				
				// CEH - Verify
				NSArray *pkgsFromPatch = patch[@"patches"][@"patches"];
				for (NSDictionary *_p in pkgsFromPatch)
				{
					NSError *dlErr = nil;
					NSString *stageDir = [NSString stringWithFormat:@"%@/Data/.stage/%@",MP_ROOT_CLIENT,patch[@"patch_id"]];
					NSString *downloadURL = [NSString stringWithFormat:@"/mp-content%@",_p[@"url"]];
					NSString *fileName = [_p[@"url"] lastPathComponent];
					NSString *stagedFilePath = [stageDir stringByAppendingPathComponent:fileName];
					
					if ([fm fileExistsAtPath:stagedFilePath])
					{
						// Migth want to check hash here
						qlinfo(@"Patch %@ is already pre-staged.",patch[@"patch"]);
						continue;
					}
					
					// Create Staging Dir
					BOOL isDir = NO;
					if ([fm fileExistsAtPath:stageDir isDirectory:&isDir])
					{
						if (isDir)
						{
							if ([fm fileExistsAtPath:stagedFilePath])
							{
								if ([[_p[@"hash"] uppercaseString] isEqualTo:[[crypto md5HashForFile:stagedFilePath] uppercaseString]])
								{
									qlinfo(@"Patch %@ has already been staged.",patch[@"patch"]);
									continue;
								}
								else
								{
									dlErr = nil;
									[fm removeItemAtPath:stagedFilePath error:&dlErr];
									if (dlErr)
									{
										qlerror(@"Unable to remove bad staged patch file %@",stagedFilePath);
										qlerror(@"Can not stage %@",patch[@"patch"]);
										continue;
									}
								}
							}
						}
						else
						{
							// Is not a dir but is a file, just remove it. It's in our space
							dlErr = nil;
							[fm removeItemAtPath:stageDir error:&dlErr];
							if (dlErr)
							{
								qlerror(@"Unable to remove bad staged directory/file %@",stageDir);
								qlerror(@"Can not stage %@",patch[@"patch"]);
								continue;
							}
						}
					}
					else
					{
						// Stage dir does not exists, create it.
						dlErr = nil;
						[fm createDirectoryAtPath:stageDir withIntermediateDirectories:YES attributes:nil error:&dlErr];
						if (dlErr)
						{
							qlerror(@"%@",dlErr.localizedDescription);
							qlerror(@"Can not stage %@",patch[@"patch"]);
							continue; // Error creating stage patch dir. Can not use it.
						}
					}
					
					qlinfo(@"Download patch from: %@",downloadURL);
					dlErr = nil;
					NSString *dlPatchLoc = [self downloadUpdate:downloadURL error:&dlErr];
					if (dlErr)
					{
						qlerror(@"%@",dlErr.localizedDescription);
					}
					qldebug(@"Downloaded patch to %@",dlPatchLoc);
					
					dlErr = nil;
					[fm moveItemAtPath:dlPatchLoc toPath:stagedFilePath error:&dlErr];
					if (dlErr)
					{
						qlerror(@"%@",dlErr.localizedDescription);
						continue; // Error creating stage patch dir. Can not use it.
					}
					qlinfo(@"%@ has been staged.",patch[@"patches"]);
					qldebug(@"Moved patch to: %@",stagedFilePath);
				}
			}
		}
		
		[self cleanupPreStagePatches:(NSArray *)approvedUpdateIDsArray];
	}
}

// Scan Host for Patches based on BundleID
// Found patches are stored in self.appprovedPatches array
- (void)scanForPatchUsingBundleID:(NSString *)aBundleID
{
	qlinfo(@"Begin scanning system for patches.");
	qlinfo(@"Scanning system for %@ type patches using bundleID.",MPPatchContentType_toString[kCustomPatches]);
	
	MPPatching *scanner = [MPPatching new];
	NSArray *approvedUpdatesArray = [scanner scanForPatchUsingBundleID:aBundleID];
	
	qlinfo(@"Approved patches: %d",(int)approvedUpdatesArray.count);
	qldebug(@"Approved patches to install: %@",approvedUpdatesArray);
	
	if (settings.agent.preStagePatches)
	{
		qlinfo(@"Staging Updates is enabled.");
		[self stagePatches:approvedUpdatesArray];
	}
	
	[self setApprovedPatches:[approvedUpdatesArray copy]];
	qlinfo(@"Patch Scan Completed.");
}

// NEW
- (void)patchScanAndUpdate:(MPPatchContentType)contentType bundleID:(NSString *)bundleID
{
	NSArray *updatesArray = [NSArray array];
	if (bundleID != NULL) {
		[self scanForPatchUsingBundleID:bundleID];
	} else {
		[self scanForPatches:contentType forceRun:NO];
	}
	
	updatesArray = [NSArray arrayWithArray:approvedPatches];
	
	// -------------------------------------------
	// If no updates, exit
	if (updatesArray.count <= 0)
	{
		qlinfo( @"No approved patches to install.");
		return;
	}
	
	// -------------------------------------------
	// Sort Array by patch install weight
	NSSortDescriptor *desc = [NSSortDescriptor sortDescriptorWithKey:@"patch_install_weight" ascending:YES];
	updatesArray = [updatesArray sortedArrayUsingDescriptors:[NSArray arrayWithObject:desc]];
	
	// -------------------------------------------
	// Check to see if client os type is allowed to perform updates.
	qlinfo( @"Checking system patching requirments.");
	NSDictionary *systeInfo = [MPSystemInfo osVersionInfo];
	NSString *_osType = systeInfo[@"ProductName"];
	qlinfo( @"OS Full Info: (%@)",systeInfo);
	qlinfo( @"OS Info: (%@)",_osType);
	if ([_osType.lowercaseString isEqualToString:@"mac os x"] || [_osType.lowercaseString isEqualToString:@"macos"])
	{
		if (settings.agent.patchClient)
		{
			if (settings.agent.patchClient == 0)
			{
				qlinfo(@"Host is a Mac OS X client and \"AllowClient\" property is set to false. No updates will be applied.");
				return;
			}
		}
	}

	if ([_osType.lowercaseString isEqualToString:@"mac os x server"])
	{
		if (settings.agent.patchServer)
		{
			if (settings.agent.patchServer == 0) {
				qlinfo(@"Host is a Mac OS X Server and \"AllowServer\" property is set to false. No updates will be applied.");
				return;
			}
		}
		else
		{
			qlinfo(@"Host is a Mac OS X Server and \"AllowServer\" property is not defined. No updates will be applied.");
			return;
		}
	}
	
	// -------------------------------------------
	// iLoad / Provisioning
	BOOL hasConsoleUserLoggedIn = TRUE;
	[self iLoadStatus:@"Updates to install: %d\n", (int)updatesArray.count];
	
	if (!iLoadMode)
	{
		// We know if the system is in iLoad/Provisioning mode that no one is
		// logged in. So we can patch and reboot.
		
		// Check for console user
		qlinfo( @"Checking for any logged in users.");
		@try
		{
			hasConsoleUserLoggedIn = [self isLocalUserLoggedIn];
			if (!hasConsoleUserLoggedIn)
			{
				NSError *fileErr = nil;
				[@"patch" writeToFile:MP_PATCH_ON_LOGOUT_FILE atomically:NO encoding:NSUTF8StringEncoding error:&fileErr];
				if (fileErr)
				{
					qlerror( @"Error writing out %@ file. %@", MP_PATCH_ON_LOGOUT_FILE, fileErr.localizedDescription);
				}
				else
				{
					// No need to continue, MPLoginAgent will perform the updates
					// Since no user is logged in.
					return;
				}
			}
		}
		@catch (NSException * e)
		{
			qlinfo( @"Error getting console user status. %@",e);
		}
	}
	
	// -------------------------------------------
	// Begin Patching
	MPPatching *patching = [MPPatching new];
	NSDictionary *patchingResult = [patching installPatchesUsingTypeFilter:updatesArray typeFilter:contentType];
	
	NSInteger patchesNeedingReboot = [patchingResult[@"patchesNeedingReboot"] integerValue];
	NSInteger rebootPatchesNeeded = [patchingResult[@"rebootPatchesNeeded"] integerValue];
	
	// -------------------------------------------
	// Update MP Client Status to reflect patch install
	[[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"kRefreshStatusIconNotification" object:nil userInfo:nil options:NSNotificationPostToAllSessions];
	
	
	// If any patches that were installed needed a reboot
	qldebug(@"Number of installed patches needing a reboot %ld.", (long)patchesNeedingReboot);
	if (patchesNeedingReboot > 0)
	{
		if (iLoadMode)
		{
			qlinfo(@"Patches have been installed that require a reboot. Please reboot the systems as soon as possible.");
			return;
		}
		if (!hasConsoleUserLoggedIn)
		{
			if (settings.agent.reboot)
			{
				if (settings.agent.reboot == 1)
				{
					qlinfo(@"Patches have been installed that require a reboot. Rebooting system now.");
					[NSTask launchedTaskWithLaunchPath:@"/bin/launchctl" arguments:@[@"reboot"]];
				}
				else
				{
					qlinfo(@"Patches have been installed that require a reboot. Please reboot the systems as soon as possible.");
					return;
				}
				
			}
		}
	}
	// Have Patches that need to be install requiring a reboot or patches that have been
	// installed require a reboot.
	if (patchesNeedingReboot > 0 || rebootPatchesNeeded > 0)
	{
		// CEH - Not Sure this will spawn reoot window
		qlinfo(@"Patches that require reboot need to be installed. Opening reboot dialog now.");
		[@"reboot" writeToFile:MP_PATCH_ON_LOGOUT_FILE atomically:YES encoding:NSUTF8StringEncoding error:NULL];
		[fm setAttributes:@{@"NSFilePosixPermissions":[NSNumber numberWithUnsignedLong:0777]} ofItemAtPath:MP_PATCH_ON_LOGOUT_FILE error:NULL];
	}
}

#pragma mark - Agent Updater(MPAgentUp2Date)
/**
 Scan for, and update the agent updater
 */
-(void)scanAndUpdateAgentUpdater
{
	qlinfo(@"Begin checking for agent updates.");
	NSDictionary *updateDataRaw = [self getAgentUpdaterInfo];
	if (!updateDataRaw) {
		qlerror(@"Unable to get update data needed.");
		return;
	}

    // Check to make sure the object is the right type
    // This needs to be fixed in the next version.
    if (![updateDataRaw isKindOfClass:[NSDictionary class]])
    {
        qlerror(@"Agent updater info is not available.");
        return;
    }

    // Check if update needed
	if (![updateDataRaw objectForKey:@"updateAvailable"] || [[updateDataRaw objectForKey:@"updateAvailable"] boolValue] == NO) {
		qlinfo(@"No update needed.");
		return;
	}

	if (![updateDataRaw objectForKey:@"SelfUpdate"]) {
		qlerror(@"No update data found.");
		return;
	}

	NSDictionary *updateData = [NSDictionary dictionaryWithDictionary:[updateDataRaw objectForKey:@"SelfUpdate"]];

	NSError *err = nil;
	NSString *downloadURL;
	NSString *downloadFileLoc;

	// *****************************
	// First we need to download the update
	@try
	{
		qlinfo(@"Start download for patch from %@",[updateData objectForKey:@"pkg_Url"]);
		//Pre Proxy Config
		downloadURL = [updateData objectForKey:@"pkg_Url"];
		qlinfo(@"Download patch from: %@",downloadURL);
		err = nil;
		downloadFileLoc = [self downloadUpdate:downloadURL error:&err];
		if (err) {
			qlerror(@"Error downloading update %@. Err Message: %@",[downloadURL lastPathComponent],[err localizedDescription]);
			return;
		}
		qlinfo(@"File downloaded to %@",downloadFileLoc);
	}
	@catch (NSException *e)
	{
		qlerror(@"%@", e);
		return;
	}

	// *****************************
	// Validate hash, before install
	qlinfo(@"Validating downloaded patch.");
	MPCrypto *_crypto = [[MPCrypto alloc] init];
	NSString *fileHash = [_crypto sha1HashForFile:downloadFileLoc];
	_crypto = nil;
	qlinfo(@"Validating download file.");
	qldebug(@"Downloaded file hash: (%@) (%@)",fileHash,[updateData objectForKey:@"pkg_Hash"]);
	qldebug(@"%@",updateData);
	if ([[[updateData objectForKey:@"pkg_Hash"] uppercaseString] isEqualToString:[fileHash uppercaseString]] == NO) {
		qlerror(@"The downloaded file did not pass the file hash validation. No install will occur.");
		return;
	}

	// *****************************
	// Now we need to unzip
	qlinfo(@"Uncompressing patch, to begin install.");
	qlinfo(@"Begin decompression of file, %@",downloadFileLoc);
	err = nil;
	MPFileUtils *fu = [MPFileUtils new];
	[fu unzip:downloadFileLoc error:&err];
	if (err) {
		qlerror(@"Error decompressing a update %@. Err Message:%@",[downloadURL lastPathComponent],[err localizedDescription]);
		return;
	}
	qlinfo(@"Update has been decompressed.");

	// *****************************
	// Install the update
	BOOL hadErr = NO;
	@try
	{
		NSString *pkgPath;
		NSString *pkgBaseDir = [downloadFileLoc stringByDeletingLastPathComponent];
		NSPredicate *pkgPredicate = [NSPredicate predicateWithFormat:@"(SELF like [cd] '*.pkg') OR (SELF like [cd] '*.mpkg')"];
		NSArray *pkgList = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:[downloadFileLoc stringByDeletingLastPathComponent] error:NULL] filteredArrayUsingPredicate:pkgPredicate];
		int installResult = -1;
		MPInstaller *mpInstaller;

		// Install pkg(s)
		for (int ii = 0; ii < [pkgList count]; ii++) {
			pkgPath = [NSString stringWithFormat:@"%@/%@",pkgBaseDir,[pkgList objectAtIndex:ii]];
			qlinfo(@"Installing %@",[pkgPath lastPathComponent]);
			qlinfo(@"Start install of %@",pkgPath);
			mpInstaller = [[MPInstaller alloc] init];
			installResult = [mpInstaller installPkgToRoot:pkgPath];
			if (installResult != 0) {
				qlerror(@"Error installing package, error code %d.",installResult);
				hadErr = YES;
				break;
			} else {
				qlinfo(@"%@ was installed successfully.",pkgPath);
			}
		} // End Loop
	}
	@catch (NSException *e) {
		qlerror(@"%@", e);
		qlerror(@"Error attempting to install update %@. Err Message:%@",[downloadURL lastPathComponent],[err localizedDescription]);
	}

	qlinfo(@"Checking for agent updates completed.");
	return;
}

// Private
- (NSDictionary *)getAgentUpdaterInfo
{
	NSString *updateAppPath = [MP_ROOT stringByAppendingPathComponent:@"Updater/MPAgentUp2Date"];

	NSError *error = nil;
	NSString *verString = @"0";
	MPNSTask *mpr = [[MPNSTask alloc] init];

	// If no or valid MP signature, replace and install
    NSError *err = nil;
    MPCodeSign *cs = [[MPCodeSign alloc] init];
    BOOL verifyDevBin = [cs verifyAppleDevBinary:updateAppPath error:&err];
    if (err) {
        qlerror(@"%ld: %@",err.code,err.localizedDescription);
    }
    cs = nil;
    if (verifyDevBin == YES)
    {
		verString = [mpr runTask:updateAppPath binArgs:[NSArray arrayWithObjects:@"-v", nil] error:&error];
		if (error) {
			qlerror(@"%@",[error description]);
			verString = @"0";
		}
	}

	// Check for updates
    NSString *urlPath = [@"/api/v1/agent/updater" stringByAppendingFormat:@"/%@/%@",settings.ccuid,verString];
    NSDictionary *result = [self getDataFromWS:urlPath];
    return result[@"data"];
}

#pragma mark - SW Dist Installs


/**
 Install a list of software tasks using a string of task ID's

 @param tasks - string of task ID's
 @param delimiter - delimter default is ","
 @return int
 */
- (int)installSoftwareTasksFromString:(NSString *)tasks delimiter:(NSString *)delimiter
{
    needsReboot = 0;
	NSString *_delimiter = @",";
	if (delimiter != NULL) _delimiter = delimiter;

    NSArray *_tasksArray = [tasks componentsSeparatedByString:_delimiter];
    if (!_tasksArray) {
        qlerror(@"Software tasks list was empty. No installs will occure.");
		qldebug(@"Task List String: %@",tasks);
        return 1;
    }

    for (NSString *_task in _tasksArray)
	{
		if (![self installSoftwareTask:_task]) return 1;
    }

    if (needsReboot >= 1) {
        qlerror(@"Software has been installed that requires a reboot.");
        return 2;
    }

    return 0;
}


/**
 Install all software tasks for a given group name.

 @param aGroupName - Group Name
 @return int
 */
- (int)installSoftwareTasksForGroup:(NSString *)aGroupName
{
    needsReboot = 0;
    int result = 1;
    
    NSArray *tasks;
    NSString *urlPath = [NSString stringWithFormat:@"/api/v2/sw/tasks/%@/%@",settings.ccuid, aGroupName];
    NSDictionary *data = [self getDataFromWS:urlPath];
    
    if (data[@"data"])
    {
        tasks = data[@"data"];
        if ([tasks count] <= 0) {
            qlerror(@"Group (%@) contains no tasks.",aGroupName);
            return 0;
        }
    }
    else
    {
        qlerror(@"No tasks for group %@ were found.",aGroupName);
        return result;
    }

    for (NSDictionary *task in tasks)
	{
		MPSoftware *software = [MPSoftware new];
        if (![software installSoftwareTask:task])
		{
            qlerror(@"FAILED to install task %@",[task objectForKey:@"name"]);
             result = 1;
        }
    }

    if (needsReboot >= 1) {
        qlerror(@"Software has been installed that requires a reboot.");
        result = 2;
    }

    return result;
}

/*
- (BOOL)installSoftwareWithTask:(NSDictionary *)aTask error:(NSError **)err
{
    BOOL taskCanBeInstalled = [self softwareTaskCriteriaCheck:aTask];
    if (!taskCanBeInstalled) {
        NSMutableDictionary *errorDetail = [NSMutableDictionary dictionary];
        [errorDetail setValue:@"Software Task failed basic criteria check." forKey:NSLocalizedDescriptionKey];
        *err = [NSError errorWithDomain:@"gov.llnl.mp.sw.install" code:1001 userInfo:errorDetail];
        return NO;
    }
    
    NSString *noteName = @"MPSWInstallStatus";
    NSString *tID = [aTask objectForKey:@"id"];
    [self postNotificationTo:noteName info:[NSString stringWithFormat:@"Installing [taskid:%@]: %@",tID,[aTask objectForKey:@"name"]] isGlobal:YES];
    qlinfo(@"Installing %@ (%@).",[aTask objectForKey:@"name"],[aTask objectForKey:@"id"]);
    qlinfo(@"INFO: %@",[aTask valueForKeyPath:@"Software.sw_type"]);

    // Create Path to download software to
    NSString *swLoc = NULL;
    NSString *swLocBase = [[mp_SOFTWARE_DATA_DIR path] stringByAppendingPathComponent:@"sw"];
    swLoc = [NSString pathWithComponents:[NSArray arrayWithObjects:swLocBase, [aTask objectForKey:@"id"], nil]];

    // Verify Disk space requirements before downloading and installing
    long long stringToLong = 0;
    stringToLong = [[aTask valueForKeyPath:@"Software.sw_size"] longLongValue];

    MPDiskUtil *mpd = [[MPDiskUtil alloc] init];
    if ([mpd diskHasEnoughSpaceForPackage:stringToLong] == NO)
    {
        qlerror(@"This system does not have enough free disk space to install the following software %@",[aTask objectForKey:@"name"]);
        return NO;
    }

    // Create Download URL
    [self postNotificationTo:noteName info:[NSString stringWithFormat:@"Downloading [taskid:%@]: %@",tID,[aTask objectForKey:@"name"]] isGlobal:YES];
    NSString *_url = [@"/mp-content" stringByAppendingPathComponent:[aTask valueForKeyPath:@"Software.sw_url"]];
    qldebug(@"Download software from: %@",[aTask valueForKeyPath:@"Software.sw_type"]);

    NSError *dlErr = nil;
    
    MPHTTPRequest *req = [[MPHTTPRequest alloc] init];
    NSString *dlPath = [req runSyncFileDownload:_url downloadDirectory:NSTemporaryDirectory() error:&dlErr];
    
    if (dlErr) {
        qlerror(@"Error[%d], trying to download file.",(int)[dlErr code]);
        return NO;
    }
    if (!dlPath) {
        qlerror(@"Error, downloaded file path is nil.");
        qlerror(@"No install will occure.");
        return NO;
    }

    // Create Destination Dir
    dlErr = nil;
    if ([fm fileExistsAtPath:swLoc] == NO) {
        [fm createDirectoryAtPath:swLoc withIntermediateDirectories:YES attributes:nil error:&dlErr];
        if (dlErr) {
            qlerror(@"Error[%d], trying to create destination directory. %@.",(int)[dlErr code],swLoc);
        }
    }

    // Move Downloaded File to Destination
    if ([fm fileExistsAtPath:[swLoc stringByAppendingPathComponent:[dlPath lastPathComponent]]]) {
        // File Exists, remove it first
        dlErr = nil;
        [fm removeItemAtPath:[swLoc stringByAppendingPathComponent:[dlPath lastPathComponent]] error:&dlErr];
        if (dlErr) {
            qlerror(@"%@",dlErr.localizedDescription);
            return NO;
        }
    }
    dlErr = nil;
    [fm moveItemAtPath:dlPath toPath:[swLoc stringByAppendingPathComponent:[dlPath lastPathComponent]] error:&dlErr];
    if (dlErr) {
        qlerror(@"Error[%d], trying to move downloaded file to %@.",(int)[dlErr code],swLoc);
        qlerror(@"No install will occure.");
        return NO;
    }

    qlinfo(@"Begin install for (%@).",[aTask objectForKey:@"name"]);
    int result = -1;
    int pResult = -1;

	MPSoftware *installer = [MPSoftware new];
	result = [installer installSoftwareTask:aTask];

    if (result == 0)
    {
        // Software has been installed, now flag for reboot
        if ([[aTask valueForKeyPath:@"Software.reboot"] isEqualTo:@"1"]) {
            needsReboot++;
        }
		
        if ([[aTask valueForKeyPath:@"Software.auto_patch"] isEqualTo:@"1"])
		{
            [self postNotificationTo:noteName info:@"Auto Patching is enabled, begin patching..." isGlobal:YES];
			MPPatching *patching = [MPPatching new];
			NSArray *patchNeeded = [patching scanForPatchUsingBundleID:[aTask valueForKeyPath:@"Software.patch_bundle_id"]];
			if (patchNeeded.count >= 1) {
				NSDictionary *patchResult = nil;
				patchResult = [patching installPatchesUsingTypeFilter:patchNeeded typeFilter:kCustomPatches];
			}
        }

        [self postNotificationTo:noteName info:[NSString stringWithFormat:@"Installing [taskid:%@]: %@ completed.",tID,[aTask objectForKey:@"name"]] isGlobal:YES];
        [self recordInstallSoftwareItem:aTask];

        [self postInstallResults:result resultText:@"" task:aTask];
        return YES;
    } else {
        [self postNotificationTo:noteName info:[NSString stringWithFormat:@"Failed [taskid:%@]: %@ failed to install.",tID,[aTask objectForKey:@"name"]] isGlobal:YES];
        return NO;
    }
    

    return NO;
}
 */

/**
 Private Method
 Install Software Task using software task ID

 @param swTaskID software task ID
 @return BOOL
 */
- (BOOL)installSoftwareTask:(NSString *)swTaskID
{
	BOOL result = NO;
    NSDictionary *task = [self getSoftwareTaskForID:swTaskID];
    if (!task) {
        return NO;
    }
	MPSoftware *software = [MPSoftware new];
	if ([software installSoftwareTask:task])
	{
		result = YES;
		if ([self softwareTaskRequiresReboot:task]) needsReboot++;
	}
    return result;
}

// Private
- (BOOL)recordInstallSoftwareItem:(NSDictionary *)dict
{
    NSString *installFile = [[mp_SOFTWARE_DATA_DIR path] stringByAppendingPathComponent:@".installed.plist"];
    NSMutableDictionary *installData = [[NSMutableDictionary alloc] init];
    [installData setObject:[NSDate date] forKey:@"installDate"];
    [installData setObject:[dict objectForKey:@"id"] forKey:@"id"];
    [installData setObject:[dict objectForKey:@"name"] forKey:@"name"];
    if ([dict objectForKey:@"sw_uninstall"]) {
        [installData setObject:[dict objectForKey:@"sw_uninstall"] forKey:@"sw_uninstall"];
    } else {
        [installData setObject:@"" forKey:@"sw_uninstall"];
    }
    NSMutableArray *_data;
    if ([fm fileExistsAtPath:installFile]) {
        _data = [NSMutableArray arrayWithContentsOfFile:installFile];
    } else {
        if (![fm fileExistsAtPath:[mp_SOFTWARE_DATA_DIR path]]) {
            NSDictionary *attributes = [NSDictionary dictionaryWithObject:[NSNumber numberWithShort:0777] forKey:NSFilePosixPermissions];
            [fm createDirectoryAtPath:[mp_SOFTWARE_DATA_DIR path] withIntermediateDirectories:YES attributes:attributes error:NULL];
        }
        _data = [NSMutableArray array];
    }
    [_data addObject:installData];
    [_data writeToFile:installFile atomically:YES];
    installData = nil;
    return YES;
}

// Private
- (void)postInstallResults:(int)resultNo resultText:(NSString *)resultString task:(NSDictionary *)taskDict
{
    MPSWTasks *swt = [[MPSWTasks alloc] init];
    int result = -1;
    result = [swt postInstallResults:resultNo resultText:resultString task:taskDict];
    swt = nil;
}

// Private
- (NSDictionary *)getSoftwareTaskForID:(NSString *)swTaskID
{
    NSDictionary *task = nil;
    NSDictionary *data = nil;
    
    NSString *urlPath = [NSString stringWithFormat:@"/api/v2/sw/task/%@/%@",settings.ccuid, swTaskID];
    data = [self getDataFromWS:urlPath];
    if (data[@"data"])
    {
        task = data[@"data"];
    }

    return task;
}


/**
 Private Method
 Query a Software Task for reboot requirement.

 @param task software task dictionary
 @return BOOL
 */
- (BOOL)softwareTaskRequiresReboot:(NSDictionary *)task
{
	BOOL result = NO;
	NSNumber *_rbNumber = [task valueForKeyPath:@"Software.reboot"];
	NSInteger _reboot = [_rbNumber integerValue];
	switch (_reboot) {
		case 0:
			result = NO;
			break;
		case 1:
			result = YES;
			break;
		default:
			break;
	}
	
	return result;
}

// Private
- (BOOL)softwareTaskCriteriaCheck:(NSDictionary *)aTask
{
    qlinfo(@"Checking %@ criteria.",[aTask objectForKey:@"name"]);
    
    MPOSCheck *mpos = [[MPOSCheck alloc] init];
    NSDictionary *_SoftwareCriteria = [aTask objectForKey:@"SoftwareCriteria"];
    
    // OSArch
    if ([mpos checkOSArch:[_SoftwareCriteria objectForKey:@"arch_type"]]) {
        qldebug(@"OSArch=TRUE: %@",[_SoftwareCriteria objectForKey:@"arch_type"]);
    } else {
        qlinfo(@"OSArch=FALSE: %@",[_SoftwareCriteria objectForKey:@"arch_type"]);
        return NO;
    }
    
    // OSType
    if ([mpos checkOSType:[_SoftwareCriteria objectForKey:@"os_type"]]) {
        qldebug(@"OSType=TRUE: %@",[_SoftwareCriteria objectForKey:@"os_type"]);
    } else {
        qlinfo(@"OSType=FALSE: %@",[_SoftwareCriteria objectForKey:@"os_type"]);
        return NO;
    }
    // OSVersion
    if ([mpos checkOSVer:[_SoftwareCriteria objectForKey:@"os_vers"]]) {
        qldebug(@"OSVersion=TRUE: %@",[_SoftwareCriteria objectForKey:@"os_vers"]);
    } else {
        qlinfo(@"OSVersion=FALSE: %@",[_SoftwareCriteria objectForKey:@"os_vers"]);
        return NO;
    }
    
    mpos = nil;
    return YES;
}

#pragma mark - Web Service Requests

- (BOOL)postDataToWS:(NSString *)urlPath data:(NSDictionary *)data
{
    MPHTTPRequest *req;
    MPWSResult *result;
    
    req = [[MPHTTPRequest alloc] init];
    result = [req runSyncPOST:urlPath body:data];
    
    if (result.statusCode >= 200 && result.statusCode <= 299) {
        qlinfo(@"[MPAgentExecController][postDataToWS]: Data post to web service (%@), returned true.", urlPath);
        //qldebug(@"Data post to web service (%@), returned true.", urlPath);
        qldebug(@"Data Result: %@",result.result);
    } else {
        qlerror(@"Data post to web service (%@), returned false.", urlPath);
        qldebug(@"%@",result.toDictionary);
        return NO;
    }
    
    return YES;
}

- (NSDictionary *)getDataFromWS:(NSString *)urlPath
{
    NSDictionary *result = nil;
    MPHTTPRequest *req;
    MPWSResult *wsresult;
    
    req = [[MPHTTPRequest alloc] init];
    wsresult = [req runSyncGET:urlPath];
    
    if (wsresult.statusCode >= 200 && wsresult.statusCode <= 299) {
        qldebug(@"Get Data from web service (%@) returned true.",urlPath);
        qldebug(@"Data Result: %@",wsresult.result);
        result = wsresult.result;
    } else {
        qlerror(@"Get Data from web service (%@), returned false.", urlPath);
        qldebug(@"%@",wsresult.toDictionary);
    }
    
    return result;
}

#pragma mark - Misc

- (void)cleanupPreStagePatches:(NSArray *)aApprovedPatches
{
    qlinfo(@"Cleaning up older pre-staged patches.");
    NSString *stagePatchDir;
    
    NSString *stageDir = [NSString stringWithFormat:@"%@/Data/.stage",MP_ROOT_CLIENT];
    NSArray *dirEnum = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:stageDir error:NULL];
    
    for (NSString *filename in dirEnum)
    {
        qldebug(@"Validating patch %@",filename);
        BOOL found = NO;
        stagePatchDir = [stageDir stringByAppendingPathComponent:filename];
        for (NSString *patchid in aApprovedPatches) {
            if ([[filename lowercaseString] isEqualToString:[patchid lowercaseString]]) {
                found = YES;
                break;
            }
        }
        // filename (patch_id) not found in approved patch IDs
        if (found == NO) {
            qlinfo(@"Delete obsolete patch %@",filename);
            [[NSFileManager defaultManager] removeItemAtPath:stagePatchDir error:NULL];
        }
    }
}


/**
 Echo status to stdout for iLoad. Will only echo if iLoadMode is true

 @param str Status string to echo
 */
- (void)iLoadStatus:(NSString *)str, ...
{
	va_list va;
	va_start(va, str);
	NSString *string = [[NSString alloc] initWithFormat:str arguments:va];
	va_end(va);
	if (iLoadMode == YES) {
		printf("%s\n", [string cStringUsingEncoding:NSUTF8StringEncoding]);
	}
}

- (NSString *)downloadUpdate:(NSString *)aURL error:(NSError **)err
{
	NSString *res = nil;
	NSError *error = nil;
	MPHTTPRequest *req = [[MPHTTPRequest alloc] init];
	NSString *uuid = [[NSUUID UUID] UUIDString];
	NSString *dlDir = [@"/private/tmp" stringByAppendingPathComponent:uuid];
	res = [req runSyncFileDownload:aURL downloadDirectory:dlDir error:&error];
	if (error) {
		if (err != NULL) {
			*err = error;
		}
	}
	
	return res;
}

- (void)postNotificationTo:(NSString *)aName info:(NSString *)info isGlobal:(BOOL)glb;
{
	NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:info, @"status", nil];
	if (glb) {
		qldebug(@"sendNotificationTo(G): %@ with %@",aName,options);
		[[NSDistributedNotificationCenter defaultCenter] postNotificationName:aName object:nil userInfo:options options:NSNotificationPostToAllSessions];
	} else {
		qldebug(@"sendNotificationTo: %@ with %@",aName,options);
		[[NSNotificationCenter defaultCenter] postNotificationName:aName object:nil userInfo:options];
	}
}

#pragma mark MPNetRequestController Callbacks
- (void)appendDownloadProgress:(double)aNumber
{
    //[progressBar setDoubleValue:aNumber];
}

- (void)appendDownloadProgressPercent:(NSString *)aPercent
{
    qldebug(@"%d%%",[aPercent intValue]);
}

- (void)downloadStarted
{
    qlinfo(@"Download Started");
}

- (void)downloadFinished
{
    qlinfo(@"Download Finished");
}

- (void)downloadError
{
    qlerror(@"Download Had An Error");
}

@end
