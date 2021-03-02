//
//  PatchScanAndUpdateOperation.m
/*
 Copyright (c) 2021, Lawrence Livermore National Security, LLC.
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

#import "PatchScanAndUpdateOperation.h"
#import "MacPatch.h"
#import <SystemConfiguration/SystemConfiguration.h>

@interface PatchScanAndUpdateOperation ()
{
    MPCodeSign *cs;
	MPSettings *settings;
}

- (void)runCritialPatchScanAndUpdate;

@end

@implementation PatchScanAndUpdateOperation

@synthesize iLoadMode;
@synthesize scanType;
@synthesize taskPID;
@synthesize taskFile;
@synthesize bundleID;
@synthesize patchFilter;
@synthesize forceRun;

- (id)init
{
    self = [super init];
	if (self)
    {
		patchFilter			= kAllPatches;
		scanType	    	= 0;
		bundleID			= NULL;
		forceRun			= NO;
        taskPID     		= -99;
		self.isExecuting 	= NO;
        self.isFinished  	= NO;
		fm          = [NSFileManager defaultManager];
        cs          = [[MPCodeSign alloc] init];
		settings	= [MPSettings new];
		
		[self setILoadMode:NO];
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
    self.isExecuting = NO;
    self.isFinished = YES;
    [self didChangeValueForKey:@"isExecuting"];
    [self didChangeValueForKey:@"isFinished"];
    
    [self killTaskUsingPID];
}

- (void)start
{
    if ([self isCancelled]) {
        [self willChangeValueForKey:@"isFinished"];
        self.isFinished = YES;
        [self didChangeValueForKey:@"isFinished"];
    } else {
        [self willChangeValueForKey:@"isExecuting"];
		[self performSelectorInBackground:@selector(main) withObject:nil];
        self.isExecuting = YES;
        [self didChangeValueForKey:@"isExecuting"];
    }
}

- (void)main
{
	@try
	{
		switch (scanType)
		{
			case 0:
				[self scanForPatches:patchFilter forceRun:forceRun];
				break;
			case 1:
                NSAssert(patchFilter,@"patchFilter failed");
				[self patchScanAndUpdate:patchFilter bundleID:bundleID];
				break;
			case 2:
				// [self runCritialPatchScanAndUpdate];
				break;
			default:
				[self scanForPatches:kAllPatches forceRun:NO];
				break;
		}
	}
	@catch (NSException * e) {
		logit(lcl_vError,@"[NSException]: %@",e);
	}
	[self finish];
}

- (void)runCritialPatchScanAndUpdate
{
    logit(lcl_vInfo,@"Running Critial vulnerability scan and update.");
    @autoreleasepool
    {
        @try
        {
            [self setTaskFile:[@"/private/tmp" stringByAppendingPathComponent:kMPPatchUPDATE]];
        }
        @catch (NSException *exception) {
            [self setTaskFile:[@"/private/tmp" stringByAppendingPathComponent:@".mpUpdateRunning"]];
        }
        
        NSString *appPath = [MP_ROOT_CLIENT stringByAppendingPathComponent:@"MPAgentExec"];
        if (![fm fileExistsAtPath:appPath]) {
            logit(lcl_vError,@"Unable to find MPAgentExec app.");
        } else {
            NSError *err = nil;
            BOOL result = [cs verifyAppleDevBinary:appPath error:&err];
            if (err) {
                logit(lcl_vError,@"%ld: %@",err.code,err.localizedDescription);
            }
            cs = nil;
            if (result == YES)
            {
                NSError *error = nil;
                NSString *result;
                MPNSTask *mpr = [[MPNSTask alloc] init];
                result = [mpr runTask:appPath binArgs:[NSArray arrayWithObjects:@"-x", nil] error:&error];
                
                if (error) {
                    logit(lcl_vError,@"%@",[error description]);
                }
                
                logit(lcl_vDebug,@"%@",result);
                logit(lcl_vInfo,@"Critial Vulnerability scan & update has been completed.");
                logit(lcl_vInfo,@"See the MPAgentExec.log file for more information.");
            }
        }	
    }
}

- (void)killTaskUsingPID
{
    NSError *err = nil;
    // If File Does Not Exists, not PID to kill
    if (![fm fileExistsAtPath:self.taskFile]) {
        return;
    } else {
        NSString *strPID = [NSString stringWithContentsOfFile:self.taskFile encoding:NSUTF8StringEncoding error:&err];
        if (err) {
            logit(lcl_vError,@"%ld: %@",err.code,err.localizedDescription);
        }
        if ([strPID intValue] > 0) {
            [self setTaskPID:[strPID intValue]];
        }
    }
    
    if (self.taskPID == -99) {
        logit(lcl_vWarning,@"No task PID was defined");
        return;
    }
    
    // Make Sure it's running before we send a SIGKILL
    NSArray *procArr = [MPSystemInfo bsdProcessList];
    NSArray *filtered = [procArr filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"processID == %i", self.taskPID]];
    if ([filtered count] <= 0) {
        return;
    } else if ([filtered count] == 1 ) {
        kill( self.taskPID, SIGKILL );
    } else {
        logit(lcl_vError,@"Can not kill task using PID. Found to many using the predicate.");
        logit(lcl_vDebug,@"%@",filtered);
    }
}


#pragma mark - From MPAgentExec
// Scan Host for Patches based on BundleID
// Found patches are stored in self.appprovedPatches array
- (NSArray *)scanForPatchUsingBundleID:(NSString *)aBundleID
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
	
	qlinfo(@"Patch Scan Completed.");
	return [approvedUpdatesArray copy];
}

// Scan Host for Patches
// Found patches are stored in self.appprovedPatches array
- (NSArray *)scanForPatches:(MPPatchContentType)contentType forceRun:(BOOL)aForceRun
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
	}
	
	qlinfo(@"Patch Scan Completed.");
	return [approvedUpdatesArray copy];
}

// NEW
- (void)patchScanAndUpdate:(MPPatchContentType)contentType bundleID:(NSString *)bundleID
{
    [self iLoadStatus:@"Status: Scanning for patches."];
	NSArray *updatesArray = [NSArray array];
	if (bundleID != NULL) {
		updatesArray = [self scanForPatchUsingBundleID:bundleID];
	} else {
		updatesArray = [self scanForPatches:contentType forceRun:NO];
	}
	
	// -------------------------------------------
	// If no updates, exit
	if (updatesArray.count <= 0)
	{
		qlinfo( @"No approved patches to install.");
        [self iLoadStatus:@"Completed: No approved patches to install."];
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
	[self iLoadStatus:@"Status: %d updates to install.", (int)updatesArray.count];
	
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
    patching.delegate = self;
    if (iLoadMode) patching.iLoadMode = YES;
    
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
		qlinfo(@"Patches that require reboot need to be installed. Opening reboot dialog now.");
		[@"reboot" writeToFile:MP_PATCH_ON_LOGOUT_FILE atomically:YES encoding:NSUTF8StringEncoding error:NULL];
		[fm setAttributes:@{@"NSFilePosixPermissions":[NSNumber numberWithUnsignedLong:0777]} ofItemAtPath:MP_PATCH_ON_LOGOUT_FILE error:NULL];
	}
    [self iLoadStatus:@"Status: Scanning and Patching completed."];
}

#pragma mark - MPPatching Delegates

- (void)patchProgress:(NSString *)progressStr
{
    if (iLoadMode)
    {
        if([progressStr hasPrefix:@"Begin:"]) {
            [self iLoadStatus:@"%@",progressStr];
            
        } else if([progressStr hasPrefix:@"Install completed for "]) {
            [self iLoadStatus:@"Completed: %@",progressStr];
            
        } else if([progressStr hasPrefix:@"Completed:"]) {
            [self iLoadStatus:@"%@",progressStr];
            
        } else if([progressStr hasPrefix:@"Progress:"]) {
            [self iLoadStatus:@"%@",progressStr];
            
        } else {
            [self iLoadStatus:@"Status: %@",progressStr];
        }
    }
}

- (void)patchingProgress:(MPPatching *)mpPatching progress:(NSString *)progressStr
{
    //qlinfo(@"[patchingProgress]: %@",progressStr);
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
			qltrace(@"PATCH: %@",patch);
			@try
			{
				if ([patch[@"type"] isEqualToString:@"Apple"])
				{
					[mpa downloadAppleUpdate:patch[@"patch"]];
				}
				else
				{
					// This is to clean up non used patches
					[approvedUpdateIDsArray addObject:patch[@"patch_id"]];
					
					//NSArray *pkgsFromPatch = patch[@"patches"][@"patches"];
					NSArray *pkgsFromPatch = patch[@"patches"];
					for (NSDictionary *_p in pkgsFromPatch)
					{
						qltrace(@"PKGPATCH: %@",_p);
						if ([_p[@"pkg_size"] integerValue] == 0) {
							qlinfo(@"Skipping %@, due to zero size.",_p[@"patch_name"]);
							continue;
						}
						
						NSError *dlErr = nil;
						NSString *stageDir = [NSString stringWithFormat:@"%@/Data/.stage/%@",MP_ROOT_CLIENT,patch[@"patch_id"]];
						NSString *downloadURL = [NSString stringWithFormat:@"/mp-content%@",_p[@"pkg_url"]];
						NSString *fileName = [_p[@"pkg_url"] lastPathComponent];
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
									if ([[_p[@"pkg_hash"] uppercaseString] isEqualTo:[[crypto md5HashForFile:stagedFilePath] uppercaseString]])
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
						qlinfo(@"%@ has been staged.",patch[@"patch"]);
						qldebug(@"Moved patch to: %@",stagedFilePath);
					}
				}
			} @catch (NSException *exception) {
				qlerror(@"Pre staging update %@ failed.",patch[@"patch"]);
				qlerror(@"%@",exception);
			}
		}
		
		[self cleanupPreStagePatches:(NSArray *)approvedUpdateIDsArray];
	}
}

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
@end
