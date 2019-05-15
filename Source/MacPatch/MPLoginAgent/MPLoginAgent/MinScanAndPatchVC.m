//
//  MinScanAndPatchVC.m
//  MPLoginAgent
//
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

#import "MinScanAndPatchVC.h"
#import "MacPatch.h"
#include <unistd.h>
#include <sys/reboot.h>

#import <CoreServices/CoreServices.h>

#undef  ql_component
#define ql_component lcl_cMain

#define	BUNDLE_ID       @"gov.llnl.MPLoginAgent"

extern OSStatus MDSendAppleEventToSystemProcess(AEEventID eventToSend);

@interface MinScanAndPatchVC ()
{
    MPSettings *settings;
}

// Main
- (void)scanAndPatch;
- (void)scanAndPatchThread;
- (void)countDownToClose;
- (void)rebootOrLogout:(int)action;
- (void)toggleStatusProgress;

// Patch Status File
- (BOOL)isRecentPatchStatusFile;
- (void)updateNeededPatchesFile:(NSDictionary *)aPatch;
- (int)createPatchStatusFile:(NSArray *)patches;
- (void)clearPatchStatusFile;

// Misc
- (void)progress:(NSString *)text,...;

// Web Service
- (void)postInstallToWebService:(NSString *)aPatch type:(NSString *)aType;
@end

@implementation MinScanAndPatchVC

@synthesize taskThread;
@synthesize killTaskThread;
@synthesize cancelTask;

- (void)awakeFromNib
{
    static BOOL alreadyInit = NO;
    
    if (!alreadyInit)
    {
        alreadyInit = YES;
        
        fm = [NSFileManager defaultManager];
        settings = [MPSettings sharedInstance];
        cancelTask = FALSE;
        
        [self->progressBar  setUsesThreadedAnimation: YES];
        
        dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0);
        dispatch_queue_t main = dispatch_get_main_queue();
        
        dispatch_async(queue, ^{
            dispatch_async(main, ^{
                [self scanAndPatch];
            });
        });
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do view setup here.
}

#pragma mark - Main

- (void)scanAndPatch
{
    [progressText setHidden:NO];
    [progressText setStringValue:@""];
    [progressCountText setHidden:NO];
    [progressCountText setStringValue:@""];
    [self->progressBar  setHidden:YES];
    [self->progressBar  stopAnimation:nil];
    
    killTaskThread = NO;
    
    if (taskThread != nil) {
        taskThread = nil;
    }
    
    taskThread = [[NSThread alloc] initWithTarget:self selector:@selector(scanAndPatchThread) object:nil];
    [taskThread start];
}

- (void)scanAndPatchThread
{
	@autoreleasepool
	{
		[self toggleStatusProgress];
		[NSThread sleepForTimeInterval:2];
		[NSApp activateIgnoringOtherApps:YES];
		
		NSArray *approvedUpdates = [NSArray array];
	
		// Scan for Apple Patches
		[self progress:@"Scanning for patches..."];
		if (cancelTask) [self _stopThread];
		MPPatching *patching = [MPPatching new];
		patching.delegate = self;
		
		// Scan host for patches
		approvedUpdates = [patching scanForPatchesUsingTypeFilter:kAllPatches forceRun:YES];
		qlinfo(@"approvedUpdates: %@",approvedUpdates);
		if (approvedUpdates.count <= 0)
		{
			[self progress:@"No patches found..."];
			[self toggleStatusProgress];
			[self rebootOrLogout:1]; // Exit app, no reboot.
			return;
		}
		
		// Sort approved pacthes by install weight
		NSMutableArray *approvedUpdatesArray = [[NSMutableArray alloc] initWithArray:approvedUpdates];
		NSSortDescriptor *desc = [NSSortDescriptor sortDescriptorWithKey:@"patch_install_weight" ascending:YES];
		[approvedUpdatesArray sortUsingDescriptors:[NSArray arrayWithObject:desc]];
		approvedUpdates = [approvedUpdatesArray copy];
		
		// Install required patches
		dispatch_async(dispatch_get_main_queue(), ^(void)
		{
			[self->progressBar  setIndeterminate:NO];
			[self->progressBar  setDoubleValue:1.0];
			[self->progressBar  setMaxValue:approvedUpdates.count+1];
		});
		
		// Begin Patching
		__block NSMutableArray *failedPatches = [[NSMutableArray alloc] init];
		
		
		for (NSDictionary *patch in approvedUpdates)
		{
			if (cancelTask) [self _stopThread];
			
			qlinfo(@"Installing: %@",patch[@"patch"]);
			qldebug(@"Patch: %@",patch);
			[self progress:@"Installing %@",patch[@"patch"]];
			MPPatchContentType pType = kCustomPatches;
			if ([patch[@"type"] isEqualToString:@"Apple"]) {
				pType = kApplePatches;
			}
			
			int install_result = 9999;
			NSDictionary *res = [patching installPatchUsingTypeFilter:patch typeFilter:pType];
			if (res[@"patchInstallErrors"])
			{
				qldebug(@"patchResult[patchInstallErrors] = %d",[res[@"patchInstallErrors"] intValue]);
				if ([res[@"patchInstallErrors"] intValue] >= 1)
				{
					qlerror(@"Error installing %@",patch[@"patch"]);
					install_result = 1;
				} else {
					install_result = 0;
				}
			}
			
			if (install_result != 0) {
				qlerror(@"Patch %@ failed to install.",patch[@"patch"]);
				[failedPatches addObject:patch];
			}
			
			dispatch_async(dispatch_get_main_queue(), ^(void){
				[self->progressBar setDoubleValue:([self->progressBar doubleValue]+1)];
			});
			
		}
		
		[self progress:@"Complete"];
		[NSThread sleepForTimeInterval:1.0];
		
		qlinfo(@"Patches have been installed, system will now reboot.");
		[self countDownToClose];
	}
}

- (void)countDownToClose
{
    for (int i = 0; i < 5;i++)
    {
        // Message that window is closing
        [self progress:@"Rebooting system in %d seconds...",(5-i)];
        sleep(1);
    }
    
    [self progress:@"Rebooting System Please Be Patient"];
    [self rebootOrLogout:0];
}

- (void)countDownShowRebootButton
{
	@autoreleasepool
	{
		for (int i = 0; i < 300;i++)
		{
			sleep(1);
		}
		dispatch_async(dispatch_get_global_queue(0, 0), ^{
			dispatch_async(dispatch_get_main_queue(), ^{
				self->cancelButton.title = @"Reboot";
				self->cancelButton.hidden = NO;
			});
		});
	}
}

- (void)rebootOrLogout:(int)action
{
	switch ( action )
	{
		case 0:
			[NSTask launchedTaskWithLaunchPath:@"/bin/launchctl" arguments:@[@"reboot"]];
			qlinfo(@"MPAuthPlugin issued a launchctl reboot.");
			[NSThread detachNewThreadSelector:@selector(countDownShowRebootButton) toTarget:self withObject:nil];
			break;
		case 1:
			// just return to loginwindow
			exit(0);
			break;
		default:
			// Code
			exit(0);
			break;
	}
}

- (void)toggleStatusProgress
{
    if ([self->progressBar  isHidden]) {
        
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [self->progressBar  setUsesThreadedAnimation:YES];
                [self->progressBar  setHidden:NO];
                [self->progressBar  startAnimation:nil];
            });
        });
        
    } else {
        [self->progressBar  setHidden:YES];
        [self->progressBar  stopAnimation:nil];
    }
}

- (IBAction)cancelOperation:(id)sender
{
	if ([cancelButton.title isEqualToString:@"Reboot"])
	{
		int rb = 0;
		qlerror(@"User forced a reboot. Some items may not have gotten installed.");
		rb = reboot(RB_AUTOBOOT);
	}
}

- (void)_stopThread
{
    @autoreleasepool
    {
        MDSendAppleEventToSystemProcess(kAERestart);
    }
}

OSStatus MDSendAppleEventToSystemProcess(AEEventID eventToSendID)
{
    qlinfo(@"MDSendAppleEventToSystemProcess called");
    
    AEAddressDesc targetDesc;
    static const ProcessSerialNumber kPSNOfSystemProcess = {0, kSystemProcess };
    AppleEvent eventReply = {typeNull, NULL};
    AppleEvent eventToSend = {typeNull, NULL};
    
    OSStatus status = AECreateDesc(typeProcessSerialNumber,
                                   &kPSNOfSystemProcess, sizeof(kPSNOfSystemProcess), &targetDesc);
    
    if (status != noErr) return status;
    
    status = AECreateAppleEvent(kCoreEventClass, eventToSendID,
                                &targetDesc, kAutoGenerateReturnID, kAnyTransactionID, &eventToSend);
    
    AEDisposeDesc(&targetDesc);
    
    if (status != noErr) return status;
    
    status = AESendMessage(&eventToSend, &eventReply,
                           kAENormalPriority, kAEDefaultTimeout);
    
    AEDisposeDesc(&eventToSend);
    if (status != noErr) return status;
    AEDisposeDesc(&eventReply);
    return status;
}

#pragma mark - Scanning
/*
- (NSArray *)scanForAppleUpdates:(NSError **)err
{
    qlinfo(@"Scanning for Apple software updates.");
    
    NSArray *results = nil;
    results = [mpScanner scanForAppleUpdates];
    return results;
}

- (NSArray *)scanForCustomUpdates:(NSError **)err
{
    NSArray *results = nil;
    results = [mpScanner scanForCustomUpdates];
    return results;
}

- (NSArray *)filterFoundPatches:(NSDictionary *)patchGroupPatches applePatches:(NSArray *)apple customePatches:(NSArray *)custom
{
    NSMutableArray *approvedUpdatesArray = [[NSMutableArray alloc] init];
    NSMutableDictionary *tmpPatchDict;
    NSDictionary *customPatch;
    NSDictionary *approvedPatch;
    
    NSArray *approvedApplePatches;
    NSArray *approvedCustomPatches;
    
    // Sort Apple & Custom PatchGroup Patches
    approvedApplePatches = [patchGroupPatches objectForKey:@"AppleUpdates"];
    approvedCustomPatches = [patchGroupPatches objectForKey:@"CustomUpdates"];
    
    
    // Filter Apple Patches
    if (!apple) {
        qlinfo(@"The scan results for ASUS scan were nil.");
    } else {
        // If no items in array, lets bail...
        if ([apple count] == 0 ) {
            qlinfo(@"No Apple updates found.");
            sleep(1);
        } else {
            // We have Apple patches, now add them to the array of approved patches
            
            // If no items in array, lets bail...
            if ([approvedApplePatches count] == 0 ) {
                qlinfo(@"No Patch Group patches found.");
                qlinfo(@"No apple updates found for \"%@\" patch group.",settings.agent.patchGroup);
            } else {
                // Build Approved Patches
                qlinfo(@"Building approved apple patch list...");
				NSDictionary *_applePatch;
				NSDictionary *_applePatchApproved;
				
				for (int i=0; i<[apple count]; i++)
				{
					_applePatch = [apple objectAtIndex:i];
					
					for (int x=0;x < [approvedApplePatches count]; x++)
					{
						_applePatchApproved = [approvedApplePatches objectAtIndex:x];
						
						if ([_applePatchApproved[@"name"] isEqualTo:_applePatch[@"patch"]])
						{
							if ([_applePatchApproved objectForKey:@"user_install"])
							{
								if ([[_applePatchApproved objectForKey:@"user_install"] intValue] == 1)
								{
									qlwarning(@"Patch %@ is approved. Will not install due to being a user required install patch.",_applePatch[@"patch"]);
									break;
								}
							}
							
							qlinfo(@"Patch %@ approved for update.",_applePatchApproved[@"name"]);
							
							tmpPatchDict = [[NSMutableDictionary alloc] init];
							[tmpPatchDict setObject:[NSNumber numberWithBool:YES] forKey:@"selected"];
							[tmpPatchDict setObject:_applePatch[@"patch"] forKey:@"patch"];
							[tmpPatchDict setObject:_applePatch[@"size"] forKey:@"size"];
							[tmpPatchDict setObject:_applePatch[@"description"] forKey:@"description"];
							[tmpPatchDict setObject:_applePatch[@"restart"] forKey:@"restart"];
							[tmpPatchDict setObject:_applePatch[@"version"] forKey:@"version"];
							[tmpPatchDict setObject:_applePatchApproved[@"hasCriteria"] forKey:@"hasCriteria"];
							
							if ([_applePatchApproved[@"hasCriteria"] boolValue] == YES)
							{
								if (_applePatchApproved[@"criteria_pre"] && [_applePatchApproved[@"criteria_pre"] count] > 0)
								{
									[tmpPatchDict setObject:_applePatchApproved[@"criteria_pre"] forKey:@"criteria_pre"];
								}
								if (_applePatchApproved[@"criteria_post"] && [_applePatchApproved[@"criteria_post"] count] > 0)
								{
									[tmpPatchDict setObject:_applePatchApproved[@"criteria_post"] forKey:@"criteria_post"];
								}
							}
							
							[tmpPatchDict setObject:@"Apple" forKey:@"type"];
							[tmpPatchDict setObject:[[approvedApplePatches objectAtIndex:i] objectForKey:@"patch_install_weight"] forKey:@"patch_install_weight"];
							
							[approvedUpdatesArray addObject:tmpPatchDict];
							qldebug(@"Apple Patch Dictionary Added: %@",tmpPatchDict);
							break;
						}
					}
				}
            }
        }
    }
	
    // Filter Custom Patches
    qlinfo(@"Building approved custom patch list...");
    for (int i=0; i<[custom count]; i++) {
        customPatch	= [custom objectAtIndex:i];
        for (int x=0;x < [approvedCustomPatches count]; x++) {
            approvedPatch = [approvedCustomPatches objectAtIndex:x];
            if ([[customPatch objectForKey:@"patch_id"] isEqualTo:[approvedPatch objectForKey:@"patch_id"]])
            {
                qlinfo(@"Patch %@ approved for update.",[customPatch objectForKey:@"description"]);
				
                tmpPatchDict = [[NSMutableDictionary alloc] init];
                [tmpPatchDict setObject:[NSNumber numberWithBool:YES] forKey:@"selected"];
                [tmpPatchDict setObject:[customPatch objectForKey:@"patch"] forKey:@"patch"];
                for (id item in [approvedPatch objectForKey:@"patches"]) {
                    if ([[item objectForKey:@"type"] isEqualTo:@"1"]) {
                        [tmpPatchDict setObject:[NSString stringWithFormat:@"%@K",[item objectForKey:@"size"]] forKey:@"size"];
                        break;
                    }
                }
                [tmpPatchDict setObject:[customPatch objectForKey:@"description"] forKey:@"description"];
                [tmpPatchDict setObject:[customPatch objectForKey:@"restart"] forKey:@"restart"];
                [tmpPatchDict setObject:[customPatch objectForKey:@"version"] forKey:@"version"];
                [tmpPatchDict setObject:approvedPatch forKey:@"patches"];
                [tmpPatchDict setObject:[customPatch objectForKey:@"patch_id"] forKey:@"patch_id"];
                
                [tmpPatchDict setObject:@"Third" forKey:@"type"];
                [tmpPatchDict setObject:[customPatch objectForKey:@"bundleID"] forKey:@"bundleID"];
                [tmpPatchDict setObject:[approvedPatch objectForKey:@"patch_install_weight"] forKey:@"patch_install_weight"];
                
                [approvedUpdatesArray addObject:tmpPatchDict];
                qldebug(@"Custom Patch Dictionary Added: %@",tmpPatchDict);
                break;
            }
        }
    }
    
    // Sort Array
    NSSortDescriptor *desc = [NSSortDescriptor sortDescriptorWithKey:@"patch_install_weight" ascending:YES];
    [approvedUpdatesArray sortUsingDescriptors:[NSArray arrayWithObject:desc]];
    return (NSArray *)approvedUpdatesArray;
}

- (NSDictionary *)patchGroupPatches
{
    NSError       *error = nil;
    NSDictionary  *patchGroupPatches = nil;
    MPRESTfull    *rest = [[MPRESTfull alloc] init];
    
    BOOL           useLocalPatchesFile = NO;
    
    // Get Approved Patch group patches
    patchGroupPatches = [rest getApprovedPatchesForClient:&error];
    if (error)
    {
        qlerror(@"There was a issue getting the approved patches for the patch group, scan will exit.");
        qlerror(@"%@",error.localizedDescription);
        return nil;
    }
    
 
    return patchGroupPatches;
}
*/
#pragma mark - Installing
/*
- (int)installPatch:(NSDictionary *)patch
{
    int installResult = -1;

    qlinfo(@"Preparing to install %@(%@)",[patch objectForKey:@"patch"],[patch objectForKey:@"version"]);
    qldebug(@"Patch to process: %@",patch);
    
    if ([[patch objectForKey:@"type"] isEqualTo:@"Third"])
    {
        installResult = [self installCustomPatch:patch];
        if (installResult == 0)
        {
            // Post the results to web service
            @try {
                [self postInstallToWebService:[patch objectForKey:@"patch_id"] type:@"third"];
            } @catch (NSException *e) {
                qlerror(@"%@", e);
            }
        } else {
            // Post failed patch
        }
        
        return installResult;
        
    }
    else if ([[patch objectForKey:@"type"] isEqualTo:@"Apple"])
    {
        installResult = [self installApplePatch:patch];
        if (installResult == 0)
        {
            // Post the results to web service
            @try {
                [self postInstallToWebService:[patch objectForKey:@"patch"] type:@"apple"];
            } @catch (NSException *e) {
                qlerror(@"%@", e);
            }
        } else {
            // Post failed patch
        }
        
        return installResult;
    }
    
    qlerror(@"Unknow patch type (%@), no install occured.",[patch objectForKey:@"type"]);
    return 1;
}

- (int)installApplePatch:(NSDictionary *)patch
{
	MPPatching *patching = [MPPatching new];
	NSDictionary *res = [patching installPatchUsingTypeFilter:patch typeFilter:kApplePatches];
	qlinfo(@"installApplePatch[Result]: %@",res);
	return 0;
}

- (int)installCustomPatch:(NSDictionary *)patch
{
	MPPatching *patching = [MPPatching new];
	NSDictionary *res = [patching installPatchUsingTypeFilter:patch typeFilter:kCustomPatches];
	qlinfo(@"installApplePatch[Result]: %@",res);
	return 0;
}
- (int)installPKG:(NSString *)aPkgPath target:(NSString *)aTarget env:(NSString *)aEnv
{
    int result = 99;
    
    InstallPackage *ipkg = [[InstallPackage alloc] init];
    result = [ipkg installPkgToRoot:aPkgPath env:aEnv];
    
    return result;
}
*/

#pragma mark - Status File

- (BOOL)isRecentPatchStatusFile
{
    const int k30Minutes = 1800;
    if (![fm fileExistsAtPath:PATCHES_NEEDED_PLIST]) {
        return FALSE;
    }
    
    NSError *error   = nil;
    NSURL   *fileUrl = [NSURL fileURLWithPath:PATCHES_NEEDED_PLIST];
    NSDate  *fileDate;
    [fileUrl getResourceValue:&fileDate forKey:NSURLContentModificationDateKey error:&error];
    if (!error)
    {
        NSDate *now = [NSDate date];
        NSTimeInterval delta = [fileDate timeIntervalSinceDate:now] * -1.0;
        if (delta < k30Minutes) {
            return TRUE;
        }
    }
    
    // Default to old file
    return FALSE;
}

- (void)updateNeededPatchesFile:(NSDictionary *)aPatch
{
    NSMutableArray *patchesNew;
    NSArray *patches;
    if ([fm fileExistsAtPath:PATCHES_NEEDED_PLIST]) {
        patches = [NSArray arrayWithArray:[NSKeyedUnarchiver unarchiveObjectWithFile:PATCHES_NEEDED_PLIST]];
        [self clearPatchStatusFile];
    } else {
        qlerror(@"Unable to update %@, file not found.",PATCHES_NEEDED_PLIST);
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
        [self createPatchStatusFile:(NSArray *)patchesNew];
    } else {
        [self clearPatchStatusFile];
    }
}

- (int)createPatchStatusFile:(NSArray *)patches
{
    @try
    {
        if ([fm fileExistsAtPath:PATCHES_NEEDED_PLIST]) {
            if ([fm isDeletableFileAtPath:PATCHES_NEEDED_PLIST]) {
                [fm removeItemAtPath:PATCHES_NEEDED_PLIST error:NULL];
            } else {
                qlerror(@"Unable to remove %@ due to permissions.",PATCHES_NEEDED_PLIST);
            }
        }
        
        BOOL result = [NSKeyedArchiver archiveRootObject:patches toFile:PATCHES_NEEDED_PLIST];
        if (!result) {
            logit(lcl_vError,@"Error writing array to %@.",PATCHES_NEEDED_PLIST);
            return 1;
        }
        return 0;
    }
    @catch (NSException *exception) {
        logit(lcl_vError,@"Error writing data to file(%@)\n%@.",PATCHES_NEEDED_PLIST,exception);
        return 1;
    }
    return 1;
}

- (void)clearPatchStatusFile
{
    [NSKeyedArchiver archiveRootObject:[NSArray array] toFile:PATCHES_NEEDED_PLIST];
    return;
}

#pragma mark - Delegates
/*
- (void)scanData:(MPScanner *)scanner data:(NSString *)aData
{
    progressText.stringValue = aData;
}

- (void)installData:(InstallAppleUpdate *)installUpdate data:(NSString *)aData type:(NSUInteger)dataType
{
    qlinfo(@"%@",aData);
}

- (void)patchScan:(MPPatchScan *)patchScan didReciveStatusData:(NSString *)data
{
    qldebug(@"[patchScan:didReciveStatusData]: %@",data);
}
*/

- (void)patchingProgress:(MPPatching *)mpPatching progress:(NSString *)progressStr
{
	[self progress:progressStr];
}

#pragma mark - Misc

- (void)progress:(NSString *)text,...
{
	va_list va;
	va_start(va, text);
	NSString *string = [[NSString alloc] initWithFormat:text arguments:va];
	va_end(va);
	
    dispatch_async(dispatch_get_main_queue(), ^(void){
		[self->progressText setStringValue:string];
    });
}

#pragma mark - Web Services

- (void)postInstallToWebService:(NSString *)aPatch type:(NSString *)aType
{
    BOOL result = NO;
    NSError *wsErr = nil;
    
    MPRESTfull *rest = [[MPRESTfull alloc] init];
    result = [rest postPatchInstallResults:aPatch type:aType error:&wsErr];
    if (wsErr) {
        qlerror(@"%@",wsErr.localizedDescription);
    } else {
        if (result == TRUE) {
            qlinfo(@"Patch (%@) install result was posted to webservice.",aPatch);
        } else {
            qlerror(@"Patch (%@) install result was not posted to webservice.",aPatch);
        }
    }
    return;
}
@end
