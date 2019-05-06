//
//  MPPatching.m
//  MPLibrary
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


#import "MPPatching.h"
#import "MPSettings.h"
#import "MPAsus.h"
#import "MPASUSCatalogs.h"
#import "MPPatchScan.h"

#undef  ql_component
#define ql_component lcl_cMPPatching

typedef enum {
	kScanRunning = 1,
	kPatchRunning,
	kInventoryRunning,
	kAVUpdateRunning
} MPTaskRunningType;

@interface MPPatching ()
{
	NSFileManager *fm;
}

@property (nonatomic, strong) NSArray *approvedPatches;
@property (nonatomic, strong) MPSettings *settings;

- (BOOL)isTaskRunning:(MPTaskRunningType)task;
- (void)writeTaskRunning:(MPTaskRunningType)task;
- (void)removeTaskRunning:(MPTaskRunningType)task;
// Networking
- (NSString *)downloadUpdate:(NSString *)url error:(NSError **)err;

@end

@implementation MPPatching

@synthesize forceTaskRun;
@synthesize iLoadMode;
@synthesize settings;
@synthesize installRebootPatchesWhileLoggedIn;

- (id)init
{
	self = [super init];
	if (self)
	{
		fm = [NSFileManager defaultManager];
		[self setForceTaskRun:NO];
		[self setInstallRebootPatchesWhileLoggedIn:NO];
		settings = [MPSettings sharedInstance];
	}
	return self;
}

/**
 Scan system for patches that match a bundleID

 @param aBundleID Custom patch BundleID
 @return NSArray
 */
- (NSArray *)scanForPatchUsingBundleID:(NSString *)aBundleID
{
	return [self scanForPatchesUsingTypeFilterOrBundleID:kCustomPatches bundleID:aBundleID forceRun:NO];
}

/**
 Scan system for needed patches

 @param contentType Filter in scan type Apple, Custom, All, Critical
 @param forceRun Force run even if there is another running
 @return NSArray
 */
- (NSArray *)scanForPatchesUsingTypeFilter:(MPPatchContentType)contentType forceRun:(BOOL)forceRun
{
	return [self scanForPatchesUsingTypeFilterOrBundleID:contentType bundleID:NULL forceRun:forceRun];
}

- (NSArray *)scanForPatchesUsingTypeFilterOrBundleID:(MPPatchContentType)contentType bundleID:(NSString *)bundleID forceRun:(BOOL)forceRun
{
	NSArray *result = [NSArray array];
	if (!forceTaskRun)
	{
		if (forceRun)
		{
			// Wait up to 60 seconds to see if current running task will complete
			int w = 0;
			while ([self isTaskRunning:kScanRunning])
			{
				w++;
				sleep(1);
			}
		}
		else
		{
			if ([self isTaskRunning:kScanRunning])
			{
				qlinfo(@"Patch scan is already running. Now exiting.");
				[self patchScanCompleted];
				return nil;
			} else {
				[self writeTaskRunning:kScanRunning];
			}
		}
	}
	
	NSMutableArray      *approvedUpdatesArray = [[NSMutableArray alloc] init];
	NSMutableArray      *userInstallApplePatches = [[NSMutableArray alloc] init];
	NSMutableDictionary *tmpDict;
	NSArray             *approvedApplePatches = nil;
	NSArray             *approvedCustomPatches = nil;
	NSArray             *applePatchesArray = nil;
	NSMutableArray      *customPatchesArray;
	NSDictionary        *patchGroupPatches;
	
	// Get Patch Group Patches
	NSError *wsErr = nil;
	MPRESTfull *mprest = [[MPRESTfull alloc] init];
	qlinfo(@"Get approved patches list.");
	if (bundleID != NULL)
	{
		// Filter on BundleID
		patchGroupPatches = [mprest getApprovedPatchesForClient:&wsErr];
	}
	else
	{
		patchGroupPatches = [mprest getApprovedPatchesForClient:&wsErr];
	}
	if (wsErr)
	{
		// Error getting approved patch group patches
		qlerror(@"%@",wsErr.localizedDescription);
		[self patchScanCompleted];
		return result;
	}
	
	if (!patchGroupPatches)
	{
		qlerror(@"There was a issue getting the approved patches, scan will exit.");
		[self patchScanCompleted];
		return result;
	}
	
	if ((contentType == kApplePatches) || (contentType == kAllPatches))
	{
		approvedApplePatches = patchGroupPatches[@"Apple"];
		if (approvedApplePatches.count <= 0)
		{
			qlinfo(@"Warning: no apple updates have been approved for install.");
		}
	}
	if ((contentType == kCustomPatches) || (contentType == kAllPatches))
	{
		approvedCustomPatches = patchGroupPatches[@"Custom"];
		if (approvedCustomPatches.count <= 0)
		{
			qlinfo(@"Warning: no custom updates have been approved for install.");
		}
	}
	
	// Scan for Apple Patches
	if ((contentType == kApplePatches) || (contentType == kAllPatches))
	{
		qlinfo(@"Scanning for Apple software updates.");
		
		// New way, using the helper daemon
		MPAsus *asus = [MPAsus new];
		asus.delegate = self;
		
		applePatchesArray = [asus scanForAppleUpdates];
		[self wsPostPatchScanResults:applePatchesArray type:kApplePatches];
		
		// Process patches
		// If no items in array, lets bail...
		if (applePatchesArray.count == 0)
		{
			qlinfo(@"No Apple updates found.");
		}
		else
		{
			qlinfo(@"%ld Apple updates found.",applePatchesArray.count);
			for (NSDictionary *d in applePatchesArray) {
				qlinfo(@"Apple Patch Needed: %@",d[@"patch"]);
			}
			
			// We have Apple patches, now add them to the array of approved patches
			// If no items in array, lets bail...
			if (approvedApplePatches.count == 0)
			{
				qlinfo(@"No apple updates found for \"%@\" patch group.",settings.agent.patchGroup);
			}
			else
			{
				// Build Approved Patches
				qlinfo(@"Building approved patch list...");
				
				for (int i=0; i<[applePatchesArray count]; i++)
				{
					NSDictionary *_applePatch = applePatchesArray[i];
					for (int x=0;x < [approvedApplePatches count]; x++)
					{
						NSDictionary *_approvedPatch = approvedApplePatches[x];
						if ([ _approvedPatch[@"supatchname"] isEqualTo:_applePatch[@"patch"]])
						{
							
							// Check to see if the approved apple patch requires a user
							// to install the patch, right now this is for 10.13 os updates
							if (_approvedPatch[@"user_install"])
							{
								if ([_approvedPatch[@"user_install"] intValue] == 1)
								{
									qlinfo(@"Approved (User Install) update %@",_applePatch[@"patch"]);
									qldebug(@"Approved: %@",_approvedPatch);
									[userInstallApplePatches addObject:@{@"type":@"Apple",@"patch":_applePatch[@"patch"]}];
									break;
								}
							}
							
							qlinfo(@"Approved update %@",_applePatch[@"patch"]);
							qldebug(@"Approved: %@",_approvedPatch);
							tmpDict = [[NSMutableDictionary alloc] init];
							[tmpDict setObject:@"Apple" forKey:@"type"];
							[tmpDict setObject:_applePatch[@"patch"] forKey:@"patch"];
							[tmpDict setObject:_applePatch[@"description"] forKey:@"description"];
							[tmpDict setObject:_applePatch[@"restart"] forKey:@"restart"];
							[tmpDict setObject:_applePatch[@"version"] forKey:@"version"];
							[tmpDict setObject:_approvedPatch[@"severity"] forKey:@"severity"];
							[tmpDict setObject:_approvedPatch[@"patch_install_weight"] forKey:@"patch_install_weight"];
							
							if (_approvedPatch[@"hasCriteria"])
							{
								[tmpDict setObject:_approvedPatch[@"hasCriteria"] forKey:@"hasCriteria"];
								if ([_approvedPatch[@"hasCriteria"] boolValue] == YES)
								{
									if ( _approvedPatch[@"criteria_pre"] && [_approvedPatch[@"criteria_pre"] count] > 0)
									{
										[tmpDict setObject:_approvedPatch[@"criteria_pre"] forKey:@"criteria_pre"];
									}
									if (_approvedPatch[@"criteria_post"] && [_approvedPatch[@"criteria_post"] count] > 0)
									{
										[tmpDict setObject:_approvedPatch[@"criteria_post"] forKey:@"criteria_post"];
									}
								}
							}
							
							qldebug(@"Apple Patch Dictionary Added: %@",tmpDict);
							[approvedUpdatesArray addObject:tmpDict];
							break;
						}
					}
				}
			}
		} // If has applePatchesArray
	} // Scan for Apple or All
	
	// Scan for Custom Patches to see what is relevant for the system
	if ((contentType == kCustomPatches) || (contentType == kAllPatches))
	{
		qlinfo(@"Scanning for custom patch vulnerabilities...");
		MPPatchScan *scanner = [MPPatchScan new];
		scanner.delegate = self;
		
		if (bundleID != NULL)
		{
			customPatchesArray = [NSMutableArray arrayWithArray:[scanner scanForPatchesWithbundleID:bundleID]];
		}
		else
		{
			qlinfo(@"Start custom patch scan.");
			customPatchesArray = [NSMutableArray arrayWithArray:[scanner scanForPatches]];
			qlinfo(@"Custom patch scan completed.");
			qlinfo(@"%ld custom patches needed.",customPatchesArray.count);
			// Only post found patches on full scan, bundle id is for targeting sw install
			// auto-updates
			[self wsPostPatchScanResults:customPatchesArray type:kCustomPatches];
		}
		
		qlinfo(@"Custom Patches Needed: %ld",customPatchesArray.count);
		qldebug(@"Custom Patches Needed: %@",customPatchesArray);
		qlinfo(@"Approved Custom Patches: %ld",approvedCustomPatches.count);
		qldebug(@"Approved Custom Patches: %@",approvedCustomPatches);
		
		// Filter List of Patches containing only the approved patches
		qlinfo(@"Building approved patch list...");
		for (int i=0; i < customPatchesArray.count; i++)
		{
			NSDictionary *_customPatch = customPatchesArray[i];
			for (int x=0;x < approvedCustomPatches.count; x++)
			{
				NSDictionary *_approvedPatch = approvedCustomPatches[x];
				if ( [ _customPatch[@"patch_id"] isEqualTo:_approvedPatch[@"puuid"] ] )
				{
					qlinfo(@"Patch %@ approved for update.",_customPatch[@"description"]);
					tmpDict = [[NSMutableDictionary alloc] init];
					[tmpDict setObject:@"Third" forKey:@"type"];
					[tmpDict setObject:_customPatch[@"patch"] forKey:@"patch"];
					[tmpDict setObject:_customPatch[@"description"] forKey:@"description"];
					[tmpDict setObject:_customPatch[@"restart"] forKey:@"restart"];
					[tmpDict setObject:_customPatch[@"version"] forKey:@"version"];
					[tmpDict setObject:_customPatch[@"patchData"] forKey:@"patchData"];
					// CEH - This needs to be fixed, but it will take a lot of refactoring
					[tmpDict setObject:@[_approvedPatch] forKey:@"patches"];
					[tmpDict setObject:_customPatch[@"patch_id"] forKey:@"patch_id"];
					[tmpDict setObject:_customPatch[@"bundleID"] forKey:@"bundleID"];
					[tmpDict setObject:_approvedPatch[@"patch_install_weight"] forKey:@"patch_install_weight"];

					qldebug(@"Custom Patch Dictionary Added: %@",tmpDict);
					[approvedUpdatesArray addObject:[tmpDict copy]];
					tmpDict = nil;
					break;
				}
			}
		}
	}

	[self addPatchesToClientDatabase:[approvedUpdatesArray copy]];
	qldebug(@"Approved patches to install: %@",approvedUpdatesArray);
	result = [NSArray arrayWithArray:approvedUpdatesArray];
	
	[self patchScanCompleted];
	return result;
}

- (void)patchScanCompleted
{
	if (!forceTaskRun) {
		[self removeTaskRunning:kScanRunning];
	}
	
	// Post notification on update UI
	[[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"kRequiredPatchesChangeNotification" object:nil userInfo:nil options:NSNotificationPostToAllSessions];
	qlinfo(@"Patch Scan Completed.");
}

- (NSDictionary *)installPatchUsingTypeFilter:(NSDictionary *)approvedPatch typeFilter:(MPPatchContentType)contentType
{
	return [self installPatchesUsingTypeFilter:@[approvedPatch] typeFilter:contentType];
}

- (NSDictionary *)installPatchesUsingTypeFilter:(NSArray *)approvedPatches typeFilter:(MPPatchContentType)contentType
{
	qlinfo(@"installPatchesUsingTypeFilter[approvedPatches]: %@",approvedPatches);
	qlinfo(@"installPatchesUsingTypeFilter[typeFilter]: %d",contentType);
	
	BOOL hasUserLoggedIn = [MPSystemInfo isUserLoggedIn];
	BOOL canInstallRebootPatches = NO;
	
	MPAsus				*mpAsus = nil;
	MPInstaller         *mpInstaller = nil;
	MPScript            *mpScript = nil;
	NSError				*err;
	
	// Staging
	NSString *stageDir;
	
	int i;
	BOOL installResult = NO;
	
	int patchesToInstall = (int)approvedPatches.count;
	int patchesInstalled = 0;
	int patchInstallErrors = 0;
	NSMutableArray *failedPatches = [NSMutableArray new];
	
	int	patchesNeedingReboot = 0; // # of patches that need to be installed
	int patchesRequireReboot = 0; // # of patches that have been installed
	
	// Reboot Patch Install Vars
	if (!hasUserLoggedIn) canInstallRebootPatches = YES; //If no user logged in
	if (self.installRebootPatchesWhileLoggedIn) canInstallRebootPatches = YES; // Class override to allow reboot patches
	
	MPClientDatabase *cdb;
	qlinfo( @"Begin installing patches.");
	for (i = 0; i < approvedPatches.count; i++)
	{
		// Create/Get Dictionary of Patch to install
		NSDictionary *_patch = approvedPatches[i];
		qlinfo(@"Patching: %@",_patch[@"patch"]);
		qldebug(@"Patch Data: %@",_patch);
		
		BOOL _patchNeedsReboot = [_patch[@"restart"] stringToBoolValue];
		if (_patchNeedsReboot)
		{
			if (!canInstallRebootPatches)
			{
				qlinfo(@"%@(%@) requires a reboot, this patch will be installed on logout.",_patch[@"patch"],_patch[@"version"]);
				patchesNeedingReboot++;
				continue;
			}
		}
		
		// -------------------------------------------
		// Now proceed to the download and install
		// -------------------------------------------
		installResult = NO;
		
		if ([[_patch[@"type"] lowercaseString] isEqualTo:@"third"] && (contentType == kAllPatches || contentType == kCustomPatches))
		{
			
			qlinfo(@"Starting install for %@",_patch[@"patch"]);
			[self iLoadStatus:@"Begin: %@\n", _patch[@"patch"]];
			
			qlinfo(@"_patch: %@",_patch);
			
			// Get all of the patches, main and subs
			// This is messed up, not sure why I have an array right within an array, needs to be fixed ...later :-)
			NSArray *patchPatchesArray = [NSArray arrayWithArray:_patch[@"patches"]];
			qlinfo(@"Current patch has total patches associated with it %ld", patchPatchesArray.count);
			qlinfo(@"patchPatchesArray: %@", patchPatchesArray);
			
			MPFileUtils *fu;
			NSString *dlPatchLoc; //Download location Path
			int patchIndex = 0;
			for (patchIndex=0; patchIndex < patchPatchesArray.count; patchIndex++)
			{
				// Make sure we only process the dictionaries in the NSArray
				NSDictionary *currPatchToInstallDict;
				if ([patchPatchesArray[patchIndex] isKindOfClass:[NSDictionary class]])
				{
					currPatchToInstallDict = [NSDictionary dictionaryWithDictionary:patchPatchesArray[patchIndex]];
				}
				else
				{
					qlinfo(@"Object found was not of dictionary type; could be a problem. %@",patchPatchesArray[patchIndex]);
					continue;
				}
				
				BOOL usingStagedPatch = NO;
				BOOL downloadPatch = YES;
				BOOL validHash = NO;
				
				// We have a currPatchToInstallDict to work with
				qlinfo(@"Start install for patch %@ from %@",currPatchToInstallDict[@"pkg_url"],_patch[@"patch"]);
				
				// *****************************
				// Download the update
				@try
				{
					// -------------------------------------------
					// Check to see if the patch has been staged
					// -------------------------------------------
					NSString *stageDir = [NSString stringWithFormat:@"%@/Data/.stage/%@",MP_ROOT_CLIENT,_patch[@"patch_id"]];
					dlPatchLoc = [stageDir stringByAppendingPathComponent:[currPatchToInstallDict[@"pkg_url"] lastPathComponent]];
					if ([fm fileExistsAtPath:dlPatchLoc])
					{
						qlinfo(@"File has been staged to %@",dlPatchLoc);
						usingStagedPatch = YES;
					}
					
					// Validate hash, of staged patch
					if (usingStagedPatch)
					{
						downloadPatch = NO;
						validHash = [self doesHashMatch:dlPatchLoc knownHash:currPatchToInstallDict[@"hash"]];
						if (!validHash)
						{
							// Invalid hash, remove staged files
							fu = [MPFileUtils new];
							[fu removeContentsOfDirectory:stageDir];
							downloadPatch = YES;
						}
					}
					
					// -------------------------------------------
					// if, download the patch
					// -------------------------------------------
					if (downloadPatch)
					{
						qlinfo(@"Start download for patch from %@",currPatchToInstallDict[@"pkg_url"]);
						NSString *patchURL = [NSString stringWithFormat:@"/mp-content%@",currPatchToInstallDict[@"pkg_url"]];
						
						qlinfo(@"Download patch from: %@",patchURL);
						err = nil;
						dlPatchLoc = [self downloadUpdate:patchURL error:&err];
						if (err) {
							qlerror(@"Error downloading a patch, skipping %@. Err Message: %@",_patch[@"patch"],err.localizedDescription);
							break;
						}
						qlinfo(@"File downloaded to %@",dlPatchLoc);
						
						// -------------------------------------------
						// Validate hash, before install
						// -------------------------------------------
						if (![self doesHashMatch:dlPatchLoc knownHash:currPatchToInstallDict[@"pkg_hash"]])
						{
							qlerror(@"The downloaded file did not pass the file hash validation. No install will occur.");
							
							fu = [MPFileUtils new];
							[fu removeContentsOfDirectory:dlPatchLoc.stringByDeletingLastPathComponent];
							
							continue;
						}
					}
				}
				@catch (NSException *e)
				{
					qlerror(@"%@", e);
					break;
				}
				
				// *****************************
				// Now we need to unzip
				qlinfo(@"Uncompressing patch, to begin install.");
				qlinfo(@"Begin decompression of file, %@",dlPatchLoc);
				err = nil;
				fu = [MPFileUtils new];
				[fu unzip:dlPatchLoc error:&err];
				if (err)
				{
					qlerror(@"Error decompressing a patch, skipping %@. Err Message:%@",_patch[@"patch"],err.localizedDescription);
					break;
				}
				qlinfo(@"Patch has been decompressed.");
				
				// *****************************
				// Run PreInstall Script
				if(![currPatchToInstallDict[@"pkg_preinstall"] isKindOfClass:[NSNull class]])
				{
					if ([currPatchToInstallDict[@"pkg_preinstall"] length] > 0 && ([currPatchToInstallDict[@"pkg_preinstall"] isEqualTo:@"NA"] == NO))
					{
						qlinfo(@"Begin pre install script.");
						NSString *preInstScript = @"";
						if ([currPatchToInstallDict[@"pkg_preinstall"] isBase64String])
						{
							preInstScript = [currPatchToInstallDict[@"pkg_preinstall"] decodeBase64AsString];
						}
						else
						{
							preInstScript = currPatchToInstallDict[@"pkg_preinstall"];
						}
						
						mpScript = [[MPScript alloc] init];
						if ([mpScript runScript:preInstScript] == NO)
						{
							qlerror(@"Error running pre-install script.");
							qlerror(@"Pre Install Script: %@",preInstScript);
							mpScript = nil;
							break;
						}
						mpScript = nil;
					}
				}
				
				// *****************************
				// Install the update
				BOOL hadErr = NO;
				@try
				{
					// Look at directory of the uncompressed downloaded file. Install all PKGS
					NSString *pkgPath;
					NSString *pkgBaseDir = [dlPatchLoc stringByDeletingLastPathComponent];
					NSPredicate *pkgPredicate = [NSPredicate predicateWithFormat:@"(SELF like [cd] '*.pkg') OR (SELF like [cd] '*.mpkg')"];
					NSArray *pkgList = [[fm contentsOfDirectoryAtPath:[dlPatchLoc stringByDeletingLastPathComponent] error:NULL] filteredArrayUsingPredicate:pkgPredicate];
					installResult = NO;
					
					// Install pkg(s)
					cdb = [MPClientDatabase new];
					for (int ii = 0; ii < pkgList.count; ii++)
					{
						pkgPath = [NSString stringWithFormat:@"%@/%@",pkgBaseDir,pkgList[ii]];
						qlinfo(@"Installing %@",pkgPath.lastPathComponent);
						qlinfo(@"Start install of %@",pkgPath);
						mpInstaller = [[MPInstaller alloc] init];
						int instalRes = -1;
						instalRes = [mpInstaller installPkgToRoot:pkgPath env:currPatchToInstallDict[@"pkg_env_var"]];
						if (instalRes != 0)
						{
							qlerror(@"Error installing package, error code %d.",instalRes);
							[cdb recordHistory:kMPPatchType name:_patch[@"patch"] uuid:_patch[@"patch_id"] action:kMPInstallAction result:1 errorMsg:@"Failed to install patch"];
							hadErr = YES;
							break;
						} else {
							[cdb recordPatchInstall:_patch];
							qlinfo(@"%@ was installed successfully.",pkgPath);
						}
					} // End Loop
					
					if (!hadErr)
					{
						patchesInstalled++;
						// If the Patch we just installed needed a reboot ...
						if (_patchNeedsReboot) patchesRequireReboot++;
					}
					else
					{
						patchInstallErrors++;
						[failedPatches addObject:_patch];
					}
					
					// Install Complteded Remove downloaded and uncompressed files
					fu = [MPFileUtils new];
					[fu removeContentsOfDirectory:pkgBaseDir];
					
				}
				@catch (NSException *e)
				{
					qlerror(@"%@", e);
					qlerror(@"Error attempting to install patch, skipping %@.",_patch[@"patch"]);
					break;
				}
				
				if (hadErr) continue; // We had an error, try the next one.
				
				// **********************************************************
				// Run PostInstall Script
				if(![currPatchToInstallDict[@"pkg_postinstall"] isKindOfClass:[NSNull class]])
				{
					if ([currPatchToInstallDict[@"pkg_postinstall"] length] > 0 && [currPatchToInstallDict[@"pkg_postinstall"] isEqualTo:@"NA"] == NO)
					{
						qlinfo(@"Begin post install script.");
						NSString *postInstScript = @"";
						if ([currPatchToInstallDict[@"pkg_postinstall"] isBase64String])
						{
							postInstScript = [currPatchToInstallDict[@"pkg_postinstall"] decodeBase64AsString];
						}
						else
						{
							postInstScript = currPatchToInstallDict[@"pkg_postinstall"];
						}
						
						mpScript = [[MPScript alloc] init];
						if ([mpScript runScript:postInstScript] == NO)
						{
							qlerror(@"Error running post-install script.");
							qlerror(@"Post Install Script: %@",postInstScript);
							mpScript = nil;
							break;
						}
						mpScript = nil;
					}
				}
				// **********************************************************
				// Install is complete, post result to web service
				@try
				{
					qlinfo(@"Posting patch (%@) install to web service.",_patch[@"patch_id"]);
					[self postPatchInstallData:_patch patchType:kCustomPatches];
				}
				@catch (NSException *e)
				{
					qlerror(@"%@", e);
				}
				
				if (iLoadMode == YES) fprintf(stdout, "Completed: %s\n", [_patch[@"patch"] cString]);
				
				// **********************************************************
				// If staged, remove staged patch dir
				if (usingStagedPatch)
				{
					if ([fm fileExistsAtPath:stageDir])
					{
						qlinfo(@"Removing staged patch dir %@",stageDir);
						err = nil;
						[fm removeItemAtPath:stageDir error:&err];
						if (err) {
							qlerror(@"Removing staged patch dir %@ failed.",stageDir);
							qlerror(@"%@",err.localizedDescription);
						}
					}
				}
				
				qlinfo(@"Patch install completed.");
			}
			// End patchArray To install
			// ***************************************************************************************
		}
		// ***************************************************************************************
		// Process Apple Type Patches
		// ***************************************************************************************
		else if ([[_patch[@"type"] lowercaseString] isEqualTo:@"apple"] && (contentType == kAllPatches || contentType == kApplePatches))
		{
			qlinfo(@"Starting install for %@",_patch[@"patch"]);
			qldebug(@"Apple Dict:%@",_patch);
			[self iLoadStatus:@"Begin: %s",_patch[@"patch"]];
			
			mpAsus = [MPAsus new];
			if ([_patch[@"hasCriteria"] boolValue] == NO || !_patch[@"hasCriteria"])
			{
				qlinfo(@"hasCriteria=No");
				installResult = [mpAsus installAppleSoftwareUpdate:_patch[@"patch"]];
				qlinfo(@"installResult(1): %@",installResult ? @"Yes":@"No");
			}
			else
			{
				qlinfo(@"%@ has install criteria assigned to it.",_patch[@"patch"]);
				NSDictionary *criteriaDictPre, *criteriaDictPost;
				NSString *scriptText;
				
				int i = 0;
				// PreInstall First
				if (_patch[@"criteria_pre"])
				{
					qlinfo(@"Processing pre-install criteria.");
					for (i=0; i < [_patch[@"criteria_pre"] count]; i++)
					{
						criteriaDictPre = _patch[@"criteria_pre"][i];
						if ([criteriaDictPre[@"data"] isBase64String])
						{
							scriptText = [criteriaDictPre[@"data"] decodeBase64AsString];
						}
						else
						{
							scriptText = criteriaDictPre[@"data"];
						}
						
						mpScript = [MPScript new];
						if (![mpScript runScript:scriptText])
						{
							installResult = NO;
							qlerror(@"Pre-install script returned false for %@. No install will occur.",_patch[@"patch"]);
							goto instResult;
						}
						else
						{
							qlinfo(@"Pre-install script returned true.");
						}
					}
				}
				// Run the patch install, now that the install has occured.
				installResult = [mpAsus installAppleSoftwareUpdate:_patch[@"patch"]];
				
				// If Install retuened anything but 0, the dont run post criteria
				if (!installResult)
				{
					qlerror(@"The install for %@ returned an error.",_patch[@"patch"]);
					goto instResult;
				}
				
				if (_patch[@"criteria_post"])
				{
					qlinfo(@"Processing post-install criteria.");
					for (i=0; i < [_patch[@"criteria_post"] count]; i++)
					{
						criteriaDictPost = _patch[@"criteria_post"][i];
						if ([criteriaDictPost[@"data"] isBase64String])
						{
							scriptText = [criteriaDictPost[@"data"] decodeBase64AsString];
						}
						else
						{
							scriptText = criteriaDictPost[@"data"];
						}

						mpScript = [MPScript new];
						if (![mpScript runScript:scriptText])
						{
							installResult = NO;
							qlerror(@"Post-install script returned false for %@. No install will occur.",_patch[@"patch"]);
							goto instResult;
						} else {
							qlinfo(@"Post-install script returned true.");
						}
					}
				}
			}
			
		instResult:
			//cdb = [MPClientDatabase new];
			if (!installResult)
			{
				qlerror(@"Error installing update, error code %@.",installResult ? @"Yes":@"No");
				[cdb recordHistory:kMPPatchType name:_patch[@"patch"] uuid:_patch[@"patch"] action:kMPInstallAction result:1 errorMsg:@"Failed to install patch"];
				continue;
			}
			else
			{
				qlinfo(@"%@ was installed successfully.",_patch[@"patch"]);
				[cdb recordPatchInstall:_patch];
				patchesInstalled++;
				if (_patchNeedsReboot) patchesRequireReboot++;
			}
			
			// Post the results to web service
			@try
			{
				qlinfo(@"Posting patch (%@) install to web service.",_patch[@"patch"]);
				[self postPatchInstallData:_patch patchType:kApplePatches];
			}
			@catch (NSException *e)
			{
				qlerror(@"%@", e);
			}
			
			if (iLoadMode == YES) fprintf(stdout, "Completed: %s\n", [_patch[@"patch"] cString]);
			qlinfo(@"Patch install completed.");
		}
		else
		{
			continue;
		}
	} //End patchesToInstallArray For Loop
	
	// Update MP Client Status to reflect patch install
	[[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"kRequiredPatchesChangeNotification" object:nil userInfo:nil options:NSNotificationPostToAllSessions];
	
	if (patchesNeedingReboot >= 1 || patchesRequireReboot >= 1)
	{
		if (![[NSFileManager defaultManager] fileExistsAtPath:MP_AUTHRUN_FILE])
		{
			[@"reboot" writeToFile:MP_AUTHRUN_FILE atomically:YES encoding:NSUTF8StringEncoding error:NULL];
			[[NSFileManager defaultManager] setAttributes:@{@"NSFilePosixPermissions":[NSNumber numberWithUnsignedLong:0777]} ofItemAtPath:MP_AUTHRUN_FILE error:NULL];
		}
	}
	
	// If any patches that were installed needed a reboot
	qldebug(@"Number of installed patches needing a reboot, %d.", patchesRequireReboot);
	qldebug(@"Number of reboot patches needing to be installed, %d.", patchesNeedingReboot);
	NSDictionary *result = @{@"patchesNeedingReboot": [NSNumber numberWithInt:patchesRequireReboot],
							 @"rebootPatchesNeeded": [NSNumber numberWithInt:patchesNeedingReboot],
							 @"totalPatchesToInstall": [NSNumber numberWithInt:patchesToInstall],
							 @"totalPatchesInstalled": [NSNumber numberWithInt:patchesInstalled],
							 @"patchInstallErrors": [NSNumber numberWithInt:patchInstallErrors],
							 @"failedPatches": [failedPatches copy],
							 };

	qlinfo(@"CEH Result: %@",result);
	return result;
}

#pragma mark - Delegate Methods
// Take the MPPatchScan delegate data and post to MPPatching status delegate
- (void)scanProgress:(NSString *)scanStr
{
	[self.delegate patchingProgress:self progress:scanStr];
}

- (void)asusProgress:(NSString *)data
{
	[self.delegate patchingProgress:self progress:data];
}

#pragma mark - Private

- (BOOL)isTaskRunning:(MPTaskRunningType)task
{
	BOOL result = NO;
	if (forceTaskRun == YES) return result;
	
	switch (task)
	{
		case kScanRunning:
			if ([fm fileExistsAtPath:[@"/tmp" stringByAppendingPathComponent:kScanRunningFile]]) result = YES;
			break;
		case kPatchRunning:
			if ([fm fileExistsAtPath:[@"/tmp" stringByAppendingPathComponent:kPatchRunningFile]]) result = YES;
			break;
		case kInventoryRunning:
			if ([fm fileExistsAtPath:[@"/tmp" stringByAppendingPathComponent:kInventoryRunningFile]]) result = YES;
			break;
		case kAVUpdateRunning:
			if ([fm fileExistsAtPath:[@"/tmp" stringByAppendingPathComponent:kAVUpdateRunningFile]]) result = YES;
			break;
		default:
			break;
	}
	
	return result;
}

-(void)writeTaskRunning:(MPTaskRunningType)task
{
	if (forceTaskRun == NO)
	{
		NSString *taskFile;
		switch (task)
		{
			case kScanRunning:
				taskFile = [@"/tmp" stringByAppendingPathComponent:kScanRunningFile];
				break;
			case kPatchRunning:
				taskFile = [@"/tmp" stringByAppendingPathComponent:kPatchRunningFile];
				break;
			case kInventoryRunning:
				taskFile = [@"/tmp" stringByAppendingPathComponent:kInventoryRunningFile];
				break;
			case kAVUpdateRunning:
				taskFile = [@"/tmp" stringByAppendingPathComponent:kAVUpdateRunningFile];
				break;
			default:
				taskFile = nil;
				break;
		}
		if (taskFile)
		{
			[[[NSProcessInfo processInfo] globallyUniqueString] writeToFile:taskFile atomically:YES encoding:NSUTF8StringEncoding error:NULL];
		}
	}
}

-(void)removeTaskRunning:(MPTaskRunningType)task
{
	if (forceTaskRun) return;
	
	NSString *taskFile;
	switch (task)
	{
		case kScanRunning:
			taskFile = [@"/tmp" stringByAppendingPathComponent:kScanRunningFile];
			break;
		case kPatchRunning:
			taskFile = [@"/tmp" stringByAppendingPathComponent:kPatchRunningFile];
			break;
		case kInventoryRunning:
			taskFile = [@"/tmp" stringByAppendingPathComponent:kInventoryRunningFile];
			break;
		case kAVUpdateRunning:
			taskFile = [@"/tmp" stringByAppendingPathComponent:kAVUpdateRunningFile];
			break;
		default:
			taskFile = nil;
			break;
	}
	if (taskFile)
	{
		if ([fm fileExistsAtPath:taskFile])
		{
			NSError *err = nil;
			[fm removeItemAtPath:taskFile error:&err];
			if (err) {
				qlerror(@"File remove %@\nError=%@",taskFile,err.localizedDescription);
			}
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

- (BOOL)doesHashMatch:(NSString *)filePath knownHash:(NSString *)knownHash
{
	MPCrypto *crypto = [MPCrypto new];
	NSString *fileHash = [crypto md5HashForFile:filePath];
	
	if ([[knownHash uppercaseString] isEqualToString:[fileHash uppercaseString]])
	{
		qlinfo(@"%@ passed file hash check.",filePath.lastPathComponent);
		return YES;
	}
	else
	{
		qlerror(@"Error, %@ failed file hash check.",filePath.lastPathComponent);
		qldebug(@"Known: %@ Found: %@",knownHash,fileHash);
		return NO;
	}
}

- (BOOL)checkPatchPreAndPostForRebootRequired:(NSArray *)aDictArray
{
	BOOL result = NO;
	int x = 0;
	// Look for reboots in other patches attached
	for (x = 0; x < [aDictArray count];x++) {
		if ([[[aDictArray objectAtIndex:x] objectForKey:@"reboot"] isEqualTo:@"Yes"]) {
			result = YES;
			break;
		}
	}
	
	return result;
}

- (void)addPatchesToClientDatabase:(NSArray *)patches
{
	qlinfo(@"Adding required patches to client database.");
	MPClientDatabase *cdb = [MPClientDatabase new];
	[cdb clearRequiredPatches];
	for (NSDictionary *p in patches)
	{
		[cdb addRequiredPatch:p];
		qldebug(@"Added %@",p[@"patch"]);
	}
	return;
}

#pragma mark Networking
- (NSString *)downloadUpdate:(NSString *)url error:(NSError **)err
{
	NSString *res = nil;
	NSError *error = nil;
	MPHTTPRequest *req = [[MPHTTPRequest alloc] init];
	NSString *uuid = [[NSUUID UUID] UUIDString];
	NSString *dlDir = [@"/private/tmp" stringByAppendingPathComponent:uuid];
	res = [req runSyncFileDownload:url downloadDirectory:dlDir error:&error];
	if (error) {
		if (err != NULL) {
			*err = error;
		}
	}
	
	return res;
}

- (BOOL)postPatchInstallData:(NSDictionary *)patch patchType:(MPPatchContentType)type
{
	NSString *pType;
	NSString *patchID;
	switch (type) {
		case kApplePatches:
			pType = @"apple";
			patchID = patch[@"patch"];
			break;
		case kCustomPatches:
			pType = @"third";
			patchID = patch[@"patch_id"];
			break;
		default:
			pType = nil;
			break;
	}
	
	if (!pType) {
		qlerror(@"Error, invalid patch type. Can not post patch install." );
	}
	
	NSString *urlPath = [NSString stringWithFormat:@"/api/v1/client/patch/install/%@/%@/%@",patchID,pType,settings.ccuid];
	return [self postDataToWebService:urlPath data:nil];
}

- (BOOL)postDataToWebService:(NSString *)urlPath data:(NSDictionary *)data
{
	MPHTTPRequest *req;
	MPWSResult *result;
	
	req = [[MPHTTPRequest alloc] init];
	result = [req runSyncPOST:urlPath body:data];
	
	if (result.statusCode >= 200 && result.statusCode <= 299)
	{
		qlinfo(@"Results posted to web service.");
		qldebug(@"[MPMpatching][postDataToWebService]: Data post to web service (%@), returned true.", urlPath);
		qldebug(@"Data Result: %@",result.result);
	} else {
		qlerror(@"Data post to web service (%@), returned false.", urlPath);
		qldebug(@"%@",result.toDictionary);
		return NO;
	}
	
	return YES;
}

- (BOOL)wsPostPatchScanResults:(NSArray *)data type:(MPPatchContentType)type
{
	NSString *urlPath;
	switch (type)
	{
		case kApplePatches:
			urlPath = [NSString stringWithFormat:@"/api/v1/client/patch/scan/1/%@",settings.ccuid];
			break;
		case kCustomPatches:
			urlPath = [NSString stringWithFormat:@"/api/v1/client/patch/scan/2/%@",settings.ccuid];
			break;
		default:
			urlPath = [NSString stringWithFormat:@"/api/v1/client/patch/scan/3/%@",settings.ccuid];
			break;
	}
	
	NSDictionary *_data = @{@"rows": [NSArray array]};
	if (data)
	{
		_data = @{@"rows": data};
	}
	
	return [self postDataToWebService:urlPath data:_data];
}

#pragma mark Local Database
@end
