//
//  MPAgentController.m
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

#import "MPAgentController.h"
#import "MacPatch.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import "Constants.h"
#include <sys/reboot.h>

@interface MPAgentController ()

@property (nonatomic, readwrite, assign) int errorCode;
@property (nonatomic, readwrite, strong) NSString *errorMsg;

@end

@implementation MPAgentController

@synthesize errorCode;
@synthesize errorMsg;

@synthesize _defaults;
@synthesize _cuuid;
@synthesize _appPid;
@synthesize iLoadMode;
@synthesize forceRun;
@synthesize approvedPatches;

- (id)init
{
    self = [super init];
    if (self) {
        fm = [NSFileManager defaultManager];
        MPDefaults *d = [[MPDefaults alloc] init];
        [self set_defaults:d.defaults];
		[self set_cuuid:[MPSystemInfo clientUUID]];
        mpAsus = [[MPAsus alloc] init];
        mpDataMgr = [[MPDataMgr alloc] init];
		[self setILoadMode:NO];
		[self setForceRun:NO];
		
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
		[self set_cuuid:[MPSystemInfo clientUUID]];
        mpAsus = [[MPAsus alloc] init];
        mpDataMgr = [[MPDataMgr alloc] init];
		[self setILoadMode:NO];
		[self setForceRun:NO];
        [self setErrorCode:-1];
        [self setErrorMsg:@""];
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

- (void)scanForPatches
{
	[self scanForPatchesWithFilter:0 byPassRunning:NO];
}

- (void)scanForPatchesWithFilter:(int)aFilter
{
    [self scanForPatchesWithFilter:aFilter byPassRunning:NO];
}

- (void)scanForPatchesWithFilter:(int)aFilter byPassRunning:(BOOL)aByPass
{
    [self scanForPatchesWithFilterWaitAndForce:aFilter byPassRunning:aByPass];
}

- (void)scanForPatchesWithFilterWaitAndForce:(int)aFilter byPassRunning:(BOOL)aByPass
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

    NSString            *_approvedPatchesFile = [NSString stringWithFormat:@"%@/Data/.approvedPatches.plist",MP_ROOT_CLIENT];
	NSMutableArray      *approvedUpdatesArray = [[NSMutableArray alloc] init];
	NSMutableDictionary *tmpDict;
    NSArray             *approvedApplePatches = nil;
    NSArray             *approvedCustomPatches = nil;
    MPASUSCatalogs      *mpCatalog;
    NSArray             *applePatchesArray = nil;
    NSMutableArray      *customPatchesArray;
    NSDictionary        *customPatch, *approvedPatch;
    NSDictionary        *patchGroupPatches;
    
	// Get Patch Group Patches
    NSError *wsErr = nil;
    MPWebServices *mpws = [[MPWebServices alloc] init];
    
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
            logit(lcl_vError,@"There was a issue getting the approved patches for the patch group, scan will exit. %@",wsErr.localizedDescription);
            goto done;
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

        // Process patches
        if (!applePatchesArray) {
            logit(lcl_vInfo,@"The scan results for ASUS scan were nil.");
        } else {
            // If no items in array, lets bail...
            if ([applePatchesArray count] == 0 ) {
                logit(lcl_vInfo,@"No Apple updates found.");
                sleep(1);
            } else {
                // We have Apple patches, now add them to the array of approved patches
                
                // If no items in array, lets bail...
                if ([approvedApplePatches count] == 0 ) {
                    logit(lcl_vInfo,@"No apple updates found for \"%@\" patch group.",[_defaults objectForKey:@"PatchGroup"]);
                } else {
                    // Build Approved Patches
                    logit(lcl_vInfo,@"Building approved patch list...");
                    
                    for (int i=0; i<[applePatchesArray count]; i++) {
                        for (int x=0;x < [approvedApplePatches count]; x++) {
                            if ([[[approvedApplePatches objectAtIndex:x] objectForKey:@"name"] isEqualTo:[[applePatchesArray objectAtIndex:i] objectForKey:@"patch"]]) {
                                logit(lcl_vInfo,@"Approved update %@",[[applePatchesArray objectAtIndex:i] objectForKey:@"patch"]);
                                logit(lcl_vDebug,@"Approved: %@",[approvedApplePatches objectAtIndex:x]);
                                tmpDict = [[NSMutableDictionary alloc] init];
                                [tmpDict setObject:[[applePatchesArray objectAtIndex:i] objectForKey:@"patch"] forKey:@"patch"];
                                [tmpDict setObject:[[applePatchesArray objectAtIndex:i] objectForKey:@"description"] forKey:@"description"];
                                [tmpDict setObject:[[applePatchesArray objectAtIndex:i] objectForKey:@"restart"] forKey:@"restart"];
                                [tmpDict setObject:[[applePatchesArray objectAtIndex:i] objectForKey:@"version"] forKey:@"version"];
                                
                                if ([[approvedApplePatches objectAtIndex:x] objectForKey:@"hasCriteria"]) {
                                    
                                    [tmpDict setObject:[[approvedApplePatches objectAtIndex:x] objectForKey:@"hasCriteria"] forKey:@"hasCriteria"];
                                    if ([[[approvedApplePatches objectAtIndex:x] objectForKey:@"hasCriteria"] boolValue] == YES) {
                                        if ([[approvedApplePatches objectAtIndex:x] objectForKey:@"criteria_pre"] && [[[approvedApplePatches objectAtIndex:x] objectForKey:@"criteria_pre"] count] > 0) {
                                            [tmpDict setObject:[[approvedApplePatches objectAtIndex:x] objectForKey:@"criteria_pre"] forKey:@"criteria_pre"];
                                        }
                                        if ([[approvedApplePatches objectAtIndex:x] objectForKey:@"criteria_post"] && [[[approvedApplePatches objectAtIndex:x] objectForKey:@"criteria_post"] count] > 0) {
                                            [tmpDict setObject:[[approvedApplePatches objectAtIndex:x] objectForKey:@"criteria_post"] forKey:@"criteria_post"];
                                        }
                                    }	
                                }
                                [tmpDict setObject:@"Apple" forKey:@"type"];
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
            for (int x=0;x < [approvedCustomPatches count]; x++)
			{
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
                    [tmpDict setObject:[approvedPatch objectForKey:@"bundle_id"] forKey:@"bundleID"];
                    
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
	[fm createFileAtPath:[CLIENT_PATCH_STATUS_FILE stringByExpandingTildeInPath] 
                contents:[@"update" dataUsingEncoding:NSASCIIStringEncoding] 
              attributes:nil];
    
    if ([fm isWritableFileAtPath:[_approvedPatchesFile stringByDeletingLastPathComponent]]) {
        logit(lcl_vDebug,@"Writing approved patches to %@",_approvedPatchesFile);
        [NSKeyedArchiver archiveRootObject:approvedUpdatesArray toFile:[NSString stringWithFormat:@"%@/Data/.approvedPatches.plist",MP_ROOT_CLIENT]];
        [NSKeyedArchiver archiveRootObject:approvedUpdatesArray toFile:PATCHES_NEEDED_PLIST];
    } else {
        logit(lcl_vError,@"Unable to write approved patches file %@. Patch file will not be used.",_approvedPatchesFile);
    }
	
	[self setApprovedPatches:[NSArray arrayWithArray:approvedUpdatesArray]];
	[self removeTaskRunning:kMPPatchSCAN];
    logit(lcl_vInfo,@"Patch Scan Completed.");
}

- (void)scanForPatchUsingBundleID:(NSString *)aBundleID
{
	NSMutableArray      *approvedUpdatesArray = [[NSMutableArray alloc] init];
	NSMutableDictionary *tmpDict;
    NSDictionary        *patchGroupPatches;
    
    // Get Patch Group Patches
    NSError *wsErr = nil;
    MPWebServices *mpws = [[MPWebServices alloc] init];
    
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
            logit(lcl_vError,@"There was a issue getting the approved patches for the patch group, scan will exit. %@",wsErr.localizedDescription);
            return;
        }
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
        for (int x=0;x < [approvedCustomPatches count]; x++)
		{
            approvedPatch	= [approvedCustomPatches objectAtIndex:x];
            if ([[customPatch objectForKey:@"patch_id"] isEqualTo:[approvedPatch objectForKey:@"patch_id"]])
			{
                logit(lcl_vInfo,@"Patch %@ approved for update.",[customPatch objectForKey:@"description"]);
                tmpDict = [[NSMutableDictionary alloc] init];
                [tmpDict setObject:[customPatch objectForKey:@"patch"] forKey:@"patch"];
                [tmpDict setObject:[customPatch objectForKey:@"description"] forKey:@"description"];
                [tmpDict setObject:[customPatch objectForKey:@"restart"] forKey:@"restart"];
                [tmpDict setObject:[customPatch objectForKey:@"version"] forKey:@"version"];
                [tmpDict setObject:approvedPatch forKey:@"patches"];
                [tmpDict setObject:[customPatch objectForKey:@"patch_id"] forKey:@"patch_id"];
                [tmpDict setObject:@"Third" forKey:@"type"];
                [tmpDict setObject:[approvedPatch objectForKey:@"bundle_id"] forKey:@"bundleID"];
                
                logit(lcl_vDebug,@"Custom Patch Dictionary Added: %@",tmpDict);
                [approvedUpdatesArray addObject:[tmpDict copy]];
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
	[self scanForPatchesAndUpdateWithFilter:0];
}

-(void)scanForPatchesAndUpdateWithFilter:(int)aFilter;
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
	
    if ([fm fileExistsAtPath:updateFilePath]) {
        NSError *attributesRetrievalError = nil;
        NSDictionary *attributes = [fm attributesOfItemAtPath:updateFilePath error:&attributesRetrievalError];
        
        if (!attributes) {
            logit(lcl_vError,@"Error for file at %@: %@", updateFilePath, attributesRetrievalError);
        }
        NSDate *fmDate = [attributes fileModificationDate];
        // File was created within 15 minutes of last scan...
        if (([[NSDate date] timeIntervalSinceDate:fmDate] / 60) < 16) {
            logit(lcl_vDebug, @"Within 15 Minutes. Using scan file.");
            updatesArray = [NSArray arrayWithContentsOfFile:updateFilePath];
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
    
    // Populate Array with Patch Results
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

	// Check to see if client os type is allowed to perform updates.
	logit(lcl_vInfo, @"Validating client install status.");
	NSString *_osType = nil;
	_osType = [[MPSystemInfo osVersionInfo] objectForKey:@"ProductName"];
	if ([_osType isEqualToString:@"Mac OS X"]) {
		if ([_defaults objectForKey:@"AllowClient"]) {
			if (![[_defaults objectForKey:@"AllowClient"] isEqualToString:@"1"]) {
				logit(lcl_vInfo,@"Host is a Mac OS X Client and AllowClient property is set to false. No updates will be applied.");
				[self removeTaskRunning:kMPPatchUPDATE];
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
                return;
			}
		} else {
			logit(lcl_vInfo,@"Host is a Mac OS X Server and AllowServer property is not defined. No updates will be applied.");
			[self removeTaskRunning:kMPPatchUPDATE];
            return;
		}
	}

	if (iLoadMode == YES) {
		printf("Updates to install: %d\n", (int)[updatesArray count]);
	}

    // Begin Patching Process
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
    for (i = 0; i < [updatesArray count]; i++) {
		// Create/Get Dictionary of Patch to install  
		patch = nil;
		patch = [NSDictionary dictionaryWithDictionary:[updatesArray objectAtIndex:i]];
        
		if (hasConsoleUserLoggedIn == YES) {
            // Check if patch needs a reboot
            if ([[patch objectForKey:@"restart"] stringToBoolValue] == YES) {
                logit(lcl_vInfo,@"%@(%@) requires a reboot, this patch will be installed on logout.",[patch objectForKey:@"patch"],[patch objectForKey:@"version"]);
                launchRebootWindow++;
                continue; 
            }
        }
        
         if ([self checkPatchPreAndPostForRebootRequired:patchPatchesArray]) {
             logit(lcl_vInfo,@"One or more of the pre & post installs requires a reboot, this patch will be installed on logout.");
             continue;
         }
        
        // Now proceed to the download and install			
        installResult = -1;
        
        if ([[patch objectForKey:@"type"] isEqualTo:@"Third"] && (aFilter == 0 || aFilter == 2)) {
            logit(lcl_vInfo,@"Starting install for %@",[patch objectForKey:@"patch"]);
			
			if (iLoadMode == YES) {
				printf("Begin: %s\n", [[patch objectForKey:@"patch"] cString]);
			}
            
            // Get all of the patches, main and subs
            // This is messed up, not sure why I have an array right within an array, needs to be fixed ...later :-)
            patchPatchesArray = [NSArray arrayWithArray:[[patch objectForKey:@"patches"] objectForKey:@"patches"]];
            logit(lcl_vDebug,@"Current patch has total patches associated with it %d", (int)([patchPatchesArray count]-1));
            
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
                    for (int ii = 0; ii < [pkgList count]; ii++) {
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
				[self removeInstalledPatchFromCacheFile:[patch objectForKey:@"patch"]];
                logit(lcl_vInfo,@"Patch install completed.");
                
            } // End patchArray To install
		// ***************************************************************************************
		// Process Apple Type Patches
        } else if ([[patch objectForKey:@"type"] isEqualTo:@"Apple"] && (aFilter == 0 || aFilter == 1)) {
        //
		// ***************************************************************************************	
            
            logit(lcl_vInfo,@"Starting install for %@",[patch objectForKey:@"patch"]);
            logit(lcl_vDebug,@"Apple Dict:%@",patch);
			
			if (iLoadMode == YES) {
				fprintf(stdout, "Begin: %s\n", [[patch objectForKey:@"patch"] cString]);
			}
            
            if ([[patch objectForKey:@"hasCriteria"] boolValue] == NO || ![patch objectForKey:@"hasCriteria"]) {
                
                mpInstaller = [[MPInstaller alloc] init];
                installResult = [mpInstaller installAppleSoftwareUpdate:[patch objectForKey:@"patch"]];
                mpInstaller = nil;
                
            } else {
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
				
				// If the Patch Installed Required a Reboot, flag it
                if ([[patch objectForKey:@"restart"] stringToBoolValue] == YES) {
					installedPatchesNeedingReboot++;
				}
                
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
                logit(lcl_vInfo,@"%@ was installed successfully.",[patch objectForKey:@"patch"]);
            }
            
            // Post the results to web service
            @try
            {
                MPWebServices *mpws = [[MPWebServices alloc] init];
                NSError *wsErr = nil;
                [mpws postPatchInstallResultsToWebService:[patch objectForKey:@"patch"] patchType:@"apple" error:&wsErr];
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
            logit(lcl_vInfo,@"Patch install completed.");
        } else {
            continue;
        }
	} //End patchesToInstallArray For Loop
	
	// Update GUI to reflect new installs
	[[NSFileManager defaultManager] createFileAtPath:[CLIENT_PATCH_STATUS_FILE stringByExpandingTildeInPath] 
											contents:[@"update" dataUsingEncoding:NSASCIIStringEncoding] 
										  attributes:nil];
	
	// Open the Reboot App
    mpInstaller = [[MPInstaller alloc] init];
	
	// If any patches that were installed needed a reboot
	if (installedPatchesNeedingReboot > 0) {
		if (hasConsoleUserLoggedIn == NO) {
			if ([_defaults objectForKey:@"Reboot"]) {
				if ([[_defaults objectForKey:@"Reboot"] isEqualTo:@"1"]) {
					logit(lcl_vInfo,@"Patches have been installed that require a reboot. Rebooting system now.");
					//int rb = 0;
					//rb = reboot(RB_AUTOBOOT);
					[NSTask launchedTaskWithLaunchPath:@"/bin/launchctl" arguments:@[@"reboot"]];
				} else {
					logit(lcl_vInfo,@"Patches have been installed that require a reboot. Please reboot the systems as soon as possible.");
					[self removeTaskRunning:kMPPatchUPDATE];
                    return;
				}
				
			}
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

	[self removeTaskRunning:kMPPatchUPDATE];
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
	qldebug(@"updatesArrayRaw: %@",updatesArrayRaw);
    // Filter on bundle ID
    NSPredicate *p = [NSPredicate predicateWithFormat:@"(bundleID == %@)", aPatchBundleID];
	updatesArray = [updatesArrayRaw filteredArrayUsingPredicate:p];
    qldebug(@"updatesArray: %@",updatesArray);
	
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
    for (i = 0; i < [updatesArray count]; i++) {
		// Create/Get Dictionary of Patch to install  
		patch = nil;
		patch = [NSDictionary dictionaryWithDictionary:[updatesArray objectAtIndex:i]];
        
		if (hasConsoleUserLoggedIn == YES) {
            // Check if patch needs a reboot
            if ([[patch objectForKey:@"restart"] stringToBoolValue] == YES) {
                logit(lcl_vInfo,@"%@(%@) requires a reboot, this patch will be installed on logout.",[patch objectForKey:@"patch"],[patch objectForKey:@"version"]);
                launchRebootWindow++;
                continue; 
            }
        }
        
        // Now proceed to the download and install			
        installResult = -1;
        
        if ([[patch objectForKey:@"type"] isEqualTo:@"Third"]) {
            logit(lcl_vInfo,@"Starting install for %@",[patch objectForKey:@"patch"]);
			[self postNotificationTo:@"MPPatchStatusNotification" info:[NSString stringWithFormat:@"Begin patching %@",[patch objectForKey:@"patch"]] isGlobal:YES];
			if (iLoadMode == YES) {
				printf("Begin: %s\n", [[patch objectForKey:@"patch"] cString]);
			}
            
            // Get all of the patches, main and subs
            // This is messed up, not sure why I have an array right within an array, needs to be fixed ...later :-)
            patchPatchesArray = [NSArray arrayWithArray:[[patch objectForKey:@"patches"] objectForKey:@"patches"]];
            logit(lcl_vDebug,@"Current patch has total patches associated with it %d", (int)([patchPatchesArray count]-1));
            
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
					//int rb = 0;
					//rb = reboot(RB_AUTOBOOT);
					[NSTask launchedTaskWithLaunchPath:@"/bin/launchctl" arguments:@[@"reboot"]];
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
    if (!_patchesArray) {
        return;
    }
	if ([_patchesArray count] <= 0) {
		// No Items in the Array, delete the file
		[fm removeItemAtPath:_approvedPatchesFile error:NULL];
        [fm removeItemAtPath:PATCHES_NEEDED_PLIST error:NULL];
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

- (BOOL)isTaskRunning:(NSString *)aTaskName
{
	if (forceRun == YES) {
		return NO;
	}
	
	if ([aTaskName isEqualToString:@".mpScanRunning"]) {
		if ([fm fileExistsAtPath:@"/tmp/.mpScanRunning"]) {
			return YES;
		}
	}
	if ([aTaskName isEqualToString:@".mpUpdateRunning"]) {
		if ([fm fileExistsAtPath:@"/tmp/.mpUpdateRunning"]) {
			return YES;
		}
	}
	if ([aTaskName isEqualToString:@".mpInventoryRunning"]) {
		if ([fm fileExistsAtPath:@"/tmp/.mpInventoryRunning"]) {
			return YES;
		}
	}
	if ([aTaskName isEqualToString:@".mpAVUpdateRunning"]) {
		if ([fm fileExistsAtPath:@"/tmp/.mpAVUpdateRunning"]) {
			return YES;
		}
	}
	
	return NO;
}

-(void)writeTaskRunning:(NSString *)aTaskName
{
	if (forceRun == NO) {
		NSString *_id = [[NSProcessInfo processInfo] globallyUniqueString];	
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

@end
