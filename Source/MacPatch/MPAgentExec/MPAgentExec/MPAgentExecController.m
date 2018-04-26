//
//  MPAgentExecController.m
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

#import "MPAgentExecController.h"
#import "MacPatch.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import "MPAntiVirus.h"
#include <sys/reboot.h>

@interface MPAgentExecController (Private)

@property (nonatomic, readwrite, assign) int errorCode;
@property (nonatomic, readwrite, retain) NSString *errorMsg;
@property (nonatomic, readwrite, assign) int needsReboot;

// Web Services
- (void)postInstallResults:(int)resultNo resultText:(NSString *)resultString task:(NSDictionary *)taskDict;

// Misc
- (void)updateNeededPatchesFile:(NSDictionary *)aPatch;

// Helper
- (void)connect;
- (void)cleanup;
- (void)connectionDown:(NSNotification *)notification;

- (int)installSoftwareViaProxy:(NSDictionary *)aInstallDict;
- (int)patchSoftwareViaProxy:(NSDictionary *)aInstallDict;
- (int)writeToFileViaProxy:(NSString *)aFile data:(id)data;
- (int)writeArrayFileViaProxy:(NSString *)aFile data:(NSArray *)data;

- (void)killTaskUsing:(NSString *)aTaskName;

@end

@implementation MPAgentExecController

@synthesize errorCode;
@synthesize errorMsg;
@synthesize needsReboot;
@synthesize overrideRebootPatchInstalls;

@synthesize _defaults;
@synthesize _cuuid;
@synthesize _appPid;
@synthesize iLoadMode;
@synthesize forceRun;
@synthesize approvedPatches;
@synthesize mp_SOFTWARE_DATA_DIR;

- (id)init
{
    self = [super init];
    if (self) {
        fm = [NSFileManager defaultManager];
        MPDefaults *mpDefaults = [[MPDefaults alloc] init];
        [self set_defaults:[mpDefaults defaults]];
		[self set_cuuid:[MPSystemInfo clientUUID]];
        mpAsus = [[MPAsus alloc] init];
        mpDataMgr = [[MPDataMgr alloc] init];
		[self setILoadMode:NO];
		[self setForceRun:NO];
		[self setOverrideRebootPatchInstalls:NO];

		// Add Debug Output
		if ([_defaults hasKey:@"MPAgentExecDebug"]) {
			if ([[_defaults objectForKey:@"MPAgentExecDebug"] isEqualTo:@"1"]) {
				lcl_configure_by_name("*", lcl_vDebug);
			}
		}
    }
    return self;
}

- (id)initForBundleUpdate
{
    self = [super init];
    if (self) {
        fm = [NSFileManager defaultManager];
        MPDefaults *mpDefaults = [[MPDefaults alloc] init];
        [self set_defaults:[mpDefaults defaults]];
		[self set_cuuid:[MPSystemInfo clientUUID]];
        mpAsus = [[MPAsus alloc] init];
        mpDataMgr = [[MPDataMgr alloc] init];
		[self setILoadMode:NO];
		[self setForceRun:NO];
        [self setErrorCode:-1];
        [self setErrorMsg:@""];
		[self setOverrideRebootPatchInstalls:NO];
    }
    return self;
}

-(void)overRideDefaults:(NSDictionary *)aDict
{
	NSMutableDictionary *_d = [NSMutableDictionary dictionaryWithDictionary:_defaults];
	for (id key in [aDict allKeys]) {
		[_d setObject:[aDict objectForKey:key] forKey:key];
	}
	[self set_defaults:(NSDictionary *)_d];
}

// Calls: scanForPatchesWithFilter:(int)aFilter
- (void)scanForPatches
{
	[self scanForPatchesWithFilter:0 byPassRunning:NO];
}

// Calls: scanForPatchesWithFilter:(int)aFilter byPassRunning:BOOL
- (void)scanForPatchesWithFilter:(int)aFilter
{
    [self scanForPatchesWithFilter:aFilter byPassRunning:NO];
}

// Calls: canForPatchesWithFilterWaitAndForce:aFilter byPassRunning:BOOL
- (void)scanForPatchesWithFilter:(int)aFilter byPassRunning:(BOOL)aByPass
{
    [self scanForPatchesWithFilterWaitAndForce:aFilter byPassRunning:aByPass];
}

// Calls: scanForPatchesWithFilterWaitAndForceWithCritical:aFilter byPassRunning:BOOL critical:BOOL
- (void)scanForPatchesWithFilterWaitAndForce:(int)aFilter byPassRunning:(BOOL)aByPass
{
    [self scanForPatchesWithFilterWaitAndForceWithCritical:aFilter byPassRunning:aByPass critical:NO];
}

- (void)scanForPatchesWithFilterWaitAndForceWithCritical:(int)aFilter byPassRunning:(BOOL)aByPass critical:(BOOL)aCritical
{
    // Filter - 0 = All,  1 = Apple, 2 = Third
    if (forceRun == NO) {
        if (aByPass == YES) {
            int w = 0;
            while ([self isTaskRunning:kMPPatchSCAN] == YES) {
                if (w == 60) {
                    [self removeTaskRunning:kMPPatchSCAN];
                    break;
                }
                w++;
                sleep(1);
            }
        } else {
            if ([self isTaskRunning:kMPPatchSCAN]) {
                logit(lcl_vInfo,@"Scanning for patches is already running. Now exiting.");
                return;
            } else {
                [self writeTaskRunning:kMPPatchSCAN];
            }
        }
    }
    
    MPAsus              *mpa;
    MPASUSCatalogs      *mpCatalog;
    NSArray             *applePatchesArray;
    NSArray             *approvedApplePatches = nil;
	NSMutableArray      *userInstallApplePatches = [[NSMutableArray alloc] init];
    NSMutableArray      *customPatchesArray;
    NSArray             *approvedCustomPatches = nil;
    NSMutableArray      *approvedUpdatesArray = [[NSMutableArray alloc] init];
    NSMutableArray      *approvedUpdateIDsArray = [[NSMutableArray alloc] init];
    NSMutableDictionary *tmpDict;
    NSDictionary        *customPatch, *approvedPatch;
    
    // PreStage Patches
    MPCrypto *crypto = [[MPCrypto alloc] init];
    NSArray  *patchesFromPatch;
    NSString *downloadURL;
    NSString *dlPatchLoc; //Download location Path
    NSError  *dlErr = nil;
    NSString *stageDir;
    BOOL isDir = NO;
    BOOL exists = NO;
    
    // Get Patch Group Patches
    MPWebServices *mpws = [[MPWebServices alloc] init];
    NSError       *rmErr = nil;
    NSError       *wsErr = nil;
    NSDictionary  *patchGroupPatches;
    
    if (aCritical == YES) {
        patchGroupPatches = [mpws getCriticalPatchGroupContent:&wsErr];
    }
	else
	{
        
        BOOL useLocalPatchesFile = NO;
        NSString *patchGroupRevLocal = [MPClientInfo patchGroupRev];
        if (![patchGroupRevLocal isEqualToString:@"-1"]) {
            NSString *patchGroupRevRemote = [mpws getPatchGroupContentRev:&wsErr];
            if (!wsErr) {
                if ([patchGroupRevLocal isEqualToString:patchGroupRevRemote]) {
                    useLocalPatchesFile = YES;
                    NSString *pGroup = [_defaults objectForKey:@"PatchGroup"];
                    patchGroupPatches = [[[NSDictionary dictionaryWithContentsOfFile:PATCH_GROUP_PATCHES_PLIST] objectForKey:pGroup] objectForKey:@"data"];
                    if (!patchGroupPatches) {
                        logit(lcl_vError,@"Unable to get data from cached patch group data file. Will download new one.");
                        useLocalPatchesFile = NO;
                    }
                }
            }
        }
        if (!useLocalPatchesFile) {
            wsErr = nil;
            patchGroupPatches = [mpws getPatchGroupContent:&wsErr];
            if (wsErr) {
                logit(lcl_vError,@"%@",wsErr.localizedDescription);
                goto done;
            }
        }
    }

    if (!patchGroupPatches) {
        logit(lcl_vError,@"There was a issue getting the approved patches for the patch group, scan will exit.");
        goto done;
    }
    
    if ((aFilter == 0) || (aFilter == 1)) {
        approvedApplePatches  = [patchGroupPatches objectForKey:@"AppleUpdates"];
    }
    if ((aFilter == 0) || (aFilter == 2)) {
        approvedCustomPatches = [patchGroupPatches objectForKey:@"CustomUpdates"];
    }
    
    // Scan for Apple Patches
    if ((aFilter == 0) || (aFilter == 1))
    {
        logit(lcl_vInfo,@"Setting Apple softwareupdate catalog.");
        mpCatalog = [[MPASUSCatalogs alloc] init];
        if (![mpCatalog checkAndSetCatalogURL]) {
            logit(lcl_vError,@"There was a issue setting the CatalogURL, Apple updates will not occur.");
        }
        
        logit(lcl_vInfo,@"Scanning for Apple software updates.");
        
        // New way, using the helper daemon
        applePatchesArray = nil;
        applePatchesArray = [mpAsus scanForAppleUpdates];
        
        // post patches to web service
        wsErr = nil;
        [mpws postClientScanDataWithType:applePatchesArray type:0 error:&wsErr];
        if (wsErr) {
            logit(lcl_vError,@"Scan results posted to webservice returned false.");
            logit(lcl_vError,@"%@",wsErr.localizedDescription);
        } else {
            logit(lcl_vInfo,@"Scan results posted to webservice.");
        }
        
        // Process patches
        if (!applePatchesArray)
		{
            logit(lcl_vInfo,@"The scan results for ASUS scan were nil.");
        }
		else
		{
            // If no items in array, lets bail...
            if ([applePatchesArray count] == 0 )
			{
                logit(lcl_vInfo,@"No Apple updates found.");
                sleep(1);
            }
			else
			{
                // We have Apple patches, now add them to the array of approved patches
                
                // If no items in array, lets bail...
                if ([approvedApplePatches count] == 0 )
				{
                    logit(lcl_vInfo,@"No apple updates found for \"%@\" patch group.",[_defaults objectForKey:@"PatchGroup"]);
                }
				else
				{
                    // Build Approved Patches
                    logit(lcl_vInfo,@"Building approved patch list...");
					NSDictionary *_applePatch;
					NSDictionary *_applePatchApproved;
                    for (int i=0; i<[applePatchesArray count]; i++)
					{
						_applePatch = [applePatchesArray objectAtIndex:i];
						
                        for (int x=0;x < [approvedApplePatches count]; x++)
						{
							_applePatchApproved = [approvedApplePatches objectAtIndex:x];
							
                            if ([_applePatchApproved[@"name"] isEqualTo:_applePatch[@"patch"]])
							{
								// Check to see if the approved apple patch requires a user
								// to install the patch, right now this is for 10.13 os updates
								if ([_applePatchApproved objectForKey:@"user_install"])
								{
									if ([[_applePatchApproved objectForKey:@"user_install"] intValue] == 1)
									{
										logit(lcl_vInfo,@"Approved (User Install) update %@",_applePatch[@"patch"]);
										logit(lcl_vDebug,@"Approved: %@",_applePatchApproved);
										[userInstallApplePatches addObject:@{@"type":@"Apple",@"patch":_applePatch[@"patch"]}];
										break;
									}
								}
								
                                logit(lcl_vInfo,@"Approved update %@",[_applePatch objectForKey:@"patch"]);
                                logit(lcl_vDebug,@"Approved: %@",_applePatchApproved);
								
                                tmpDict = [[NSMutableDictionary alloc] init];
                                [tmpDict setObject:[_applePatch objectForKey:@"patch"] forKey:@"patch"];
                                [tmpDict setObject:[_applePatch objectForKey:@"description"] forKey:@"description"];
                                [tmpDict setObject:[_applePatch objectForKey:@"restart"] forKey:@"restart"];
                                [tmpDict setObject:[_applePatch objectForKey:@"version"] forKey:@"version"];
                                [tmpDict setObject:[_applePatchApproved objectForKey:@"severity"] forKey:@"severity"];
                                
                                if ([_applePatchApproved objectForKey:@"hasCriteria"])
								{
                                    [tmpDict setObject:[_applePatchApproved objectForKey:@"hasCriteria"] forKey:@"hasCriteria"];
                                    if ([_applePatchApproved[@"hasCriteria"] boolValue] == YES)
									{
                                        if (_applePatchApproved[@"criteria_pre"] && [_applePatchApproved[@"criteria_pre"] count] > 0)
										{
                                            [tmpDict setObject:_applePatchApproved[@"criteria_pre"] forKey:@"criteria_pre"];
                                        }
                                        if (_applePatchApproved[@"criteria_post"] && [_applePatchApproved[@"criteria_post"] count] > 0)
										{
                                            [tmpDict setObject:_applePatchApproved[@"criteria_post"] forKey:@"criteria_post"];
                                        }
                                    }
                                }
                                [tmpDict setObject:@"Apple" forKey:@"type"];
                                [tmpDict setObject:[[approvedApplePatches objectAtIndex:i] objectForKey:@"patch_install_weight"] forKey:@"patch_install_weight"];
                                logit(lcl_vDebug,@"Apple Patch Dictionary Added: %@",tmpDict);
                                [approvedUpdatesArray addObject:tmpDict];
                                break;
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Scan for Custom Patches to see what is relevant for the system
    if ((aFilter == 0) || (aFilter == 2))
    {
        logit(lcl_vInfo,@"Scanning for custom patch vulnerabilities...");
        customPatchesArray = (NSMutableArray *)[mpAsus scanForCustomUpdates];
        
        logit(lcl_vDebug,@"Custom Patches Needed: %@",customPatchesArray);
        logit(lcl_vDebug,@"Approved Custom Patches: %@",approvedCustomPatches);
        
        // Filter List of Patches containing only the approved patches
        logit(lcl_vInfo,@"Building approved patch list...");
        for (int i=0; i<[customPatchesArray count]; i++) {
            customPatch	= [customPatchesArray objectAtIndex:i];
            for (int x=0;x < [approvedCustomPatches count]; x++) {
                approvedPatch	= [approvedCustomPatches objectAtIndex:x];
                if ([[customPatch objectForKey:@"patch_id"] isEqualTo:[approvedPatch objectForKey:@"patch_id"]])
                {
                    logit(lcl_vInfo,@"Patch %@ approved for update.",[customPatch objectForKey:@"description"]);
                    logit(lcl_vDebug,@"Approved [customPatch]: %@",customPatch);
                    logit(lcl_vDebug,@"Approved [approvedPatch]: %@",approvedPatch);
                    tmpDict = [[NSMutableDictionary alloc] init];
                    [tmpDict setObject:[customPatch objectForKey:@"patch"] forKey:@"patch"];
                    [tmpDict setObject:[customPatch objectForKey:@"description"] forKey:@"description"];
                    [tmpDict setObject:[customPatch objectForKey:@"restart"] forKey:@"restart"];
                    [tmpDict setObject:[customPatch objectForKey:@"version"] forKey:@"version"];
                    [tmpDict setObject:[approvedPatch objectForKey:@"severity"] forKey:@"severity"];
                    [tmpDict setObject:approvedPatch forKey:@"patches"];
                    [tmpDict setObject:[customPatch objectForKey:@"patch_id"] forKey:@"patch_id"];
                    [tmpDict setObject:@"Third" forKey:@"type"];
                    [tmpDict setObject:[customPatch objectForKey:@"bundleID"] forKey:@"bundleID"];
                    [tmpDict setObject:[approvedPatch objectForKey:@"patch_install_weight"] forKey:@"patch_install_weight"];
                    
                    logit(lcl_vDebug,@"Custom Patch Dictionary Added: %@",tmpDict);
                    [approvedUpdatesArray addObject:tmpDict];
                    tmpDict = nil;
                    break;
                }
            }
        }
    }
    
    logit(lcl_vDebug,@"Approved patches to install: %@",approvedUpdatesArray);
    
done:
    
    // Remove File If Found
    if (aCritical == YES) {
        if ([fm fileExistsAtPath:PATCHES_CRITICAL_PLIST]) {
            [fm removeItemAtPath:PATCHES_CRITICAL_PLIST error:&rmErr];
        }
    } else {
        if ([fm fileExistsAtPath:PATCHES_NEEDED_PLIST]) {
            [NSKeyedArchiver archiveRootObject:[NSArray array] toFile:PATCHES_NEEDED_PLIST];
            [fm removeItemAtPath:PATCHES_NEEDED_PLIST error:&rmErr];
        }
    }
    
    // Sleep 1 sec
    [NSThread sleepForTimeInterval:1];
	
	// Write out user_install patches, overwrite the file contents.
	// The MP_CRITICAL_UPDATES_PLIST constant is for User Install updates
	if (userInstallApplePatches.count >= 1)
	{
		[userInstallApplePatches writeToFile:MP_CRITICAL_UPDATES_PLIST atomically:NO];
	}
	
	
    // Re-write file with new patch info
    if (approvedUpdatesArray && [approvedUpdatesArray count] > 0)
    {
        if (aCritical == YES) {
            logit(lcl_vInfo,@"Writing approved patches to %@",PATCHES_CRITICAL_PLIST);
            [NSKeyedArchiver archiveRootObject:approvedUpdatesArray toFile:PATCHES_CRITICAL_PLIST];
        } else {
            logit(lcl_vInfo,@"Writing approved patches to %@",PATCHES_NEEDED_PLIST);
            [NSKeyedArchiver archiveRootObject:approvedUpdatesArray toFile:PATCHES_NEEDED_PLIST];
        }
    }
	else
	{
        if (aCritical == YES) {
            [NSKeyedArchiver archiveRootObject:[NSArray array] toFile:PATCHES_CRITICAL_PLIST];
        } else {
            [NSKeyedArchiver archiveRootObject:[NSArray array] toFile:PATCHES_NEEDED_PLIST];
        }
    }
	
    if ([_defaults objectForKey:@"PreStageUpdates"])
    {
        logit(lcl_vInfo,@"PreStageUpdates is enabled.");
        if ([approvedUpdatesArray count] >= 1)
        {
            mpa = [[MPAsus alloc] init];
            for (NSDictionary *_patch in approvedUpdatesArray)
            {
                logit(lcl_vInfo,@"Pre staging update %@.",[_patch objectForKey:@"patch"]);
                if ([[_patch objectForKey:@"type"] isEqualToString:@"Apple"])
                {
                    [mpa downloadAppleUpdate:[_patch objectForKey:@"patch"]];
                }
                else
                {
                    // This is to clean up non used patches
                    [approvedUpdateIDsArray addObject:[_patch objectForKey:@"patch_id"]];
                    
                    patchesFromPatch = [[_patch objectForKey:@"patches"] objectForKey:@"patches"];
                    for (NSDictionary *_p in patchesFromPatch)
                    {
                        dlErr = nil;
                        stageDir = [NSString stringWithFormat:@"%@/Data/.stage/%@",MP_ROOT_CLIENT,[_patch objectForKey:@"patch_id"]];
                        downloadURL = [NSString stringWithFormat:@"/mp-content%@",[_p objectForKey:@"url"]];
                        if ([fm fileExistsAtPath:[stageDir stringByAppendingPathComponent:[[_p objectForKey:@"url"] lastPathComponent]]])
                        {
                            // Migth want to check hash here
                            logit(lcl_vInfo,@"Patch %@ is already pre-staged.",[_patch objectForKey:@"patch"]);
                            continue;
                        }
                        
                        // Create Staging Dir
                        isDir = NO;
                        exists = [fm fileExistsAtPath:stageDir isDirectory:&isDir];
                        if (exists)
                        {
                            if (isDir) {
                                if ([fm fileExistsAtPath:[stageDir stringByAppendingPathComponent:[[_p objectForKey:@"url"] lastPathComponent]]])
                                {
                                    if ([[[_p objectForKey:@"hash"] uppercaseString] isEqualTo:[[crypto md5HashForFile:[stageDir stringByAppendingPathComponent:[[_p objectForKey:@"url"] lastPathComponent]]] uppercaseString]])
                                    {
                                        qlinfo(@"Patch %@ has already been staged.",[_patch objectForKey:@"patch"]);
                                        continue;
                                    } else {
                                        dlErr = nil;
                                        [fm removeItemAtPath:[stageDir stringByAppendingPathComponent:[[_p objectForKey:@"url"] lastPathComponent]] error:&dlErr];
                                        if (dlErr) {
                                            qlerror(@"Unable to remove bad staged patch file %@",[stageDir stringByAppendingPathComponent:[[_p objectForKey:@"url"] lastPathComponent]]);
                                            qlerror(@"Can not stage %@",[_patch objectForKey:@"patch"]);
                                            continue;
                                        }
                                    }
                                    
                                }
                            } else {
                                // Is not a dir but is a file, just remove it. It's in our space
                                dlErr = nil;
                                [fm removeItemAtPath:stageDir error:&dlErr];
                                if (dlErr) {
                                    qlerror(@"Unable to remove bad staged directory/file %@",stageDir);
                                    qlerror(@"Can not stage %@",[_patch objectForKey:@"patch"]);
                                    continue;
                                }
                            }
                        } else {
                            // Stage dir does not exists, create it.
                            dlErr = nil;
                            [fm createDirectoryAtPath:stageDir withIntermediateDirectories:YES attributes:nil error:&dlErr];
                            if (dlErr) {
                                qlerror(@"%@",dlErr.localizedDescription);
                                qlerror(@"Can not stage %@",[_patch objectForKey:@"patch"]);
                                continue; // Error creating stage patch dir. Can not use it.
                            }
                        }
                        
                        qlinfo(@"Download patch from: %@",downloadURL);
                        dlErr = nil;
                        dlPatchLoc = [mpAsus downloadUpdate:downloadURL error:&dlErr];
                        if (dlErr) {
                            qlerror(@"%@",dlErr.localizedDescription);
                        }
                        qldebug(@"Downloaded patch to %@",dlPatchLoc);
                        
                        dlErr = nil;
                        [fm moveItemAtPath:dlPatchLoc toPath:[stageDir stringByAppendingPathComponent:[[_p objectForKey:@"url"] lastPathComponent]] error:&dlErr];
                        if (dlErr) {
                            qlerror(@"%@",dlErr.localizedDescription);
                            continue; // Error creating stage patch dir. Can not use it.
                        }
                        qlinfo(@"%@ has been staged.",[_patch objectForKey:@"patches"]);
                        qldebug(@"Moved patch to: %@",[stageDir stringByAppendingPathComponent:[[_p objectForKey:@"url"] lastPathComponent]]);
                    }
                }
            }

            [self cleanupPreStagePatches:(NSArray *)approvedUpdateIDsArray];
        }
        
    }
    
    //[approvedUpdatesArray writeToFile:@"/tmp/approvedUpdates.plist" atomically:NO];
    
    // Added a global notification to update image icon of MPClientStatus
    if (aCritical == NO)
	{
        // We only update notification if a normal scan has run
        [[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"kRefreshStatusIconNotification" object:nil];
        [self setApprovedPatches:[NSArray arrayWithArray:approvedUpdatesArray]];
    }
    [self removeTaskRunning:kMPPatchSCAN];
    logit(lcl_vInfo,@"Patch Scan Completed.");
}

- (void)scanForPatchUsingBundleID:(NSString *)aBundleID
{
	NSMutableArray      *approvedUpdatesArray = [[NSMutableArray alloc] init];
	NSMutableDictionary *tmpDict;

    // Get Patch Group Patches
    MPWebServices *mpws = [[MPWebServices alloc] init];
    NSError *wsErr = nil;
    NSDictionary *patchGroupPatches = [mpws getPatchGroupContent:&wsErr];
    if (wsErr) {
        logit(lcl_vError,@"%@",wsErr.localizedDescription);
		return;
    }

	if (!patchGroupPatches) {
		logit(lcl_vError,@"There was a issue getting the approved patches for the patch group, scan will exit.");
		return;
	}

    NSArray *approvedCustomPatches = nil;
    approvedCustomPatches = [patchGroupPatches objectForKey:@"CustomUpdates"];

    logit(lcl_vInfo,@"Scanning for custom patch vulnerabilities...");
    logit(lcl_vInfo,@"Scanning for custom patch vulnerabilities for %@", aBundleID);
    NSMutableArray *customPatchesArray = (NSMutableArray *)[mpAsus scanForCustomUpdateUsingBundleID:aBundleID];

    logit(lcl_vDebug,@"Custom Patches Needed: %@",customPatchesArray);

    // Filter List of Patches containing only the approved patches
    NSDictionary *customPatch, *approvedPatch;
    logit(lcl_vInfo,@"Building approved patch list...");
    for (int i=0; i<[customPatchesArray count]; i++) {
        customPatch	= [customPatchesArray objectAtIndex:i];
        for (int x=0;x < [approvedCustomPatches count]; x++) {
            approvedPatch	= [approvedCustomPatches objectAtIndex:x];
            if ([[customPatch objectForKey:@"patch_id"] isEqualTo:[approvedPatch objectForKey:@"patch_id"]]) {
                logit(lcl_vInfo,@"Patch %@ approved for update.",[customPatch objectForKey:@"description"]);
                tmpDict = [[NSMutableDictionary alloc] init];
                [tmpDict setObject:[customPatch objectForKey:@"patch"] forKey:@"patch"];
                [tmpDict setObject:[customPatch objectForKey:@"description"] forKey:@"description"];
                [tmpDict setObject:[customPatch objectForKey:@"restart"] forKey:@"restart"];
                [tmpDict setObject:[customPatch objectForKey:@"version"] forKey:@"version"];
                [tmpDict setObject:approvedPatch forKey:@"patches"];
                [tmpDict setObject:[customPatch objectForKey:@"patch_id"] forKey:@"patch_id"];
                [tmpDict setObject:@"Third" forKey:@"type"];
                [tmpDict setObject:[customPatch objectForKey:@"bundleID"] forKey:@"bundleID"];

                logit(lcl_vDebug,@"Custom Patch Dictionary Added: %@",tmpDict);
                [approvedUpdatesArray addObject:tmpDict];
                tmpDict = nil;
                break;
            }
        }
    }

    [self setApprovedPatches:[NSArray arrayWithArray:approvedUpdatesArray]];
    logit(lcl_vInfo,@"Patch Scan Completed.");
}

-(void)scanForPatchesAndUpdate
{
    [self scanForPatchesAndUpdateWithFilterCritical:0 critical:NO];
}

-(void)scanForPatchesAndUpdateWithFilter:(int)aFilter
{
    [self scanForPatchesAndUpdateWithFilterCritical:aFilter critical:NO];
}

-(void)scanForPatchesAndUpdateWithFilterCritical:(int)aFilter critical:(BOOL)aCritical;
{
	if ([self isTaskRunning:kMPPatchUPDATE]) {
		logit(lcl_vInfo,@"Scan and update patches is already running. Now exiting.");
		return;
	} else {
		[self writeTaskRunning:kMPPatchUPDATE];
	}

	// Filter - 0 = All,  1 = Apple, 2 = Third
	NSArray *updatesArray = nil;
    NSString *updateFilePath = [NSString stringWithFormat:@"%@/Data/.approvedPatches.plist",MP_ROOT_CLIENT];

    // Check to see if we have a patch scan file within the last 15 minutes.
    // If we do, then use the contents of that file and no need to re-scan.
    if (aCritical == YES)
    {
        // Critical
        // Critical updates are allways written to a file
        updateFilePath = [NSString stringWithString:PATCHES_CRITICAL_PLIST];
    } else {
        // Non Critical
        if ([fm fileExistsAtPath:updateFilePath])
        {
            NSError *attributesRetrievalError = nil;
            NSDictionary *attributes = [fm attributesOfItemAtPath:updateFilePath error:&attributesRetrievalError];

            if (!attributes) {
                logit(lcl_vError,@"Error for file at %@: %@", updateFilePath, attributesRetrievalError);
            }
            NSDate *fmDate = [attributes fileModificationDate];
            // File was created within 15 minutes of last scan...
            if (([[NSDate date] timeIntervalSinceDate:fmDate] / 60) < 16) {
                logit(lcl_vDebug, @"Within 15 Minutes. Using scan file.");
                updatesArray = [NSKeyedUnarchiver unarchiveObjectWithFile:updateFilePath];
            } else {
                logit(lcl_vDebug, @"Older than 15 Minutes, rescanning.");
                [self scanForPatchesWithFilterWaitAndForce:0 byPassRunning:YES];
                updatesArray = [NSArray arrayWithArray:approvedPatches];
            }
        } else {
            // Scan for Patches
            [self scanForPatchesWithFilterWaitAndForce:0 byPassRunning:YES];
            updatesArray = [NSArray arrayWithArray:approvedPatches];
        }
    }
    // Sort Array
    NSSortDescriptor *desc = [NSSortDescriptor sortDescriptorWithKey:@"patch_install_weight" ascending:YES];
    updatesArray = [updatesArray sortedArrayUsingDescriptors:[NSArray arrayWithObject:desc]];

    // -------------------------------------------
    // Populate Array with Patch Results
    // -------------------------------------------
	if (!updatesArray) {
		logit(lcl_vInfo,@"Updates array is nil");
        [self removeTaskRunning:kMPPatchUPDATE];
        return;
	}
    if ([updatesArray count] <= 0) {
        logit(lcl_vInfo, @"No approved patches to install.");
        logit(lcl_vDebug,@"updatesArray=%@",updatesArray);
		[self removeTaskRunning:kMPPatchUPDATE];
        return;
    }

    // -------------------------------------------
	// Check to see if client os type is allowed to perform updates.
    // -------------------------------------------
	logit(lcl_vInfo, @"Validating client install status.");
	NSString *_osType = nil;
	_osType = [[MPSystemInfo osVersionInfo] objectForKey:@"ProductName"];
    logit(lcl_vInfo, @"OS Full Info: (%@)",[MPSystemInfo osVersionInfo]);
    logit(lcl_vInfo, @"OS Info: (%@)",_osType);
	if ([_osType isEqualToString:@"Mac OS X"]) {
		if ([_defaults objectForKey:@"AllowClient"]) {

            NSNumber *AllowClientVal = [NSNumber numberWithInt:1];
            if([[_defaults objectForKey:@"AllowClient"] isKindOfClass:[NSString class]])
            {
                AllowClientVal = [NSNumber numberWithInteger:[[_defaults objectForKey:@"AllowClient"] integerValue]];
            } else if ([[_defaults objectForKey:@"AllowClient"] isKindOfClass:[NSNumber class]]) {
                AllowClientVal = [_defaults objectForKey:@"AllowClient"];
            }

			if ([AllowClientVal isEqualToNumber:[NSNumber numberWithInt:0]]) {
				logit(lcl_vInfo,@"Host is a Mac OS X Client and AllowClient property is set to false. No updates will be applied.");
				[self removeTaskRunning:kMPPatchUPDATE];
                return;
			}
		}
	}

	logit(lcl_vInfo, @"Validating server install status.");
	if ([_osType isEqualToString:@"Mac OS X Server"]) {
		if ([_defaults objectForKey:@"AllowServer"]) {

            NSNumber *AllowServerVal = [NSNumber numberWithInt:0];
            if([[_defaults objectForKey:@"AllowServer"] isKindOfClass:[NSString class]])
            {
                AllowServerVal = [NSNumber numberWithInteger:[[_defaults objectForKey:@"AllowServer"] integerValue]];
            } else if ([[_defaults objectForKey:@"AllowServer"] isKindOfClass:[NSNumber class]]) {
                AllowServerVal = [_defaults objectForKey:@"AllowServer"];
            }

			if ([AllowServerVal isEqualToNumber:[NSNumber numberWithInt:0]]) {
				logit(lcl_vInfo,@"Host is a Mac OS X Server and AllowServer property is set to false. No updates will be applied.");
				[self removeTaskRunning:kMPPatchUPDATE];
                return;
			}
		} else {
			logit(lcl_vInfo,@"Host is a Mac OS X Server and AllowServer property is not defined. No updates will be applied.");
			[self removeTaskRunning:kMPPatchUPDATE];
            return;
		}
	}

    // -------------------------------------------
    // iLoad
    // -------------------------------------------
	if (iLoadMode == YES) {
		printf("Updates to install: %d\n", (int)[updatesArray count]);
	}

    // -------------------------------------------
    // Begin Patching Process
    // -------------------------------------------
    MPInstaller         *mpInstaller = nil;
    MPScript            *mpScript = nil;
    NSDictionary		*patch;
	NSDictionary		*currPatchToInstallDict;
	NSArray				*patchPatchesArray;
	NSString			*downloadURL;
	NSError				*err;
	
	MPCrypto 			*mpCrypto = [[MPCrypto alloc] init];
	SecKeyRef			pubKeyRef = [mpCrypto getKeyRef:[NSData dataWithContentsOfFile:MP_SERVER_PUB_KEY]];
    
    // Staging
    NSString *stageDir;

	int i;
	int installResult = 1;
	int	launchRebootWindow = 0;
	int installedPatchesNeedingReboot = 0;

    // Check for console user
	logit(lcl_vInfo, @"Checking for any logged in users.");
    BOOL hasConsoleUserLoggedIn = TRUE;
	@try {
		hasConsoleUserLoggedIn = [self isLocalUserLoggedIn];
	}
	@catch (NSException * e) {
		logit(lcl_vInfo, @"Error getting console user status. %@",e);
	}

	logit(lcl_vInfo, @"Begin installing patches.");
    for (i = 0; i < [updatesArray count]; i++)
	{
		// Create/Get Dictionary of Patch to install
		patch = nil;
		patch = [NSDictionary dictionaryWithDictionary:[updatesArray objectAtIndex:i]];

        qlinfo(@"Patch: %@",patch);
		if (overrideRebootPatchInstalls == NO)
		{
			if (hasConsoleUserLoggedIn == YES)
			{
				// Check if patch needs a reboot
				if ([[patch objectForKey:@"restart"] stringToBoolValue] == YES) {
					logit(lcl_vInfo,@"%@(%@) requires a reboot, this patch will be installed on logout.",[patch objectForKey:@"patch"],[patch objectForKey:@"version"]);
					launchRebootWindow++;
					continue;
				}
			}
		}
        /* Not completed ...
         if ([self checkPatchPreAndPostForRebootRequired:patchPatchesArray]) {
         logit(lcl_vInfo,@"One or more of the pre & post installs requires a reboot, this patch will be installed on logout.");
         continue;
         }
         */
        
        // -------------------------------------------
        // Now proceed to the download and install
        // -------------------------------------------
        installResult = -1;

        if ([patch[@"type"] isEqualTo:@"Third"] && (aFilter == 0 || aFilter == 2))
        {
            logit(lcl_vInfo,@"Starting install for %@",patch[@"patch"]);

			if (iLoadMode == YES) {
				printf("Begin: %s\n", [patch[@"patch"] cString]);
			}
            
            // Get all of the patches, main and subs
            // This is messed up, not sure why I have an array right within an array, needs to be fixed ...later :-)
			NSDictionary *_curPatch = [patch objectForKey:@"patches"]; //Patch Install Dict
            patchPatchesArray = [NSArray arrayWithArray:[patch[@"patches"] objectForKey:@"patches"]];
            logit(lcl_vDebug,@"Current patch has total patches associated with it %ld", ([patchPatchesArray count]-1));
			
			// Verify Patch Signature before proceeding
			// Verify task Has SW Signature
			/*
			if (![_curPatch objectForKey:@"patch_sig"]) {
				logit(lcl_vError,@"%@ patch has no signature, will not install.",patch[@"patch"]);
				continue;
			}
			
			// Verify Signature for patch
			if (![self isValidPatch:_curPatch]) {
				logit(lcl_vError,@"Unable to verify signature for patch, %@ will not install.",patch[@"patch"]);
				continue;
			} else {
				logit(lcl_vInfo,@"Signature was verfied for %@.",patch[@"patch"]);
			}
			 */

            NSString *dlPatchLoc; //Download location Path
            int patchIndex = 0;
            for (patchIndex=0; patchIndex < [patchPatchesArray count]; patchIndex++)
			{
                // Make sure we only process the dictionaries in the NSArray
                if ([[patchPatchesArray objectAtIndex:patchIndex] isKindOfClass:[NSDictionary class]]) {
                    currPatchToInstallDict = [NSDictionary dictionaryWithDictionary:[patchPatchesArray objectAtIndex:patchIndex]];
                } else {
                    logit(lcl_vInfo,@"Object found was not of dictionary type; could be a problem. %@",[patchPatchesArray objectAtIndex:patchIndex]);
                    continue;
                }
                
                BOOL usingStagedPatch = NO;
                BOOL downloadPatch = YES;

                // We have a currPatchToInstallDict to work with
                logit(lcl_vInfo,@"Start install for patch %@ from %@",[currPatchToInstallDict objectForKey:@"url"],[patch objectForKey:@"patch"]);

                // First we need to download the update
                @try
                {
                    // -------------------------------------------
                    // Check to see if the patch has been staged
                    // -------------------------------------------
                    stageDir = [NSString stringWithFormat:@"%@/Data/.stage/%@",MP_ROOT_CLIENT,[patch objectForKey:@"patch_id"]];
                    if ([fm fileExistsAtPath:[stageDir stringByAppendingPathComponent:[[currPatchToInstallDict objectForKey:@"url"] lastPathComponent]]])
                    {
                        dlPatchLoc = [stageDir stringByAppendingPathComponent:[[currPatchToInstallDict objectForKey:@"url"] lastPathComponent]];
                        if ([[[currPatchToInstallDict objectForKey:@"hash"] uppercaseString] isEqualTo:[[mpCrypto md5HashForFile:dlPatchLoc] uppercaseString]])
                        {
                            qlinfo(@"The staged file passed the file hash validation.");
                            usingStagedPatch = YES;
                            downloadPatch = NO;
                        } else {
                            logit(lcl_vError,@"The staged file did not pass the file hash validation.");
                        }
                    }
                    
                    // -------------------------------------------
                    // Check to see if we need to download the patch
                    // -------------------------------------------
                    if (downloadPatch)
                    {
                        logit(lcl_vInfo,@"Start download for patch from %@",[currPatchToInstallDict objectForKey:@"url"]);
                        
                        //Pre Proxy Config
                        downloadURL = [NSString stringWithFormat:@"/mp-content%@",[currPatchToInstallDict objectForKey:@"url"]];
                        
                        logit(lcl_vInfo,@"Download patch from: %@",downloadURL);
                        err = nil;
                        dlPatchLoc = [mpAsus downloadUpdate:downloadURL error:&err];
                        if (err) {
                            logit(lcl_vError,@"Error downloading a patch, skipping %@. Err Message: %@",[patch objectForKey:@"patch"],[err localizedDescription]);
                            break;
                        }
                        logit(lcl_vInfo,@"File downloaded to %@",dlPatchLoc);
                        
                        // -------------------------------------------
                        // Validate hash, before install
                        // -------------------------------------------
                        NSString *fileHash = [mpCrypto md5HashForFile:dlPatchLoc];
                        
                        logit(lcl_vInfo,@"Downloaded file hash: %@ (%@)",fileHash,[currPatchToInstallDict objectForKey:@"hash"]);
                        if ([[[currPatchToInstallDict objectForKey:@"hash"] uppercaseString] isEqualTo:[fileHash uppercaseString]] == NO)
                        {
                            logit(lcl_vError,@"The downloaded file did not pass the file hash validation. No install will occur.");
                            continue;
                        }
                    }
                }
                @catch (NSException *e) {
                    logit(lcl_vError,@"%@", e);
                    break;
                }

                // *****************************
                // Now we need to unzip
                logit(lcl_vInfo,@"Uncompressing patch, to begin install.");
                logit(lcl_vInfo,@"Begin decompression of file, %@",dlPatchLoc);
                err = nil;
                [mpAsus unzip:dlPatchLoc error:&err];
                if (err) {
                    logit(lcl_vError,@"Error decompressing a patch, skipping %@. Err Message:%@",[patch objectForKey:@"patch"],[err localizedDescription]);
                    break;
                }
                logit(lcl_vInfo,@"Patch has been decompressed.");

                // *****************************
                // Run PreInstall Script
                if ([[currPatchToInstallDict objectForKey:@"preinst"] length] > 0 && [[currPatchToInstallDict objectForKey:@"preinst"] isEqualTo:@"NA"] == NO)
				{
                    logit(lcl_vInfo,@"Begin pre install script.");
                    NSString *preInstScript = [[currPatchToInstallDict objectForKey:@"preinst"] decodeBase64AsString];
                    logit(lcl_vDebug,@"preInstScript=%@",preInstScript);

                    mpScript = [[MPScript alloc] init];
                    if ([mpScript runScript:preInstScript] == NO)
                    {
                        logit(lcl_vError,@"Error[%d] running pre-install script.",installResult);
                        mpScript = nil;
                        break;
                    }
                    mpScript = nil;
                }

                // *****************************
                // Install the update
                BOOL hadErr = NO;
                @try
				{
                    NSString *pkgPath;
                    NSString *pkgBaseDir = [dlPatchLoc stringByDeletingLastPathComponent];
                    NSPredicate *pkgPredicate = [NSPredicate predicateWithFormat:@"(SELF like [cd] '*.pkg') OR (SELF like [cd] '*.mpkg')"];
                    NSArray *pkgList = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:[dlPatchLoc stringByDeletingLastPathComponent] error:NULL] filteredArrayUsingPredicate:pkgPredicate];
                    installResult = -1;

                    // Install pkg(s)
                    for (int ii = 0; ii < [pkgList count]; ii++)
                    {
                        pkgPath = [NSString stringWithFormat:@"%@/%@",pkgBaseDir,[pkgList objectAtIndex:ii]];
                        logit(lcl_vInfo,@"Installing %@",[pkgPath lastPathComponent]);
                        logit(lcl_vInfo,@"Start install of %@",pkgPath);
                        mpInstaller = [[MPInstaller alloc] init];
                        installResult = [mpInstaller installPkg:pkgPath target:@"/" env:[currPatchToInstallDict objectForKey:@"env"]];
                        if (installResult != 0) {
                            logit(lcl_vError,@"Error installing package, error code %d.",installResult);
                            hadErr = YES;
                            break;
                        } else {
                            [self updateNeededPatchesFile:patch];
                            logit(lcl_vInfo,@"%@ was installed successfully.",pkgPath);
                        }
                    } // End Loop


					// If the Patch we just installed needed a reboot ...
                    if ([[patch objectForKey:@"restart"] stringToBoolValue] == YES) {
						installedPatchesNeedingReboot++;
					}
                }
                @catch (NSException *e) {
                    logit(lcl_vError,@"%@", e);
                    logit(lcl_vError,@"Error attempting to install patch, skipping %@. Err Message:%@",[patch objectForKey:@"patch"],[err localizedDescription]);
                    break;
                }
                if (hadErr) {
                    // We had an error, try the next one.
                    continue;
                }

                // *****************************
                // Run PostInstall Script
                if ([[currPatchToInstallDict objectForKey:@"postinst"] length] > 0 && [[currPatchToInstallDict objectForKey:@"postinst"] isEqualTo:@"NA"] == NO)
				{
                    logit(lcl_vInfo,@"Begin post install script.");
                    NSString *postInstScript = [[currPatchToInstallDict objectForKey:@"postinst"] decodeBase64AsString];
                    logit(lcl_vDebug,@"postInstScript=%@",postInstScript);

                    mpScript = [[MPScript alloc] init];
                    if ([mpScript runScript:postInstScript] == NO)
                    {
                        logit(lcl_vError,@"Error[%d] running post-install script.",installResult);
                        mpScript = nil;
                        break;
                    }
                    mpScript = nil;
                }

                // *****************************
                // Instal is complete, post result to web service

                @try
				{
                    MPWebServices *mpws = [[MPWebServices alloc] init];
                    NSError *wsErr = nil;
                    [mpws postPatchInstallResultsToWebService:[patch objectForKey:@"patch_id"] patchType:@"third" error:&wsErr];
                    logit(lcl_vInfo,@"Posting patch (%@) install to web service.",[patch objectForKey:@"patch_id"]);
                    if (wsErr) {
                        logit(lcl_vError,@"%@", wsErr.localizedDescription);
                    }
                }
                @catch (NSException *e) {
                    logit(lcl_vError,@"%@", e);
                }

				if (iLoadMode == YES) {
					fprintf(stdout, "Completed: %s\n", [[patch objectForKey:@"patch"] cString]);
				}
                
                // -------------------------------------------
                // If staged, remove staged patch dir
                // -------------------------------------------
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
                
				[self removeInstalledPatchFromCacheFile:[patch objectForKey:@"patch"]];
                logit(lcl_vInfo,@"Patch install completed.");

            } // End patchArray To install
            // ***************************************************************************************
            // Process Apple Type Patches
        }
        else if ([[patch objectForKey:@"type"] isEqualTo:@"Apple"] && (aFilter == 0 || aFilter == 1))
        {
            //
            // ***************************************************************************************

            logit(lcl_vInfo,@"Starting install for %@",[patch objectForKey:@"patch"]);
            logit(lcl_vDebug,@"Apple Dict:%@",patch);

			if (iLoadMode == YES) {
				fprintf(stdout, "Begin: %s\n", [[patch objectForKey:@"patch"] cString]);
			}

            if ([[patch objectForKey:@"hasCriteria"] boolValue] == NO || ![patch objectForKey:@"hasCriteria"])
            {
                mpInstaller = [[MPInstaller alloc] init];
                installResult = [mpInstaller installAppleSoftwareUpdate:[patch objectForKey:@"patch"]];
                mpInstaller = nil;
            }
            else
            {
                logit(lcl_vInfo,@"%@ has install criteria assigned to it.",[patch objectForKey:@"patch"]);

                NSDictionary *criteriaDictPre, *criteriaDictPost;
                NSString *scriptText;

                int i = 0;
                // PreInstall First
                if ([patch objectForKey:@"criteria_pre"]) {
                    logit(lcl_vInfo,@"Processing pre-install criteria.");
                    for (i=0;i<[[patch objectForKey:@"criteria_pre"] count];i++)
                    {
                        criteriaDictPre = [[patch objectForKey:@"criteria_pre"] objectAtIndex:i];
                        scriptText = [[criteriaDictPre objectForKey:@"data"] decodeBase64AsString];

                        mpScript = [[MPScript alloc] init];
                        if ([mpScript runScript:scriptText] == NO) {
                            installResult = 1;
                            logit(lcl_vError,@"Pre-install script returned false for %@. No install will occur.",[patch objectForKey:@"patch"]);
                            mpScript = nil;
                            goto instResult;
                        } else {
                            logit(lcl_vInfo,@"Pre-install script returned true.");
                        }
                        mpScript = nil;
                        criteriaDictPre = nil;
                    }
                }
                // Run the patch install, now that the install has occured.
                mpInstaller = [[MPInstaller alloc] init];
                installResult = [mpInstaller installAppleSoftwareUpdate:[patch objectForKey:@"patch"]];
                mpInstaller = nil;

                // If Install retuened anything but 0, the dont run post criteria
                if (installResult != 0) {
                    logit(lcl_vError,@"The install for %@ returned an error.",[patch objectForKey:@"patch"]);
                    goto instResult;
                }

                if ([patch objectForKey:@"criteria_post"]) {
                    logit(lcl_vInfo,@"Processing post-install criteria.");
                    for (i=0;i<[[patch objectForKey:@"criteria_post"] count];i++)
                    {
                        criteriaDictPost = [[patch objectForKey:@"criteria_post"] objectAtIndex:i];
                        scriptText = [[criteriaDictPost objectForKey:@"data"] decodeBase64AsString];

                        mpScript = [[MPScript alloc] init];
                        if ([mpScript runScript:scriptText] == NO) {
                            installResult = 1;
                            logit(lcl_vError,@"Post-install script returned false for %@. No install will occur.",[patch objectForKey:@"patch"]);
                            mpScript = nil;
                            goto instResult;
                        } else {
                            logit(lcl_vInfo,@"Post-install script returned true.");
                        }
                        mpScript = nil;
                        criteriaDictPost = nil;
                    }
                }
            }

        instResult:

            if (installResult != 0) {
                logit(lcl_vError,@"Error installing update, error code %d.",installResult);
                continue;
            } else {
                [self updateNeededPatchesFile:patch];
                logit(lcl_vInfo,@"%@ was installed successfully.",[patch objectForKey:@"patch"]);
            }

            // If the Patch Installed Required a Reboot, flag it
            if ([[patch objectForKey:@"restart"] stringToBoolValue] == YES) {
                installedPatchesNeedingReboot++;
            }

            // Post the results to web service
            @try
            {
                MPWebServices *mpws = [[MPWebServices alloc] init];
                NSError *wsErr = nil;
                [mpws postPatchInstallResultsToWebService:[patch objectForKey:@"patch"] patchType:@"apple" error:&wsErr];
                logit(lcl_vInfo,@"Posting patch (%@) install to web service.",[patch objectForKey:@"patch"]);
                if (wsErr) {
                    logit(lcl_vError,@"%@", wsErr.localizedDescription);
                }
            }
            @catch (NSException *e)
            {
                logit(lcl_vError,@"%@", e);
            }

			if (iLoadMode == YES)
            {
				fprintf(stdout, "Completed: %s\n", [[patch objectForKey:@"patch"] cString]);
			}

            logit(lcl_vInfo,@"Patch install completed.");
        }
        else
        {
            continue;
        }
	} //End patchesToInstallArray For Loop

	// Update GUI to reflect new installs
	[fm createFileAtPath:[CLIENT_PATCH_STATUS_FILE stringByExpandingTildeInPath]
                contents:[@"update" dataUsingEncoding:NSASCIIStringEncoding]
              attributes:nil];

	// Open the Reboot App
    mpInstaller = [[MPInstaller alloc] init];

	// If any patches that were installed needed a reboot
    logit(lcl_vDebug,@"Number of installed patches needing a reboot %d.", installedPatchesNeedingReboot);
	if (installedPatchesNeedingReboot > 0)
    {
        if (iLoadMode == YES) {
			logit(lcl_vInfo,@"Patches have been installed that require a reboot. Please reboot the systems as soon as possible.");
			goto done;
		}
		if (hasConsoleUserLoggedIn == NO) {
			if ([_defaults objectForKey:@"Reboot"]) {
				if ([[_defaults objectForKey:@"Reboot"] isEqualTo:@"1"]) {
					logit(lcl_vInfo,@"Patches have been installed that require a reboot. Rebooting system now.");
					int rb = 0;
					rb = reboot(RB_AUTOBOOT);
				} else {
					logit(lcl_vInfo,@"Patches have been installed that require a reboot. Please reboot the systems as soon as possible.");
					goto done;
				}

			}
		} else {
            logit(lcl_vDebug,@"Console user found.");
        }
	}

	if (launchRebootWindow > 0)
    {
		logit(lcl_vInfo,@"Patches that require reboot need to be installed. Opening reboot dialog now.");
        // 10.9
        NSString *_atFile = @"/private/tmp/.MPAuthRun";
        NSString *_rbFile = @"/private/tmp/.MPRebootRun.plist";
		NSString *_rbText = @"reboot";
        // Mac OS X 10.9 Support, now using /private/tmp/.MPAuthRun
        NSDictionary *rebootPlist = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:@"reboot"];
        [rebootPlist writeToFile:_rbFile atomically:YES];
        [_rbText writeToFile:_atFile atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        NSDictionary *_fileAttr =  [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedLong:0777],@"NSFilePosixPermissions",nil];
		[fm setAttributes:_fileAttr ofItemAtPath:_rbFile error:NULL];
        [fm setAttributes:_fileAttr ofItemAtPath:_atFile error:NULL];
	}

done:
    // Added a global notification to update image icon of MPClientStatus
    [[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"kRefreshStatusIconNotification" object:nil];
	[self removeTaskRunning:kMPPatchUPDATE];
}

- (void)updateNeededPatchesFile:(NSDictionary *)aPatch
{
    // Updates the Patches Needed file by removing a installed
    // patch from the patches needed file, which is used
    // by MPClientStatus.app
    
    NSMutableArray *patchesNew;
    NSArray *patches;
    
    if ([fm fileExistsAtPath:PATCHES_NEEDED_PLIST]) {
        patches = [NSArray arrayWithArray:[NSKeyedUnarchiver unarchiveObjectWithFile:PATCHES_NEEDED_PLIST]];
        [NSKeyedArchiver archiveRootObject:[NSArray array] toFile:PATCHES_NEEDED_PLIST];
    } else {
        return;
    }

    patchesNew = [[NSMutableArray alloc] init];
    if (patches) {
        for (NSDictionary *p in patches) {
            if ([[p objectForKey:@"patch_id"] isEqualTo:[aPatch objectForKey:@"patch_id"]]) {
                qlinfo(@"Remove patch from array, %@",[aPatch objectForKey:@"patch"]);
                qldebug(@"%@",[aPatch objectForKey:@"patch"]);
            } else if ([[p objectForKey:@"patch"] isEqualTo:[aPatch objectForKey:@"patch"]] && [[p objectForKey:@"type"] isEqualTo:@"Apple"]) {
                qlinfo(@"Remove %@ patch from array, %@",[aPatch objectForKey:@"type"], aPatch);
            } else {
                [patchesNew addObject:p];
            }
        }
    }

    if (patchesNew.count >= 1) {
        [NSKeyedArchiver archiveRootObject:(NSArray *)patchesNew toFile:PATCHES_NEEDED_PLIST];
    } else {
        [NSKeyedArchiver archiveRootObject:[NSArray array] toFile:PATCHES_NEEDED_PLIST];
    }
}

-(void)scanAndUpdateCustomWithPatchBundleID:(NSString *)aPatchBundleID
{
    qldebug(@"scanAndUpdateCustomWithPatchBundleID:%@",aPatchBundleID);

	// Filter - 0 = All,  1 = Apple, 2 = Third
	NSArray *updatesArray = nil;
    NSArray *updatesArrayRaw = nil;

    // Scan for Patches
    [self scanForPatchUsingBundleID:aPatchBundleID];
    updatesArrayRaw = [NSArray arrayWithArray:approvedPatches];
    // Filter on bundle ID
    NSPredicate *p = [NSPredicate predicateWithFormat:@"(bundleID == %@)", aPatchBundleID];
	updatesArray = [updatesArrayRaw filteredArrayUsingPredicate:p];

	if (!updatesArray) {
		logit(lcl_vInfo,@"Updates array is nil");
        [self removeTaskRunning:kMPPatchUPDATE];
        [self setErrorCode:0];
        return;
	}
    if ([updatesArray count] <= 0) {
        logit(lcl_vInfo, @"No approved patches to install.");
        logit(lcl_vDebug,@"updatesArray=%@",updatesArray);
		[self removeTaskRunning:kMPPatchUPDATE];
        [self setErrorCode:0];
        return;
    }

	// Check to see if client os type is allowed to perform updates.
	logit(lcl_vInfo, @"Validating client install status.");
	NSString *_osType = nil;
	_osType = [[MPSystemInfo osVersionInfo] objectForKey:@"ProductName"];
	if ([_osType isEqualToString:@"Mac OS X"]) {
		if ([_defaults objectForKey:@"AllowClient"]) {
			if (![[_defaults objectForKey:@"AllowClient"] isEqualToString:@"1"]) {
				logit(lcl_vInfo,@"Host is a Mac OS X Client and AllowClient property is set to false. No updates will be applied.");
				[self removeTaskRunning:kMPPatchUPDATE];
                [self setErrorCode:0];
                return;
			}
		}
	}

	logit(lcl_vInfo, @"Validating server install status.");
	if ([_osType isEqualToString:@"Mac OS X Server"]) {
		if ([_defaults objectForKey:@"AllowServer"]) {
			if (![[_defaults objectForKey:@"AllowServer"] isEqualToString:@"1"]) {
				logit(lcl_vInfo,@"Host is a Mac OS X Server and AllowServer property is set to false. No updates will be applied.");
				[self removeTaskRunning:kMPPatchUPDATE];
                [self setErrorCode:0];
                return;
			}
		} else {
			logit(lcl_vInfo,@"Host is a Mac OS X Server and AllowServer property is not defined. No updates will be applied.");
			[self removeTaskRunning:kMPPatchUPDATE];
            [self setErrorCode:0];
            return;
		}
	}

    // Begin Patching Process
    int                 hadError = 0;
	MPCrypto			*_crypto;
    MPInstaller         *mpInstaller = nil;
    MPScript            *mpScript = nil;
    NSDictionary		*patch;
	NSDictionary		*currPatchToInstallDict;
	NSArray				*patchPatchesArray;
	NSString			*downloadURL;
	NSError				*err;

	int i;
	int installResult = 1;
	int	launchRebootWindow = 0;
	int installedPatchesNeedingReboot = 0;

    // Check for console user
	logit(lcl_vInfo, @"Checking for any logged in users.");
    BOOL hasConsoleUserLoggedIn = TRUE;
	@try {
		hasConsoleUserLoggedIn = [self isLocalUserLoggedIn];
	}
	@catch (NSException * e) {
		logit(lcl_vInfo, @"Error getting console user status. %@",e);
	}

	logit(lcl_vInfo, @"Begin installing patches.");
    for (i = 0; i < [updatesArray count]; i++)
	{
		// Create/Get Dictionary of Patch to install
		patch = nil;
		patch = [NSDictionary dictionaryWithDictionary:[updatesArray objectAtIndex:i]];

		if (overrideRebootPatchInstalls == YES)
		{
			if (hasConsoleUserLoggedIn == YES)
			{
				// Check if patch needs a reboot
				if ([[patch objectForKey:@"restart"] stringToBoolValue] == YES) {
					logit(lcl_vInfo,@"%@(%@) requires a reboot, this patch will be installed on logout.",[patch objectForKey:@"patch"],[patch objectForKey:@"version"]);
					launchRebootWindow++;
					continue;
				}
			}
		}

        // Now proceed to the download and install
        installResult = -1;

        if ([[patch objectForKey:@"type"] isEqualTo:@"Third"])
		{
            logit(lcl_vInfo,@"Starting install for %@",[patch objectForKey:@"patch"]);
			[self postNotificationTo:@"MPPatchStatusNotification" info:[NSString stringWithFormat:@"Begin patching %@",[patch objectForKey:@"patch"]] isGlobal:YES];
			if (iLoadMode == YES) {
				printf("Begin: %s\n", [[patch objectForKey:@"patch"] cString]);
			}

            // Get all of the patches, main and subs
            // This is messed up, not sure why I have an array right within an array, needs to be fixed ...later :-)
            patchPatchesArray = [NSArray arrayWithArray:[[patch objectForKey:@"patches"] objectForKey:@"patches"]];
            logit(lcl_vDebug,@"Current patch has total patches associated with it %ld", ([patchPatchesArray count]-1));

            NSString *dlPatchLoc; //Download location Path
            int patchIndex = 0;
            for (patchIndex=0; patchIndex < [patchPatchesArray count]; patchIndex++)
			{
                // Make sure we only process the dictionaries in the NSArray
                if ([[patchPatchesArray objectAtIndex:patchIndex] isKindOfClass:[NSDictionary class]]) {
                    currPatchToInstallDict = [NSDictionary dictionaryWithDictionary:[patchPatchesArray objectAtIndex:patchIndex]];
                } else {
                    logit(lcl_vInfo,@"Object found was not of dictionary type; could be a problem. %@",[patchPatchesArray objectAtIndex:patchIndex]);
                    continue;
                }
                // We have a currPatchToInstallDict to work with
                logit(lcl_vInfo,@"Start install for patch %@ from %@",[currPatchToInstallDict objectForKey:@"url"],[patch objectForKey:@"patch"]);

                // First we need to download the update
                @try {
                    logit(lcl_vInfo,@"Start download for patch from %@",[currPatchToInstallDict objectForKey:@"url"]);
                    [self postNotificationTo:@"MPPatchStatusNotification" info:[NSString stringWithFormat:@"Downloading patch %@",[patch objectForKey:@"patch"]] isGlobal:YES];
                    //Pre Proxy Config
                    downloadURL = [NSString stringWithFormat:@"/mp-content%@",[currPatchToInstallDict objectForKey:@"url"]];
                    logit(lcl_vInfo,@"Download patch from: %@",downloadURL);
                    err = nil;
                    dlPatchLoc = [mpAsus downloadUpdate:downloadURL error:&err];
                    if (err) {
                        logit(lcl_vError,@"Error downloading a patch, skipping %@. Err Message: %@",[patch objectForKey:@"patch"],[err localizedDescription]);
                        break;
                    }
                    logit(lcl_vInfo,@"File downloaded to %@",dlPatchLoc);
                }
                @catch (NSException *e) {
                    logit(lcl_vError,@"%@", e);
                    hadError++;
                    break;
                }
                // *****************************
                // Validate hash, before install
                logit(lcl_vInfo,@"Validating downloaded patch.");
				_crypto = [[MPCrypto alloc] init];
                NSString *fileHash = [_crypto md5HashForFile:dlPatchLoc];
				_crypto = nil;
                logit(lcl_vInfo,@"Downloaded file hash: %@ (%@)",fileHash,[currPatchToInstallDict objectForKey:@"hash"]);
                if ([[[currPatchToInstallDict objectForKey:@"hash"] uppercaseString] isEqualTo:[fileHash uppercaseString]] == NO) {
                    logit(lcl_vError,@"The downloaded file did not pass the file hash validation. No install will occur.");
                    hadError++;
                    continue;
                }
                // *****************************
                // Now we need to unzip
                logit(lcl_vInfo,@"Uncompressing patch, to begin install.");
                logit(lcl_vInfo,@"Begin decompression of file, %@",dlPatchLoc);
                err = nil;
                [mpAsus unzip:dlPatchLoc error:&err];
                if (err) {
                    logit(lcl_vError,@"Error decompressing a patch, skipping %@. Err Message:%@",[patch objectForKey:@"patch"],[err localizedDescription]);
                    hadError++;
                    break;
                }
                logit(lcl_vInfo,@"Patch has been decompressed.");
                // *****************************
                // Run PreInstall Script
                if ([[currPatchToInstallDict objectForKey:@"preinst"] length] > 0 && [[currPatchToInstallDict objectForKey:@"preinst"] isEqualTo:@"NA"] == NO) {
                    logit(lcl_vInfo,@"Begin pre install script.");
                    NSString *preInstScript = [[currPatchToInstallDict objectForKey:@"preinst"] decodeBase64AsString];
                    logit(lcl_vDebug,@"preInstScript=%@",preInstScript);

                    mpScript = [[MPScript alloc] init];
                    if ([mpScript runScript:preInstScript] == NO)
                    {
                        logit(lcl_vError,@"Error[%d] running pre-install script.",installResult);
                        mpScript = nil;
                        hadError++;
                        break;
                    }
                    mpScript = nil;
                }
                // *****************************
                // Install the update
                BOOL hadErr = NO;
                @try
				{
                    NSString *pkgPath;
                    NSString *pkgBaseDir = [dlPatchLoc stringByDeletingLastPathComponent];
                    NSPredicate *pkgPredicate = [NSPredicate predicateWithFormat:@"(SELF like [cd] '*.pkg') OR (SELF like [cd] '*.mpkg')"];
                    NSArray *pkgList = [[fm contentsOfDirectoryAtPath:[dlPatchLoc stringByDeletingLastPathComponent] error:NULL] filteredArrayUsingPredicate:pkgPredicate];
                    installResult = -1;

                    // Install pkg(s)
                    for (int ii = 0; ii < [pkgList count]; ii++) {
                        pkgPath = [NSString stringWithFormat:@"%@/%@",pkgBaseDir,[pkgList objectAtIndex:ii]];
                        [self postNotificationTo:@"MPPatchStatusNotification" info:[NSString stringWithFormat:@"Installing patch %@",[pkgPath lastPathComponent]] isGlobal:YES];
                        logit(lcl_vInfo,@"Installing %@",[pkgPath lastPathComponent]);
                        logit(lcl_vInfo,@"Start install of %@",pkgPath);
                        mpInstaller = [[MPInstaller alloc] init];
                        installResult = [mpInstaller installPkg:pkgPath target:@"/" env:[currPatchToInstallDict objectForKey:@"env"]];
                        if (installResult != 0) {
                            logit(lcl_vError,@"Error installing package, error code %d.",installResult);
                            hadErr = YES;
                            hadError++;
                            break;
                        } else {
                            logit(lcl_vInfo,@"%@ was installed successfully.",pkgPath);
                        }
                    } // End Loop


					// If the Patch we just installed needed a reboot ...
					if ([[patch objectForKey:@"restart"] stringToBoolValue] == YES) {
						installedPatchesNeedingReboot++;
					}
                }
                @catch (NSException *e) {
                    logit(lcl_vError,@"%@", e);
                    logit(lcl_vError,@"Error attempting to install patch, skipping %@. Err Message:%@",[patch objectForKey:@"patch"],[err localizedDescription]);
                    hadError++;
                    break;
                }
                if (hadErr) {
                    // We had an error, try the next one.
                    continue;
                }
                // *****************************
                // Run PostInstall Script
                if ([[currPatchToInstallDict objectForKey:@"postinst"] length] > 0 && [[currPatchToInstallDict objectForKey:@"postinst"] isEqualTo:@"NA"] == NO) {
                    logit(lcl_vInfo,@"Begin post install script.");
                    NSString *postInstScript = [[currPatchToInstallDict objectForKey:@"postinst"] decodeBase64AsString];
                    logit(lcl_vDebug,@"postInstScript=%@",postInstScript);

                    mpScript = [[MPScript alloc] init];
                    if ([mpScript runScript:postInstScript] == NO)
                    {
                        logit(lcl_vError,@"Error[%d] running post-install script.",installResult);
                        mpScript = nil;
                        break;
                    }
                    mpScript = nil;
                }
                // *****************************
                // Instal is complete, post result to web service
                @try {
                    MPWebServices *mpws = [[MPWebServices alloc] init];
                    NSError *wsErr = nil;
                    logit(lcl_vInfo,@"Posting patch (%@) install to web service.",[patch objectForKey:@"patch_id"]);
                    [mpws postPatchInstallResultsToWebService:[patch objectForKey:@"patch_id"] patchType:@"third" error:&wsErr];
                    if (wsErr) {
                        logit(lcl_vError,@"%@", wsErr.localizedDescription);
                    }
                }
                @catch (NSException *e) {
                    logit(lcl_vError,@"%@", e);
                }

				if (iLoadMode == YES) {
					fprintf(stdout, "Completed: %s\n", [[patch objectForKey:@"patch"] cString]);
				}
				[self removeInstalledPatchFromCacheFile:[patch objectForKey:@"patch"]];
                [self postNotificationTo:@"MPPatchStatusNotification" info:@"Patch install completed." isGlobal:YES];
                logit(lcl_vInfo,@"Patch install completed.");

            } // End patchArray To install
        }
	} //End patchesToInstallArray For Loop

	// Update GUI to reflect new installs
	[fm createFileAtPath:[CLIENT_PATCH_STATUS_FILE stringByExpandingTildeInPath]
                contents:[@"update" dataUsingEncoding:NSASCIIStringEncoding]
              attributes:nil];

	// Open the Reboot App


	// If any patches that were installed needed a reboot
	if (installedPatchesNeedingReboot > 0) {
		if (hasConsoleUserLoggedIn == NO) {
			if ([_defaults objectForKey:@"Reboot"]) {
				if ([[_defaults objectForKey:@"Reboot"] isEqualTo:@"1"]) {
					logit(lcl_vInfo,@"Patches have been installed that require a reboot. Rebooting system now.");
					int rb = 0;
					rb = reboot(RB_AUTOBOOT);
				} else {
					logit(lcl_vInfo,@"Patches have been installed that require a reboot. Please reboot the systems as soon as possible.");
					goto done;
				}

			}
		}
	}

	if (launchRebootWindow > 0)
    {
		logit(lcl_vInfo,@"Patches that require reboot need to be installed. Opening reboot dialog now.");
        // 10.9 support
        NSString *_atFile = @"/private/tmp/.MPAuthRun";
        NSString *_rbFile = @"/private/tmp/.MPRebootRun.plist";
		NSString *_rbText = @"reboot";
        // Mac OS X 10.9 Support, now using /private/tmp/.MPAuthRun
        NSDictionary *rebootPlist = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:@"reboot"];
        [rebootPlist writeToFile:_rbFile atomically:YES];
        [_rbText writeToFile:_atFile atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        NSDictionary *_fileAttr =  [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedLong:0777],@"NSFilePosixPermissions",nil];
		[fm setAttributes:_fileAttr ofItemAtPath:_rbFile error:NULL];
        [fm setAttributes:_fileAttr ofItemAtPath:_atFile error:NULL];
	}

done:
    [self setErrorCode:hadError];
	[self removeTaskRunning:kMPPatchUPDATE];
}

-(BOOL)checkPatchPreAndPostForRebootRequired:(NSArray *)aDictArray
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

- (void)removeInstalledPatchFromCacheFile:(NSString *)aPatchName
{
	NSString *_approvedPatchesFile = [NSString stringWithFormat:@"%@/Data/.approvedPatches.plist",MP_ROOT_CLIENT];
	if (([fm fileExistsAtPath:_approvedPatchesFile] == NO) && ([fm fileExistsAtPath:PATCHES_NEEDED_PLIST] == NO)) {
		// No file, nothing todo.
		return;
	}

	NSMutableArray *_patchesArray = [NSMutableArray arrayWithArray:[NSKeyedUnarchiver unarchiveObjectWithFile:_approvedPatchesFile]];
	if ([_patchesArray count] <= 0) {
		// No Items in the Array, delete the file
		[fm removeItemAtPath:_approvedPatchesFile error:NULL];
        [NSKeyedArchiver archiveRootObject:[NSArray array] toFile:PATCHES_NEEDED_PLIST];
		return;
	}

	NSDictionary *_patchDict;
	for (int i = 0; i < [_patchesArray count]; i++)
	{
		_patchDict = [NSDictionary dictionaryWithDictionary:[_patchesArray objectAtIndex:i]];
		if ([[_patchDict objectForKey:@"patch"] isEqualToString:aPatchName]) {
			[_patchesArray removeObjectAtIndex:i];
			break;
		}
	}

	if ([_patchesArray count] <= 0) {
		// No Items in the Array, delete the file
		[fm removeItemAtPath:_approvedPatchesFile error:NULL];
        [NSKeyedArchiver archiveRootObject:[NSArray array] toFile:PATCHES_NEEDED_PLIST];
		return;
	} else {
        [NSKeyedArchiver archiveRootObject:_patchesArray toFile:_approvedPatchesFile];
        [NSKeyedArchiver archiveRootObject:_patchesArray toFile:PATCHES_NEEDED_PLIST];
	}

	return;
}

-(void)scanForAVDefs
{
	if ([self isTaskRunning:kMPAVUpdate]) {
		logit(lcl_vInfo,@"Scanning for av defs is already running. Now exiting.");
		return;
	} else {
		[self writeTaskRunning:kMPAVUpdate];
	}

	logit(lcl_vInfo,@"Begin scan for AV defs.");
	MPAntiVirus *mpav = [[MPAntiVirus alloc] init];
	[mpav scanDefs];
	mpav = nil;
	logit(lcl_vInfo,@"Scan for AV defs complete.");
	[self removeTaskRunning:kMPAVUpdate];
}

-(void)scanForAVDefsAndUpdate
{
	if ([self isTaskRunning:kMPAVUpdate]) {
		logit(lcl_vInfo,@"Updating av defs is already running. Now exiting.");
		return;
	} else {
		[self writeTaskRunning:kMPAVUpdate];
	}

	logit(lcl_vInfo,@"Begin scan and update for AV defs.");
	MPAntiVirus *mpav = [[MPAntiVirus alloc] init];
	[mpav scanAndUpdateDefs];
	mpav = nil;
	logit(lcl_vInfo,@"Scan and update for AV defs complete.");
	[self removeTaskRunning:kMPAVUpdate];
}

-(void)scanAndUpdateAgentUpdater
{
	logit(lcl_vInfo,@"Begin checking for agent updates.");
	NSDictionary *updateDataRaw = [self getAgentUpdaterInfo];
	if (!updateDataRaw) {
		logit(lcl_vError,@"Unable to get update data needed.");
		return;
	}

    // Check to make sure the object is the right type
    // This needs to be fixed in the next version.
    if (![updateDataRaw isKindOfClass:[NSDictionary class]])
    {
        logit(lcl_vError,@"Agent updater info is not available.");
        return;
    }

    // Check if update needed
	if (![updateDataRaw objectForKey:@"updateAvailable"] || [[updateDataRaw objectForKey:@"updateAvailable"] boolValue] == NO) {
		logit(lcl_vInfo,@"No update needed.");
		return;
	}

	if (![updateDataRaw objectForKey:@"SelfUpdate"]) {
		logit(lcl_vError,@"No update data found.");
		return;
	}

	NSDictionary *updateData = [NSDictionary dictionaryWithDictionary:[updateDataRaw objectForKey:@"SelfUpdate"]];

	NSError *err = nil;
	NSString *downloadURL;
	NSString *downloadFileLoc;

	// *****************************
	// First we need to download the update
	@try {
		logit(lcl_vInfo,@"Start download for patch from %@",[updateData objectForKey:@"pkg_Url"]);
		//Pre Proxy Config
		downloadURL = [updateData objectForKey:@"pkg_Url"];
		logit(lcl_vInfo,@"Download patch from: %@",downloadURL);
		err = nil;
		downloadFileLoc = [mpAsus downloadUpdate:downloadURL error:&err];
		if (err) {
			logit(lcl_vError,@"Error downloading update %@. Err Message: %@",[downloadURL lastPathComponent],[err localizedDescription]);
			return;
		}
		logit(lcl_vInfo,@"File downloaded to %@",downloadFileLoc);
	}
	@catch (NSException *e) {
		logit(lcl_vError,@"%@", e);
		return;
	}

	// *****************************
	// Validate hash, before install
	logit(lcl_vInfo,@"Validating downloaded patch.");
	MPCrypto *_crypto = [[MPCrypto alloc] init];
	NSString *fileHash = [_crypto sha1HashForFile:downloadFileLoc];
	_crypto = nil;
	logit(lcl_vInfo,@"Validating download file.");
	logit(lcl_vDebug,@"Downloaded file hash: (%@) (%@)",fileHash,[updateData objectForKey:@"pkg_Hash"]);
	logit(lcl_vDebug,@"%@",updateData);
	if ([[[updateData objectForKey:@"pkg_Hash"] uppercaseString] isEqualToString:[fileHash uppercaseString]] == NO) {
		logit(lcl_vError,@"The downloaded file did not pass the file hash validation. No install will occur.");
		return;
	}

	// *****************************
	// Now we need to unzip
	logit(lcl_vInfo,@"Uncompressing patch, to begin install.");
	logit(lcl_vInfo,@"Begin decompression of file, %@",downloadFileLoc);
	err = nil;
	[mpAsus unzip:downloadFileLoc error:&err];
	if (err) {
		logit(lcl_vError,@"Error decompressing a update %@. Err Message:%@",[downloadURL lastPathComponent],[err localizedDescription]);
		return;
	}
	logit(lcl_vInfo,@"Update has been decompressed.");

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
			logit(lcl_vInfo,@"Installing %@",[pkgPath lastPathComponent]);
			logit(lcl_vInfo,@"Start install of %@",pkgPath);
			mpInstaller = [[MPInstaller alloc] init];
			installResult = [mpInstaller installPkgToRoot:pkgPath];
			if (installResult != 0) {
				logit(lcl_vError,@"Error installing package, error code %d.",installResult);
				hadErr = YES;
				break;
			} else {
				logit(lcl_vInfo,@"%@ was installed successfully.",pkgPath);
			}
		} // End Loop
	}
	@catch (NSException *e) {
		logit(lcl_vError,@"%@", e);
		logit(lcl_vError,@"Error attempting to install update %@. Err Message:%@",[downloadURL lastPathComponent],[err localizedDescription]);
	}

	logit(lcl_vInfo,@"Checking for agent updates completed.");
	return;
}

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
        logit(lcl_vError,@"%ld: %@",err.code,err.localizedDescription);
    }
    cs = nil;
    if (verifyDevBin == YES)
    {
		verString = [mpr runTask:updateAppPath binArgs:[NSArray arrayWithObjects:@"-v", nil] error:&error];
		if (error) {
			logit(lcl_vError,@"%@",[error description]);
			verString = @"0";
		}
	}

	// Check for updates
    MPWebServices *mpws = [[MPWebServices alloc] init];
    NSError *wsErr = nil;
    NSDictionary *result = [mpws getAgentUpdaterUpdates:verString error:&wsErr];
    if (wsErr) {
        logit(lcl_vError,@"%@",wsErr);
        return nil;
    }
    return result;
}

- (BOOL)isTaskRunning:(NSString *)aTaskName
{
	if (forceRun == YES) {
		return NO;
	}

    NSDate *cdate; // CDate of File
    NSDate *cdatePlus; // CDate of file plus ... hrs
    NSDate *ndate = [NSDate date]; // Now

	if ([aTaskName isEqualToString:kMPPatchSCAN]) {
		if ([fm fileExistsAtPath:@"/tmp/.mpScanRunning"]) {
            cdate = [[fm attributesOfItemAtPath:@"/tmp/.mpScanRunning" error:nil] fileCreationDate];
            cdatePlus = [cdate dateByAddingTimeInterval:7200];
            NSComparisonResult result = [ndate compare:cdatePlus];
            if( result == NSOrderedAscending ) {
                // cdatePlus is in the future
                return YES;
            } else if(result==NSOrderedDescending) {
                // cdatePlus is in the past
                [self killTaskUsing:kMPPatchSCAN];
                logit(lcl_vError, @"Task file /tmp/.mpScanRunning found. File older than 2 hours. Deleting file.");
                [self removeTaskRunning:@"/tmp/.mpScanRunning"];
                return NO;
            }
            // Both dates are the same
			return NO;
		}
	}
	if ([aTaskName isEqualToString:kMPPatchUPDATE]) {
		if ([fm fileExistsAtPath:@"/tmp/.mpUpdateRunning"]) {
            cdate = [[fm attributesOfItemAtPath:@"/tmp/.mpUpdateRunning" error:nil] fileCreationDate];
			cdatePlus = [cdate dateByAddingTimeInterval:86400]; // Add 24 Hours
            NSComparisonResult result = [ndate compare:cdatePlus];
            if( result == NSOrderedAscending ) {
                // cdatePlus is in the future
                return YES;
            } else if(result==NSOrderedDescending) {
                // cdatePlus is in the past
                [self killTaskUsing:kMPPatchUPDATE];
                logit(lcl_vError, @"Task file /tmp/.mpUpdateRunning found. File older than 24 hours. Deleting file.");
                [self removeTaskRunning:@"/tmp/.mpUpdateRunning"];
                return NO;
            }
            // Both dates are the same
			return NO;
		}
	}
	if ([aTaskName isEqualToString:kMPInventory]) {
		if ([fm fileExistsAtPath:@"/tmp/.mpInventoryRunning"]) {
            cdate = [[fm attributesOfItemAtPath:@"/tmp/.mpInventoryRunning" error:nil] fileCreationDate];
			cdatePlus = [cdate dateByAddingTimeInterval:14400]; // Add 4 Hours
            NSComparisonResult result = [ndate compare:cdatePlus];
            if( result == NSOrderedAscending ) {
                // cdatePlus is in the future
                return YES;
            } else if(result==NSOrderedDescending) {
                // cdatePlus is in the past
                [self killTaskUsing:kMPInventory];
                logit(lcl_vError, @"Task file /tmp/.mpInventoryRunning found. File older than 4 hours. Deleting file.");
                [self removeTaskRunning:@"/tmp/.mpInventoryRunning"];
                return NO;
            }
            // Both dates are the same
			return NO;
		}
	}
	if ([aTaskName isEqualToString:kMPAVUpdate]) {
		if ([fm fileExistsAtPath:@"/tmp/.mpAVUpdateRunning"]) {
            cdate = [[fm attributesOfItemAtPath:@"/tmp/.mpAVUpdateRunning" error:nil] fileCreationDate];
			cdatePlus = [cdate dateByAddingTimeInterval:14400]; // Add 4 Hours
            NSComparisonResult result = [ndate compare:cdatePlus];
            if( result == NSOrderedAscending ) {
                // cdatePlus is in the future
                return YES;
            } else if(result==NSOrderedDescending) {
                // cdatePlus is in the past
                [self killTaskUsing:kMPAVUpdate];
                logit(lcl_vError, @"Task file /tmp/.mpAVUpdateRunning found. File older than 4 hours. Deleting file.");
                [self removeTaskRunning:@"/tmp/.mpAVUpdateRunning"];
                return NO;
            }
            // Both dates are the same
			return NO;
		}
	}

	return NO;
}

-(void)writeTaskRunning:(NSString *)aTaskName
{
	if (forceRun == NO) {
		NSString *_id = [@([[NSProcessInfo processInfo] processIdentifier]) stringValue];
		[_id writeToFile:[@"/tmp" stringByAppendingPathComponent:aTaskName] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
	}
}

-(void)removeTaskRunning:(NSString *)aTaskName
{
	logit(lcl_vInfo,@"Remove Task Running file for %@.",aTaskName);
	if ([fm fileExistsAtPath:[@"/tmp" stringByAppendingPathComponent:aTaskName]]) {
		logit(lcl_vInfo,@"File exists %@",aTaskName);
		logit(lcl_vDebug,@"File exists %@",[@"/tmp" stringByAppendingPathComponent:aTaskName]);
		if (forceRun == NO) {
			logit(lcl_vInfo,@"File remove %@",aTaskName);
			logit(lcl_vDebug,@"File remove %@",[@"/tmp" stringByAppendingPathComponent:aTaskName]);
			NSError *err = nil;
			[fm removeItemAtPath:[@"/tmp" stringByAppendingPathComponent:aTaskName] error:&err];
			if (err) {
				logit(lcl_vError,@"File remove %@\nError=%@",[@"/tmp" stringByAppendingPathComponent:aTaskName],[err description]);
			}
		} else {
			logit(lcl_vInfo,@"Force run is set to true for %@. No file will be removed.",aTaskName);
		}
	}
}

- (void)killTaskUsing:(NSString *)aTaskName
{
    int taskPID = -99;
    NSError *err = nil;
    NSString *taskFile = [@"/private/tmp" stringByAppendingPathComponent:aTaskName];
    // If File Does Not Exists, not PID to kill
    if (![fm fileExistsAtPath:taskFile]) {
        return;
    } else {
        NSString *strPID = [NSString stringWithContentsOfFile:taskFile encoding:NSUTF8StringEncoding error:&err];
        if (err) {
            logit(lcl_vError,@"%ld: %@",err.code,err.localizedDescription);
        }
        if ([strPID intValue] > 0) {
            taskPID = [strPID intValue];
        }
    }
    
    if (taskPID == -99) {
        logit(lcl_vWarning,@"No task PID was defined");
        return;
    }
    
    // Make Sure it's running before we send a SIGKILL
    NSArray *procArr = [MPSystemInfo bsdProcessList];
    NSArray *filtered = [procArr filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"processID == %i", taskPID]];
    if ([filtered count] <= 0) {
        return;
    } else if ([filtered count] == 1 ) {
        kill( taskPID, SIGKILL );
    } else {
        logit(lcl_vError,@"Can not kill task using PID. Found to many using the predicate.");
        logit(lcl_vDebug,@"%@",filtered);
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

-(void)postNotificationTo:(NSString *)aName info:(NSString *)info isGlobal:(BOOL)glb;
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

#pragma mark - SW Dist Installs
// Private
- (void)setUpSWDistProperties
{
    if (mp_SOFTWARE_DATA_DIR) {
        return;
    }
    needsReboot = 0;

    // Set Data Directory
    NSURL *appSupportDir = [[fm URLsForDirectory:NSApplicationSupportDirectory inDomains:NSSystemDomainMask] objectAtIndex:0];
    NSURL *appSupportMPDir = [appSupportDir URLByAppendingPathComponent:@"MacPatch"];
    [self setMp_SOFTWARE_DATA_DIR:[appSupportMPDir URLByAppendingPathComponent:@"SW_Data"]];
    if ([fm fileExistsAtPath:[mp_SOFTWARE_DATA_DIR path]] == NO) {
        NSError *err = nil;
        NSDictionary *attributes = [NSDictionary dictionaryWithObject:[NSNumber numberWithShort:0777] forKey:NSFilePosixPermissions];
        [fm createDirectoryAtPath:[mp_SOFTWARE_DATA_DIR path] withIntermediateDirectories:YES attributes:attributes error:&err];
        if (err) {
            logit(lcl_vError,@"%@",[err description]);
        }
    }
    if ([fm fileExistsAtPath:[[mp_SOFTWARE_DATA_DIR URLByAppendingPathComponent:@"sw"] path]] == NO) {
        NSError *err = nil;
        NSDictionary *attributes = [NSDictionary dictionaryWithObject:[NSNumber numberWithShort:0777] forKey:NSFilePosixPermissions];
        [fm createDirectoryAtPath:[[mp_SOFTWARE_DATA_DIR URLByAppendingPathComponent:@"sw"] path] withIntermediateDirectories:YES attributes:attributes error:&err];
        if (err) {
            logit(lcl_vError,@"%@",[err description]);
        }
        [[mp_SOFTWARE_DATA_DIR URLByAppendingPathComponent:@"sw"] setResourceValue:[NSNumber numberWithBool:YES] forKey:NSURLIsHiddenKey error:NULL];
    }
}

- (int)installSoftwareTasks:(NSString *)aTasks
{
    [self setUpSWDistProperties];
    needsReboot = 0;

    NSArray *_tasks = [aTasks componentsSeparatedByString:@","];
    if (!_tasks) {
        qlerror(@"Software tasks list was empty. No installs will occure.");
        return 1;
    }

    NSError *tErr = nil;
    for (NSString *aTask in _tasks) {
        tErr = nil;
        if ([self installSoftwareTask:aTask error:&tErr] == NO) {
            return 1;
        }
    }

    if (needsReboot >= 1) {
        qlerror(@"Software has been installed that requires a reboot.");
        return 2;
    }

    return 0;
}

- (int)installSoftwareTasksForGroup:(NSString *)aGroupName
{
    [self setUpSWDistProperties];
    needsReboot = 0;
    int result = 1;

    MPWebServices *mpws = [[MPWebServices alloc] init];
    NSError *wsErr = nil;
    id tasksRaw = [mpws getSWTasksForGroup:aGroupName error:&wsErr];
    NSArray *tasks;
    if ([tasksRaw objectForKey:@"Tasks"])
    {
        tasks = [tasksRaw objectForKey:@"Tasks"];
        if ([tasks count] <= 0) {
            qlerror(@"Group (%@) contains no tasks.",aGroupName);
            return 0;
        }
    } else {
        qlerror(@"No tasks for group %@ were found.",aGroupName);
        return result;
    }
    
    if (wsErr) {
        qlerror(@"There was an error getting software tasks for group %@.",aGroupName);
        return result;
    }
    if (!tasks) {
        qlerror(@"No tasks were found for group %@.",aGroupName);
        return result;
    }

    NSError *tErr = nil;
    for (NSDictionary *task in tasks) {
        tErr = nil;
        if ([self installSoftwareWithTask:task error:&tErr] == NO) {
            qlerror(@"FAILED to install task %@",[task objectForKey:@"name"]);
            if (tErr) {
                qlerror(@"%@",tErr.localizedDescription);
            }
             result = 1;
        }
    }

    if (needsReboot >= 1) {
        qlerror(@"Software has been installed that requires a reboot.");
        result = 2;
    }

    return result;
}

- (int)installSoftwareTasksUsingPLIST:(NSString *)aPlist
{
    [self setUpSWDistProperties];
    needsReboot = 0;
    int result = 0;
    
    if ([fm fileExistsAtPath:aPlist] == NO) {
        logit(lcl_vError,@"No installs will occure. Plist %@ was not found.",aPlist);
        return 1;
    }

    NSDictionary *pData = [NSDictionary dictionaryWithContentsOfFile:aPlist];
    if (![pData objectForKey:@"tasks"]) {
        logit(lcl_vError,@"No installs will occure. No tasks found.");
        return 1;
    }

    BOOL installWasSuccessful = NO;
    NSError *tErr = nil;
    NSArray *pTasks = [pData objectForKey:@"tasks"];
    for (NSString *aTask in pTasks)
    {
        tErr = nil;
        installWasSuccessful = [self installSoftwareTask:aTask error:&tErr];
        if (tErr || (installWasSuccessful == NO)) {
            qlerror(@"Software has been installed that requires a reboot.");
            result = 1;
        }
    }

    if (needsReboot >= 1) {
        qlerror(@"Software has been installed that requires a reboot.");
        return 2;
    }

    return result;
}

- (BOOL)installSoftwareWithTask:(NSDictionary *)aTask error:(NSError **)err
{
	NSMutableDictionary *errorDetail = [NSMutableDictionary dictionary];
    BOOL taskCanBeInstalled = [self softwareTaskCriteriaCheck:aTask];
    if (!taskCanBeInstalled) {
        [errorDetail setValue:@"Software Task failed basic criteria check." forKey:NSLocalizedDescriptionKey];
        *err = [NSError errorWithDomain:@"gov.llnl.mp.sw.install" code:1001 userInfo:errorDetail];
        return NO;
    }
    
    NSString *noteName = @"MPSWInstallStatus";
    NSString *tID = [aTask objectForKey:@"id"];
    [self postNotificationTo:noteName info:[NSString stringWithFormat:@"Installing [taskid:%@]: %@",tID,[aTask objectForKey:@"name"]] isGlobal:YES];
    logit(lcl_vInfo,@"Installing %@ (%@).",[aTask objectForKey:@"name"],[aTask objectForKey:@"id"]);
    logit(lcl_vInfo,@"INFO: %@",[aTask valueForKeyPath:@"Software.sw_type"]);
	
	
	// Verify task Has SW Signature
	/*
	if (![aTask objectForKey:@"sw_signature"]) {
		logit(lcl_vError,@"%@ task has no signature, will not install task.",[aTask objectForKey:@"name"]);
		[errorDetail setValue:@"Software Task failed, task has no signature." forKey:NSLocalizedDescriptionKey];
		*err = [NSError errorWithDomain:@"gov.llnl.mp.sw.install" code:1002 userInfo:errorDetail];
		return NO;
	}
	
	// Verify Signature for Software task
	logit(lcl_vInfo,@"Verify signature for task %@",[aTask objectForKey:@"name"]);
	if (![self isValidSoftwareTask:aTask[@"Software"] signature:aTask[@"sw_signature"]]) {
		logit(lcl_vError,@"Unable to verify signature for task %@ task, will not install task.",aTask[@"name"]);
		[errorDetail setValue:@"Unable to verify signature for software task." forKey:NSLocalizedDescriptionKey];
		*err = [NSError errorWithDomain:@"gov.llnl.mp.sw.install" code:1003 userInfo:errorDetail];
		return NO;
	} else {
		logit(lcl_vInfo,@"Signature for %@ passed verification.",aTask[@"name"]);
	}
	 */

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
        logit(lcl_vError,@"This system does not have enough free disk space to install the following software %@",[aTask objectForKey:@"name"]);
        return NO;
    }

    // Create Download URL
    [self postNotificationTo:noteName info:[NSString stringWithFormat:@"Downloading [taskid:%@]: %@",tID,[aTask objectForKey:@"name"]] isGlobal:YES];
    NSString *_url = [@"/mp-content" stringByAppendingPathComponent:[aTask valueForKeyPath:@"Software.sw_url"]];
    logit(lcl_vDebug,@"Download software from: %@",[aTask valueForKeyPath:@"Software.sw_type"]);

    NSError *dlErr = nil;
    NSURLResponse *response;
    MPNetConfig *mpnc = [[MPNetConfig alloc] init];
    MPNetRequest *req = [[MPNetRequest alloc] initWithMPServerArrayAndController:self servers:[mpnc servers]];
    NSURLRequest *urlReq = [req buildDownloadRequest:_url];
    NSString *dlPath = [req downloadFileRequest:urlReq returningResponse:&response error:&dlErr];

    if (dlErr) {
        logit(lcl_vError,@"Error[%d], trying to download file.",(int)[dlErr code]);
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

    logit(lcl_vDebug,@"returnCode: %d",[req errorCode]);
    // Software was downloaded
    if ([req errorCode] == 0)
    {
        logit(lcl_vInfo,@"Begin install for (%@).",[aTask objectForKey:@"name"]);
        int result = -1;
        int pResult = -1;

        result = [self installSoftwareViaProxy:aTask];

        if (result == 0)
        {
            // Software has been installed, now flag for reboot
            if ([[aTask valueForKeyPath:@"Software.reboot"] isEqualTo:@"1"]) {
                needsReboot++;
            }
            if ([[aTask valueForKeyPath:@"Software.auto_patch"] isEqualTo:@"1"]) {
                [self postNotificationTo:noteName info:@"Auto Patching is enabled, begin patching..." isGlobal:YES];
                pResult = [self patchSoftwareViaProxy:aTask];
                [NSThread sleepForTimeInterval:5];
            }

            [self postNotificationTo:noteName info:[NSString stringWithFormat:@"Installing [taskid:%@]: %@ completed.",tID,[aTask objectForKey:@"name"]] isGlobal:YES];
            [self recordInstallSoftwareItem:aTask];

            [self postInstallResults:result resultText:@"" task:aTask];
            return YES;
        } else {
            [self postNotificationTo:noteName info:[NSString stringWithFormat:@"Failed [taskid:%@]: %@ failed to install.",tID,[aTask objectForKey:@"name"]] isGlobal:YES];
            return NO;
        }
    }

    return NO;
}
// Private
- (BOOL)installSoftwareTask:(NSString *)aTask error:(NSError **)err
{
    NSError *swErr = nil;
    NSDictionary *task = [self swTaskForID:aTask error:&swErr];
    if (!task) {
        return NO;
    }
    return [self installSoftwareWithTask:task error:&swErr];
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
- (NSDictionary *)swTaskForID:(NSString *)aTaskID error:(NSError **)err
{
    NSError *wsErr = nil;
    MPWebServices *mpws = [[MPWebServices alloc] init];
    NSDictionary *task = [mpws getSWTaskForID:aTaskID error:&wsErr];
    if (wsErr) {
        logit(lcl_vError,@"%@", wsErr.localizedDescription);
        return nil;
    }

    return task;
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

#pragma mark - Misc

// Patch
- (BOOL)isValidPatch:(NSDictionary *)patch
{
	return YES; //Disabled
	/*
	MPCrypto 	*mpCrypto = [[MPCrypto alloc] init];
	SecKeyRef	pubKeyRef = [mpCrypto getKeyRef:[NSData dataWithContentsOfFile:MP_SERVER_PUB_KEY]];
	
	logit(lcl_vInfo,@"Checking signature for patch.");
	BOOL res = NO;
	NSString *strData = [self stringArrayToHash:patch[@"patches"]];
	NSData *sigData = [[NSData alloc] initWithBase64EncodedString:patch[@"patch_sig"] options:0];
	res = [mpCrypto verifiedSignedData:strData signature:sigData pubKey:pubKeyRef];
	sigData = nil;
	return res;
	 */
}

//Patch
- (NSString *)stringArrayToHash:(NSArray *)patches
{
	NSMutableString *_stringToSign = [NSMutableString new];
	NSArray *fields = @[@"baseline",@"env",@"hash",@"name",@"postinst",@"preinst",@"reboot",@"size",@"type",@"url"];
	for (NSDictionary *p in patches)
	{
		for (NSString *k in fields)
		{
			if ([[p allKeys] containsObject:k]) {
				[_stringToSign appendString:[p objectForKey:k]];
			}
		}
	}
	return (NSString *)_stringToSign;
}

// Software
- (BOOL)isValidSoftwareTask:(NSDictionary *)task signature:(NSString *)signature
{
	return YES; //Disabled
	
	MPCrypto 	*mpCrypto = [[MPCrypto alloc] init];
	SecKeyRef	pubKeyRef = [mpCrypto getKeyRef:[NSData dataWithContentsOfFile:MP_SERVER_PUB_KEY]];
	
	BOOL res = NO;
	NSString *strData = [self stringDictionaryToHash:task];
	NSData *sigData = [[NSData alloc] initWithBase64EncodedString:signature options:0];
	res = [mpCrypto verifiedSignedData:strData signature:sigData pubKey:pubKeyRef];
	sigData = nil;
	return res;
}

// Software
- (NSString *)stringDictionaryToHash:(NSDictionary *)task
{
	NSMutableString *_stringToSign = [NSMutableString new];
	NSArray *fields = @[@"auto_patch",@"name",@"patch_bundle_id",@"reboot",@"sid",@"state",
						@"sw_env_var",@"sw_hash",@"sw_post_install",@"sw_pre_install",@"sw_size",
						@"sw_type",@"sw_uninstall",@"sw_url",@"vendor",@"vendorUrl",@"version"];
	
	for (NSString *k in fields)
	{
		if ([[task allKeys] containsObject:k]) {
			[_stringToSign appendString:[task objectForKey:k]];
		}
	}
	return (NSString *)_stringToSign;
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

#pragma mark MPNetRequestController Callbacks
- (void)appendDownloadProgress:(double)aNumber
{
    //[progressBar setDoubleValue:aNumber];
}

- (void)appendDownloadProgressPercent:(NSString *)aPercent
{
    logit(lcl_vDebug,@"%d%%",[aPercent intValue]);
}

- (void)downloadStarted
{
    logit(lcl_vInfo,@"Download Started");
}

- (void)downloadFinished
{
    logit(lcl_vInfo,@"Download Finished");
}

- (void)downloadError
{
    logit(lcl_vError,@"Download Had An Error");
}

#pragma mark - Proxy Methods
-(int)installSoftwareViaProxy:(NSDictionary *)aInstallDict
{
	int results = -1;

	if (!proxy) {
        [self connect];
        if (!proxy) {
			logit(lcl_vError,@"Unable to connect to helper application. Functionality will be diminished.");
			[self cleanup];
            return results;
		}
    }

	@try {
		results = [proxy installSoftwareViaHelper:aInstallDict];
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"runTaskUsingHelper [installSoftwareViaHelper] error: %@", e);
    }

	[self cleanup];
	return results;
}

- (int)patchSoftwareViaProxy:(NSDictionary *)aInstallDict
{
    int results = -1;

	if (!proxy) {
        [self connect];
        if (!proxy) {
			logit(lcl_vError,@"Unable to connect to helper application. Functionality will be diminished.");
			[self cleanup];
            return results;
		}
    }

	@try {
		results = [proxy patchSoftwareViaHelper:aInstallDict];
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"runTaskUsingHelper [patchSoftwareViaProxy] error: %@", e);
    }

	[self cleanup];
	return results;
}

- (int)writeToFileViaProxy:(NSString *)aFile data:(id)data
{
    int results = -1;

	if (!proxy) {
        [self connect];
        if (!proxy) {
			logit(lcl_vError,@"Unable to connect to helper application. Functionality will be diminished.");
			[self cleanup];
            return results;
		}
    }

	@try {
		results = [proxy writeDataToFileViaHelper:data toFile:aFile];
        // Quick fix, script result is a bool
        if (results == 1) {
            results = 0;
        } else {
            results = 1;
        }
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"runTaskUsingHelper [writeDataToFileViaHelper] error: %@", e);
    }

	[self cleanup];
	return results;
}

- (int)writeArrayFileViaProxy:(NSString *)aFile data:(NSArray *)data
{
    int results = -1;

	if (!proxy) {
        [self connect];
        if (!proxy) {
			logit(lcl_vError,@"Unable to connect to helper application. Functionality will be diminished.");
			[self cleanup];
            return results;
		}
    }

	@try {
		results = [proxy writeArrayToFileViaHelper:data toFile:aFile];
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"writeArrayToFileViaHelper error: %@", e);
    }

	[self cleanup];
	return results;
}

#pragma mark - MPWorker

- (void)connect
{
    // Use mach ports for communication, since we're local.
    NSConnection *connection = [NSConnection connectionWithRegisteredName:kMPWorkerPortName host:nil];

    [connection setRequestTimeout: 60.0];
    [connection setReplyTimeout: 1800.0]; //30 min to install

    @try {
        proxy = [connection rootProxy];

        [[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(connectionDown:)
													 name:NSConnectionDidDieNotification
												   object:connection];

        [proxy setProtocolForProxy: @protocol(MPWorkerServer)];
        BOOL successful = [proxy registerClient:self];
        if (!successful) {
            logit(lcl_vError,@"Unable to connect to helper application.");
            [self cleanup];
        }
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"Could not connect to MPHelper: %@", e);
        [self cleanup];
    }
}

- (void)cleanup
{
    if (proxy)
    {
        NSConnection *connection = [proxy connectionForProxy];
        [connection invalidate];
        proxy = nil;
    }
}

- (void)connectionDown:(NSNotification *)notification
{
    logit(lcl_vDebug,@"helperd connection down");
    [self cleanup];
}

#pragma mark Client Callbacks
- (void)statusData:(in bycopy NSString *)aData
{
    NSString *noteName = @"MPSWInstallStatus";
    [self postNotificationTo:noteName info:aData isGlobal:YES];
}

- (void)installData:(in bycopy NSString *)aData
{
    NSString *strTxt;
    strTxt = [aData replaceAll:@"installer:STATUS:" replaceString:@""];
    strTxt = [strTxt replaceAll:@"installer:PHASE:" replaceString:@""];
    if ([aData containsString:@"installer:"]) {
        if (![strTxt containsString:@"installer:%"]) {
            NSString *noteName = @"MPSWInstallStatus";
            [self postNotificationTo:noteName info:strTxt isGlobal:YES];
        }
    }
}

@end
