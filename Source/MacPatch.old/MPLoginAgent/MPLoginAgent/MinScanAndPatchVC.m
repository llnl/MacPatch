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
#import "MPScanner.h"
#import "InstallPackage.h"
#import "InstallAppleUpdate.h"
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

// Scanning
- (NSArray *)scanForAppleUpdates:(NSError **)err;
- (NSArray *)scanForCustomUpdates:(NSError **)err;
- (NSArray *)filterFoundPatches:(NSDictionary *)patchGroupPatches applePatches:(NSArray *)apple customePatches:(NSArray *)custom;
- (NSDictionary *)patchGroupPatches;

// Installing
- (int)installPatch:(NSDictionary *)patch;
- (int)installApplePatch:(NSDictionary *)patch error:(NSError **)error;
- (int)installAppleSoftwareUpdate:(NSString *)appleUpdate;
- (int)installCustomPatch:(NSDictionary *)patch error:(NSError **)error;
- (int)installPKG:(NSString *)aPkgPath target:(NSString *)aTarget env:(NSString *)aEnv;
- (int)runScript:(NSString *)aScript;

// Patch Status File
- (BOOL)isRecentPatchStatusFile;
- (void)updateNeededPatchesFile:(NSDictionary *)aPatch;
- (int)createPatchStatusFile:(NSArray *)patches;
- (void)clearPatchStatusFile;

// Misc
- (void)progress:(NSString *)text;

// Web Service
- (void)postInstallToWebService:(NSString *)aPatch type:(NSString *)aType;
@end

@implementation MinScanAndPatchVC

@synthesize progressCount;
@synthesize progressCountTotal;
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
        mpScanner = [[MPScanner alloc] init];
        mpScanner.delegate = self;
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
    progressCount = 0;
    progressCountTotal = 0;

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
        
        NSError *error = nil;
        NSArray *appleUpdates = nil;
        NSArray *customUpdates = nil;
        NSArray *approvedUpdates = [NSArray array];
        
        if ([self isRecentPatchStatusFile])
        {
            qlinfo(@"Using patch status file for updates.");
            approvedUpdates = [NSArray arrayWithArray:[NSKeyedUnarchiver unarchiveObjectWithFile:PATCHES_NEEDED_PLIST]];
        }
        else
        {
            // Scan for Apple Patches
            [self progress:@"Scanning for Apple Updates"];
            if (cancelTask) [self _stopThread];
            
            error = nil;
            appleUpdates = [self scanForAppleUpdates:&error];
            if (error) {
                qlerror(@"%@",error.localizedDescription);
            }
            qldebug(@"Apple Updates: %@",appleUpdates);
            
            // Scan for Custome Patches
            [self progress:@"Scanning for Custom Updates"];
            if (cancelTask) [self _stopThread];
            
            error = nil;
            customUpdates = [self scanForCustomUpdates:&error];
            if (error) {
                qlerror(@"%@",error.localizedDescription);
            }
            
            qldebug(@"Custom Updates: %@",customUpdates);
            [self progress:@"Compiling approved patches from scan list"];
            if (cancelTask) [self _stopThread];
            approvedUpdates = [self filterFoundPatches:[self patchGroupPatches]
                                          applePatches:appleUpdates
                                        customePatches:customUpdates];
            
            [self createPatchStatusFile:approvedUpdates];
            if (cancelTask) [self _stopThread];
        }
        
        qlinfo(@"Approved Updates: %@",approvedUpdates);
        progressCountTotal = (int)[approvedUpdates count];
        
        // If we have no patches, close out.
        if (progressCountTotal <= 0)
        {
            [self toggleStatusProgress];
            [self rebootOrLogout:1]; // Exit app, no reboot.
            return;
        }
        
        dispatch_async(dispatch_get_main_queue(), ^(void){
            [self->progressBar  setIndeterminate:NO];
            [self->progressBar  setDoubleValue:1.0];
			[self->progressBar  setMaxValue:self->progressCountTotal+1];
        });

        // Begin Patching
        __block NSDictionary *patch;
        __block NSMutableArray *failedPatches = [[NSMutableArray alloc] init];
        
        int install_result = 0;
        for (int i = 0; i < [approvedUpdates count]; i++)
        {
            if (cancelTask) [self _stopThread];
            
            // Create/Get Dictionary of Patch to install
            patch = nil;
            patch = [NSDictionary dictionaryWithDictionary:[approvedUpdates objectAtIndex:i]];
            
            qlinfo(@"Installing: %@",[patch objectForKey:@"patch"]);
            qldebug(@"Patch: %@",patch);
            [self progress:[NSString stringWithFormat:@"Installing %@",[patch objectForKey:@"patch"]]];
            
            install_result = [self installPatch:patch];
            if (install_result != 0) {
                qlerror(@"Patch %@ failed to install.",[patch objectForKey:@"patch"]);
                [failedPatches addObject:patch];
            }
            
            // Install was successful, now patch from status file
            [self updateNeededPatchesFile:patch];
            
            dispatch_async(dispatch_get_main_queue(), ^(void){
                [self->progressBar  setDoubleValue:([self->progressBar  doubleValue]+1)];
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
        [self progress:[NSString stringWithFormat:@"Rebooting system in %d seconds...",(5-i)]];
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
	/*
	 [self progress:@"Cancelling, waiting for current request to finish..."];
	 dispatch_async(dispatch_get_main_queue(), ^(void)
	 {
	 cancelButton.enabled = FALSE;
	 self.cancelTask = TRUE;
	 });
	 */
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

- (NSArray *)scanForAppleUpdates:(NSError **)err
{
    logit(lcl_vInfo,@"Scanning for Apple software updates.");
    
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
    
    /* CEH - Look at re-implementing local cache of patch group patches
     
    NSString      *patchGroupRevLocal = [MPClientInfo patchGroupRev];
    
    if (![patchGroupRevLocal isEqualToString:@"-1"]) {
        NSString *patchGroupRevRemote = [mpws getPatchGroupContentRev:&error];
        if (!error) {
            if ([patchGroupRevLocal isEqualToString:patchGroupRevRemote]) {
                useLocalPatchesFile = YES;
                NSString *pGroup = [[mpDefauts defaults] objectForKey:@"PatchGroup"];
                patchGroupPatches = [[[NSDictionary dictionaryWithContentsOfFile:PATCH_GROUP_PATCHES_PLIST] objectForKey:pGroup] objectForKey:@"data"];
                if (!patchGroupPatches) {
                    logit(lcl_vError,@"Unable to get data from cached patch group data file. Will download new one.");
                    useLocalPatchesFile = NO;
                }
            }
        }
    }
    
    if (!useLocalPatchesFile) {
        error = nil;
        patchGroupPatches = [mpws getPatchGroupContent:&error];
        if (error) {
            qlerror(@"There was a issue getting the approved patches for the patch group, scan will exit.");
            return nil;
        }
    }
    
    if (!patchGroupPatches) {
        logit(lcl_vError,@"There was a issue getting the approved patches for the patch group, scan will exit.");
        return nil;
    }
    */
    return patchGroupPatches;
}

#pragma mark - Installing

- (int)installPatch:(NSDictionary *)patch
{
    int installResult = -1;

    qlinfo(@"Preparing to install %@(%@)",[patch objectForKey:@"patch"],[patch objectForKey:@"version"]);
    qldebug(@"Patch to process: %@",patch);
    
    if ([[patch objectForKey:@"type"] isEqualTo:@"Third"])
    {
        installResult = [self installCustomPatch:patch error:NULL];
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
        installResult = [self installApplePatch:patch error:NULL];
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

// Processed apple patch dictionary for pre & post criteria
// Insgtall of apple patch sent to installAppleSoftwareUpdate()
- (int)installApplePatch:(NSDictionary *)patch error:(NSError **)error
{
    BOOL hasCriteria = [[patch objectForKey:@"hasCriteria"] boolValue] ? : NO;
    int installResult = -1;
    int pre_criteria_res, post_criteria_res;
    NSDictionary *criteriaDictPre, *criteriaDictPost;
    NSString *scriptText;
    
    // Process Apple Type Patches
    [self progress:[NSString stringWithFormat:@"Starting install for %@",[patch objectForKey:@"patch"]]];
    
    // Process Pre-Criteria if criteria is added
    if (hasCriteria)
    {
        
        if ([patch objectForKey:@"criteria_pre"])
        {
            qlinfo(@"Processing pre-install criteria.");
            for (int i=0; i<[[patch objectForKey:@"criteria_pre"] count]; i++)
            {
                criteriaDictPre = [[patch objectForKey:@"criteria_pre"] objectAtIndex:i];
                scriptText = [[criteriaDictPre objectForKey:@"data"] decodeBase64AsString];
                
                [self progress:[NSString stringWithFormat:@"Run pre-install criteria."]];
                pre_criteria_res = -1;
                pre_criteria_res = [self runScript:scriptText];
                if (pre_criteria_res != 0) {
                    qlerror(@"Pre-install script returned false for %@. No install will occur.",[patch objectForKey:@"patch"]);
                    return 1;
                } else {
                    qlinfo(@"Pre-install script returned true.");
                }
                criteriaDictPre = nil;
            }
        }
    }
    
    // Install Apple Patch
    [self progress:[NSString stringWithFormat:@"Installing %@",[patch objectForKey:@"patch"]]];
    installResult = [self installAppleSoftwareUpdate:[patch objectForKey:@"patch"]];
    
    // If Install returned anything but 0, the dont run post criteria
    if (installResult != 0) {
        qlerror(@"The install for %@ returned an error.",[patch objectForKey:@"patch"]);
        return 1;
    } else {
        qlinfo(@"The install for %@ was successful.",[patch objectForKey:@"patch"]);
    }
    
    // Process Post-Criteria if criteria is added
    if (hasCriteria)
    {
        if ([patch objectForKey:@"criteria_post"])
        {
            qlinfo(@"Processing post-install criteria.");
            for (int x=0; x < [[patch objectForKey:@"criteria_post"] count]; x++)
            {
                criteriaDictPost = [[patch objectForKey:@"criteria_post"] objectAtIndex:x];
                scriptText = [[criteriaDictPost objectForKey:@"data"] decodeBase64AsString];
                
                [self progress:[NSString stringWithFormat:@"Run post-install criteria."]];
                post_criteria_res = -1;
                post_criteria_res = [self runScript:scriptText];
                if (post_criteria_res != 0) {
                    qlerror(@"Pre-install script returned false for %@. No install will occur.",[patch objectForKey:@"patch"]);
                    return 1;
                } else {
                    qlinfo(@"Post-install script returned true.");
                }
                criteriaDictPost = nil;
            }
        }
    }
    
    return 0;
}

- (int)installAppleSoftwareUpdate:(NSString *)appleUpdate
{
    int result = -1;
    @try {
        InstallAppleUpdate *installUpdate = [[InstallAppleUpdate alloc] init];
        installUpdate.delegate = self;
        result = [installUpdate installAppleSoftwareUpdate:appleUpdate];
    }
    @catch (NSException *e) {
        qlerror(@"runTaskUsingHelper [ASUS Install] error: %@", e);
        result = 1;
    }
    return result;
}

- (int)installCustomPatch:(NSDictionary *)patch error:(NSError **)error
{
    NSArray *patchPatchesArray;
    MPAsus *mpAsus = [[MPAsus alloc] init];
    
    [self progress:[NSString stringWithFormat:@"Starting install for %@",[patch objectForKey:@"patch"]]];
    
    // Get all of the patches, main and subs
    patchPatchesArray = [NSArray arrayWithArray:[[patch objectForKey:@"patches"] objectForKey:@"patches"]];
    qldebug(@"Current patch has total patches associated with it %d", (int)([patchPatchesArray count]-1));
    
    NSError      *err = nil;
    NSString     *downloadURL;
    NSDictionary *patchDict;
    NSString     *dlPatchLoc; //Download location Path
    int          preInstallRes, postInstallRes;
    int          installResult;
    int          patchInstallsFound = 0;
    int          patchInstallCount = 0;
    
    // Staging
    NSString *stageDir;
    
    for (int i = 0; i < [patchPatchesArray count]; i++)
    {
        // Make sure we only process the dictionaries in the NSArray
        if ([[patchPatchesArray objectAtIndex:i] isKindOfClass:[NSDictionary class]])
        {
            patchDict = [NSDictionary dictionaryWithDictionary:[patchPatchesArray objectAtIndex:i]];
            patchInstallsFound++;
        } else {
            qlinfo(@"Object found was not of dictionary type; could be a problem. %@",[patchPatchesArray objectAtIndex:i]);
            continue;
        }
        
        // We have a currPatchToInstallDict to work with
        qlinfo(@"Start install for patch %@ from %@",[patchDict objectForKey:@"url"],[patch objectForKey:@"patch"]);
        
        BOOL usingStagedPatch = NO;
        BOOL downloadPatch = YES;
        MPCrypto *mpCrypto = [[MPCrypto alloc] init];
        
        // -------------------------------------------
        // First we need to download the update
        // -------------------------------------------
        @try
        {
            // -------------------------------------------
            // Check to see if the patch has been staged
            // -------------------------------------------
            stageDir = [NSString stringWithFormat:@"%@/Data/.stage/%@",MP_ROOT_CLIENT,[patch objectForKey:@"patch_id"]];
            if ([fm fileExistsAtPath:[stageDir stringByAppendingPathComponent:[[patchDict objectForKey:@"url"] lastPathComponent]]])
            {
                dlPatchLoc = [stageDir stringByAppendingPathComponent:[[patchDict objectForKey:@"url"] lastPathComponent]];
                if ([[[patchDict objectForKey:@"hash"] uppercaseString] isEqualTo:[[mpCrypto md5HashForFile:dlPatchLoc] uppercaseString]])
                {
                    qlinfo(@"The staged file passed the file hash validation.");
                    usingStagedPatch = YES;
                    downloadPatch = NO;
                } else {
                    //[spStatusText setStringValue:[NSString stringWithFormat:@"The staged file did not pass the file hash validation."]];
                    //[spStatusText display];
                    logit(lcl_vError,@"The staged file did not pass the file hash validation.");
                }
            }
            
            // -------------------------------------------
            // Check to see if we need to download the patch
            // -------------------------------------------
            if (downloadPatch)
            {
                // Download the patch
                logit(lcl_vInfo,@"Start download for patch from %@",[patchDict objectForKey:@"url"]);
                [self progress:[NSString stringWithFormat:@"Downloading %@",[[patchDict objectForKey:@"url"] lastPathComponent]]];
                
                //Pre Proxy Config
                downloadURL = [NSString stringWithFormat:@"/mp-content%@",[patchDict objectForKey:@"url"]];
                logit(lcl_vInfo,@"Download patch from: %@",downloadURL);
                err = nil;
                dlPatchLoc = [mpAsus downloadUpdate:downloadURL error:&err];
                if (err) {
                    logit(lcl_vError,@"Error downloading a patch, skipping %@. Err Message: %@",[patch objectForKey:@"patch"],[err localizedDescription]);
                    [self progress:[NSString stringWithFormat:@"Error downloading a patch, skipping %@.",[patch objectForKey:@"patch"]]];
                    break;
                }
                
                [self progress:[NSString stringWithFormat:@"Patch download completed."]];
                logit(lcl_vInfo,@"File downloaded to %@",dlPatchLoc);
                
                
                // -------------------------------------------
                // Validate hash, before install
                // -------------------------------------------
                [self progress:[NSString stringWithFormat:@"Validating downloaded patch %@.",[patch objectForKey:@"patch"]]];
                
                NSString *fileHash = [mpCrypto md5HashForFile:dlPatchLoc];
                logit(lcl_vInfo,@"Downloaded file hash: %@ (%@)",fileHash,[patchDict objectForKey:@"hash"]);
                if ([[[patchDict objectForKey:@"hash"] uppercaseString] isEqualTo:[fileHash uppercaseString]] == NO) {
                    [self progress:[NSString stringWithFormat:@"The downloaded file did not pass the file hash validation. No install will occur."]];
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
        // Download the update
        /*
        @try
        {
            qlinfo(@"Start download for patch from %@",[patchDict objectForKey:@"url"]);
            [self progress:[NSString stringWithFormat:@"Downloading %@",[[patchDict objectForKey:@"url"] lastPathComponent]]];
            
            //Pre Proxy Config
            downloadURL = [NSString stringWithFormat:@"/mp-content%@",[patchDict objectForKey:@"url"]];
            qlinfo(@"Download patch from: %@",downloadURL);
            
            err = nil;
            dlPatchLoc = [mpAsus downloadUpdate:downloadURL error:&err];
            if (err) {
                qlerror(@"Error downloading a patch, skipping %@. Err Message: %@",[patch objectForKey:@"patch"],[err localizedDescription]);
                [self progress:[NSString stringWithFormat:@"Error downloading a patch, skipping %@.",[patch objectForKey:@"patch"]]];
                break;
            }
            [self progress:[NSString stringWithFormat:@"Patch download completed."]];
            [NSThread sleepForTimeInterval:1.0];
            qlinfo(@"File downloaded to %@",dlPatchLoc);
        }
        @catch (NSException *e)
        {
            qlerror(@"%@", e);
            break;
        }
        */
        
        // *****************************
        // Validate hash, before install
        
        /*
        [self progress:[NSString stringWithFormat:@"Validating downloaded patch."]];
        
        
        NSString *fileHash = [mpCrypto md5HashForFile:dlPatchLoc];
        
        qlinfo(@"Downloaded file hash: %@ (%@)",fileHash,[patchDict objectForKey:@"hash"]);
        if ([[[patchDict objectForKey:@"hash"] uppercaseString] isEqualTo:[fileHash uppercaseString]] == NO)
        {
            [self progress:[NSString stringWithFormat:@"The downloaded file did not pass the file hash validation. No install will occur."]];
            qlerror(@"The downloaded file did not pass the file hash validation. No install will occur.");
            mpCrypto = nil;
            continue;
        }
        mpCrypto = nil;
        */
        
        
        // *****************************
        // Now we need to unzip
        [self progress:[NSString stringWithFormat:@"Uncompressing patch, to begin install."]];
        
        qlinfo(@"Begin decompression of file, %@",dlPatchLoc);
        err = nil;
        [mpAsus unzip:dlPatchLoc error:&err];
        if (err) {
            [self progress:[NSString stringWithFormat:@"Error decompressing a patch, skipping %@.",[patch objectForKey:@"patch"]]];
            qlerror(@"Error decompressing a patch, skipping %@. Err Message:%@",[patch objectForKey:@"patch"],[err localizedDescription]);
            break;
        }
        
        [self progress:[NSString stringWithFormat:@"Patch has been uncompressed."]];
        qlinfo(@"File has been decompressed.");
        
        // *****************************
        // Run PreInstall Script
        
        if ([[patchDict objectForKey:@"preinst"] length] > 0 && [[patchDict objectForKey:@"preinst"] isEqualTo:@"NA"] == NO)
        {
            [self progress:[NSString stringWithFormat:@"Begin pre install script."]];
            NSString *preInstScript = [[patchDict objectForKey:@"preinst"] decodeBase64AsString];
            qldebug(@"preInstScript=%@",preInstScript);
            preInstallRes = [self runScript:preInstScript];
            if ( preInstallRes != 0 ) {
                qlerror(@"Error (%d) running pre-install script.",preInstallRes);
                break;
            }
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
            
            // Install pkg(s)
            for (int x = 0; x < [pkgList count]; x++)
            {
                pkgPath = [NSString stringWithFormat:@"%@/%@",pkgBaseDir,[pkgList objectAtIndex:x]];
                [self progress:[NSString stringWithFormat:@"Installing %@",[pkgPath lastPathComponent]]];
                
                qlinfo(@"Start install of %@",pkgPath);
                installResult = 0;
                installResult = [self installPKG:pkgPath target:@"/" env:[patchDict objectForKey:@"env"]];
                if (installResult != 0) {
                    [self progress:[NSString stringWithFormat:@"Error installing patch."]];
                    qlerror(@"Error installing package, error code %d.",installResult);
                    hadErr = YES;
                    break;
                } else {
                    [self progress:[NSString stringWithFormat:@"Install was successful."]];
                    qlinfo(@"%@ was installed successfully.",pkgPath);
                }
            } // End Loop
        }
        @catch (NSException *e)
        {
            [self progress:[NSString stringWithFormat:@"Error installing patch."]];
            qlerror(@"%@", e);
            qlerror(@"Error attempting to install patch, skipping %@. Err Message:%@",[patch objectForKey:@"patch"],[err localizedDescription]);
            break;
        }
        
        // If we had an error, try the next one.
        if (hadErr) {
            continue;
        }
        
        // *****************************
        // Run PostInstall Script
        if ([[patchDict objectForKey:@"postinst"] length] > 0 && [[patchDict objectForKey:@"postinst"] isEqualTo:@"NA"] == NO)
        {
            [self progress:[NSString stringWithFormat:@"Begin post install script."]];
            NSString *postInstScript = [[patchDict objectForKey:@"postinst"] decodeBase64AsString];
            qldebug(@"preInstScript=%@",postInstScript);
            postInstallRes = [self runScript:postInstScript];
            if ( postInstallRes != 0 ) {
                qlerror(@"Error (%d) running post-install script.",preInstallRes);
                break;
            }
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
        
        patchInstallCount++;
    }
    
    if (patchInstallsFound == patchInstallCount) {
        return 0;
    } else {
        return 1;
    }
}

- (int)installPKG:(NSString *)aPkgPath target:(NSString *)aTarget env:(NSString *)aEnv
{
    int result = 99;
    
    InstallPackage *ipkg = [[InstallPackage alloc] init];
    result = [ipkg installPkgToRoot:aPkgPath env:aEnv];
    
    return result;
}

- (int)runScript:(NSString *)aScript
{
    int result = 99;
    
    logit(lcl_vDebug,@"Running script\n%@",aScript);
    
    BOOL scriptResult = NO;
    MPScript *mps = [[MPScript alloc] init];
    scriptResult = [mps runScript:aScript];
    if (scriptResult == YES) {
        result = 0;
    }
    
    return result;
}

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

- (void)scanData:(MPScanner *)scanner data:(NSString *)aData
{
    progressText.stringValue = aData;
}

- (void)installData:(InstallAppleUpdate *)installUpdate data:(NSString *)aData type:(NSUInteger)dataType
{
    /*
    @try
    {
        if (dataType == kMPProcessStatus) {
            //[_client statusData:data];
        } else if (dataType == kMPInstallStatus) {
            //[_client installData:data];
        } else {
            logit(lcl_vError,@"MPPostDataType not supported.");
        }
    }
    @catch (NSException *exception) {
        logit(lcl_vError,@"%@",exception);
    }
     */
    logit(lcl_vInfo,@"%@",aData);
}

- (void)patchScan:(MPPatchScan *)patchScan didReciveStatusData:(NSString *)data
{
    logit(lcl_vDebug,@"[patchScan:didReciveStatusData]: %@",data);
}

#pragma mark - Misc

- (void)progress:(NSString *)text
{
    dispatch_async(dispatch_get_main_queue(), ^(void){
		[self->progressText setStringValue:text];
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
