//
//  Patching.m
//  MPAgent
/*
 Copyright (c) 2026, Lawrence Livermore National Security, LLC.
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

#import "Patching.h"
#import "MacPatch.h"
#import <SystemConfiguration/SystemConfiguration.h>

@interface Patching () <MPPatchingDelegate>
{
    MPCodeSign *cs;
    MPSettings *settings;
}

@end

@implementation Patching

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
        patchFilter         = kAllPatches;
        scanType            = 0;
        bundleID            = NULL;
        forceRun            = NO;
        taskPID             = -99;
        fm                  = [NSFileManager defaultManager];
        cs                  = [[MPCodeSign alloc] init];
        settings            = [MPSettings new];
        
        [self setILoadMode:NO];
    }
    return self;
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
            LogError(@"%ld: %@",err.code,err.localizedDescription);
        }
        if ([strPID intValue] > 0) {
            [self setTaskPID:[strPID intValue]];
        }
    }
    
    if (self.taskPID == -99) {
        LogWarning(@"No task PID was defined");
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
        LogError(@"Can not kill task using PID. Found to many using the predicate.");
        LogDebug(@"%@",filtered);
    }
}

- (void)patchScan
{
    [self patchScan:kAllPatches forceRun:NO];
}

- (void)patchScan:(MPPatchContentType)contentType forceRun:(BOOL)aForceRun
{
    NSArray *_res;
    _res = [self scanForPatches:contentType forceRun:aForceRun];
    _res = nil;
}

// Scan Host for Patches based on BundleID
// Found patches are stored in self.appprovedPatches array
- (NSArray *)scanForPatchUsingBundleID:(NSString *)aBundleID
{
    LogInfo(@"Begin scanning system for patches.");
    LogInfo(@"Scanning system for %@ type patches using bundleID.",MPPatchContentType_toString[kCustomPatches]);
    
    MPPatching *scanner = [MPPatching new];
    NSArray *approvedUpdatesArray = [scanner scanForPatchUsingBundleID:aBundleID];
    
    LogInfo(@"Approved patches: %d",(int)approvedUpdatesArray.count);
    LogDebug(@"Approved patches to install: %@",approvedUpdatesArray);
    
    if (settings.agent.preStagePatches)
    {
        LogInfo(@"Staging Updates is enabled.");
        [self stagePatches:approvedUpdatesArray];
    }
    
    LogInfo(@"Patch Scan Completed.");
    if (!approvedUpdatesArray) {
        return @[];
    }
    return [approvedUpdatesArray copy];
}

// Scan Host for Patches
// Found patches are stored in self.appprovedPatches array
- (NSArray *)scanForPatches:(MPPatchContentType)contentType forceRun:(BOOL)aForceRun
{
    LogInfo(@"Begin scanning system for patches.");
    LogInfo(@"Scanning system for %@ type patches.",MPPatchContentType_toString[contentType]);
    
    MPPatching *scanner = [MPPatching new];
    NSArray *approvedUpdatesArray = [scanner scanForPatchesUsingTypeFilter:contentType forceRun:aForceRun];
    
    LogInfo(@"Approved patches: %d",(int)approvedUpdatesArray.count);
    for (NSDictionary *p in approvedUpdatesArray) {
        LogInfo(@"- %@ (%@)",p[@"patch"],p[@"version"]);
    }
    LogDebug(@"Approved patches to install: %@",approvedUpdatesArray);
    
    if (settings.agent.preStagePatches)
    {
        LogInfo(@"Staging Updates is enabled.");
        [self stagePatches:approvedUpdatesArray];
    }
    
    // Added a global notification to update image icon of MPClientStatus
    if (contentType != kCriticalPatches)
    {
        // We only update notification if a normal scan has run
        [[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"kRefreshStatusIconNotification" object:nil userInfo:nil options:NSNotificationPostToAllSessions];
    }
    
    LogInfo(@"Patch Scan Completed.");
    if (!approvedUpdatesArray) {
        return @[];
    }
    return [approvedUpdatesArray copy];
}

- (void)patchScanAndUpdate
{
    [self patchScanAndUpdate:kAllPatches bundleID:@""];
}

- (void)patchScanAndUpdate:(MPPatchContentType)contentType bundleID:(NSString *)bundleID
{
    [self iLoadStatus:@"Status: Scanning for patches."];
    LogInfo(@"Begin Patch Scan and Update.");
    LogInfo(@"Scanning host for required patches.");
    NSArray *updatesArray = @[];
    if (bundleID && bundleID.length > 0) {
        updatesArray = [self scanForPatchUsingBundleID:bundleID];
    } else {
        updatesArray = [self scanForPatches:contentType forceRun:NO];
    }
    
    // -------------------------------------------
    // If no updates, exit
    if (updatesArray.count <= 0)
    {
        LogInfo( @"No approved patches to install.");
        [self iLoadStatus:@"Completed: No approved patches to install."];
        return;
    }
    
    // -------------------------------------------
    // Sort Array by patch install weight
    LogInfo( @"Sorting patches by required order.");
    NSSortDescriptor *desc = [NSSortDescriptor sortDescriptorWithKey:@"patch_install_weight" ascending:YES];
    updatesArray = [updatesArray sortedArrayUsingDescriptors:[NSArray arrayWithObject:desc]];
    
    // -------------------------------------------
    // Check to see if client os type is allowed to perform updates.
    LogInfo( @"Checking system patching requirments.");
    NSDictionary *systeInfo = [MPSystemInfo osVersionInfo];
    NSString *_osType = systeInfo[@"ProductName"];
    if ([_osType.lowercaseString isEqualToString:@"mac os x"] || [_osType.lowercaseString isEqualToString:@"macos"])
    {
        if (settings.agent.patchClient)
        {
            if (settings.agent.patchClient == 0)
            {
                LogInfo(@"Host is a Mac OS X client and \"AllowClient\" property is set to false. No updates will be applied.");
                return;
            }
        }
    }
    
    if ([_osType.lowercaseString isEqualToString:@"mac os x server"])
    {
        if (settings.agent.patchServer)
        {
            if (settings.agent.patchServer == 0) {
                LogInfo(@"Host is a Mac OS X Server and \"AllowServer\" property is set to false. No updates will be applied.");
                return;
            }
        }
        else
        {
            LogInfo(@"Host is a Mac OS X Server and \"AllowServer\" property is not defined. No updates will be applied.");
            return;
        }
    }
    
    // -------------------------------------------
    // iLoad / Provisioning
    BOOL hasConsoleUserLoggedIn = TRUE;
    LogInfo( @"%d updates to install.", (int)updatesArray.count);
    [self iLoadStatus:@"Status: %d updates to install.", (int)updatesArray.count];
    
    if (!iLoadMode)
    {
        // We know if the system is in iLoad/Provisioning mode that no one is
        // logged in. So we can patch and reboot.
        
        // Check for console user
        LogInfo( @"Checking for any logged in users.");
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
            LogInfo( @"Error getting console user status. %@",e);
        }
    }
    
    // -------------------------------------------
    // Begin Patching
    MPPatching *patching = [MPPatching new];
    patching.delegate = self;
    if (iLoadMode) patching.iLoadMode = YES;
    LogInfo(@"Begin patch installs.");
    NSDictionary *patchingResult = [patching installPatchesUsingTypeFilter:updatesArray typeFilter:contentType];
    NSInteger patchesNeedingReboot = [patchingResult[@"patchesNeedingReboot"] integerValue];
    NSInteger rebootPatchesNeeded = [patchingResult[@"rebootPatchesNeeded"] integerValue];
    
    // -------------------------------------------
    // Update MP Client Status to reflect patch install
    [[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"kRefreshStatusIconNotification" object:nil userInfo:nil options:NSNotificationPostToAllSessions];
    
    // If any patches that were installed needed a reboot
    LogDebug(@"Number of installed patches needing a reboot %ld.", (long)patchesNeedingReboot);
    if (patchesNeedingReboot > 0)
    {
        if (iLoadMode)
        {
            LogInfo(@"Patches have been installed that require a reboot. Please reboot the systems as soon as possible.");
            return;
        }
        if (!hasConsoleUserLoggedIn)
        {
            if (settings.agent.reboot)
            {
                if (settings.agent.reboot == 1)
                {
                    LogInfo(@"Patches have been installed that require a reboot. Rebooting system now.");
                    [NSTask launchedTaskWithLaunchPath:@"/bin/launchctl" arguments:@[@"reboot"]];
                }
                else
                {
                    LogInfo(@"Patches have been installed that require a reboot. Please reboot the systems as soon as possible.");
                    return;
                }
                
            }
        }
    }
    // Have Patches that need to be install requiring a reboot or patches that have been
    // installed require a reboot.
    if (patchesNeedingReboot > 0 || rebootPatchesNeeded > 0)
    {
        LogInfo(@"Patches that require reboot need to be installed. Opening reboot dialog now.");
        [@"reboot" writeToFile:MP_PATCH_ON_LOGOUT_FILE atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [fm setAttributes:@{@"NSFilePosixPermissions":[NSNumber numberWithUnsignedLong:0777]} ofItemAtPath:MP_PATCH_ON_LOGOUT_FILE error:NULL];
    }
    [self iLoadStatus:@"Status: Scanning and Patching completed."];
    LogInfo(@"Patch scan and installs completed.");
}

- (void)applePatchScanAndUpdate
{
    LogInfo(@"Begin Apple Patch Scan and Update.");
    LogInfo(@"Scanning for apple patches.");
    NSArray *updatesArray = @[];
    
    // -------------------------------------------
    // iLoad / Provisioning
    BOOL hasConsoleUserLoggedIn = TRUE;
    
    
    
    // -------------------------------------------
    // Begin Patching
    MPPatching *patching = [MPPatching new];
    patching.delegate = self;
    patching.iLoadMode = NO;
    LogInfo(@"Begin patch installs.");
    BOOL patchingResult = [patching installAllApplePatches];
    LogInfo(@"Appl Patch Scan and Installs completed.");
}

#pragma mark - Patching Private Methods

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
            LogInfo(@"Pre staging update %@.",patch[@"patch"]);
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
                            LogInfo(@"Skipping %@, due to zero size.",_p[@"patch_name"]);
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
                            LogInfo(@"Patch %@ is already pre-staged.",patch[@"patch"]);
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
                                        LogInfo(@"Patch %@ has already been staged.",patch[@"patch"]);
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
                        
                        LogInfo(@"Download patch from: %@",downloadURL);
                        dlErr = nil;
                        NSString *dlPatchLoc = [self downloadUpdate:downloadURL error:&dlErr];
                        if (dlErr)
                        {
                            qlerror(@"%@",dlErr.localizedDescription);
                        }
                        LogDebug(@"Downloaded patch to %@",dlPatchLoc);
                        
                        dlErr = nil;
                        [fm moveItemAtPath:dlPatchLoc toPath:stagedFilePath error:&dlErr];
                        if (dlErr)
                        {
                            qlerror(@"%@",dlErr.localizedDescription);
                            continue; // Error creating stage patch dir. Can not use it.
                        }
                        LogInfo(@"%@ has been staged.",patch[@"patch"]);
                        LogDebug(@"Moved patch to: %@",stagedFilePath);
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
    LogInfo(@"Cleaning up older pre-staged patches.");
    NSString *stagePatchDir;
    
    NSString *stageDir = [NSString stringWithFormat:@"%@/Data/.stage",MP_ROOT_CLIENT];
    NSArray *dirEnum = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:stageDir error:NULL];
    
    for (NSString *filename in dirEnum)
    {
        LogDebug(@"Validating patch %@",filename);
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
            LogInfo(@"Delete obsolete patch %@",filename);
            [[NSFileManager defaultManager] removeItemAtPath:stagePatchDir error:NULL];
        }
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
        LogInfo(@"%@ is currently logged in.",(__bridge NSString *)consoleUserName);
        CFRelease(consoleUserName);
    } else {
        result = NO;
    }
    
    return result;
}


- (void)patchProgress:(NSString *)progressStr
{
    NSString *msg = progressStr ?: @"";
    LogInfo(@"Patch progress: %@", msg);
    [self iLoadStatus:@"Status: %@", msg];
}

- (void)patchingProgress:(MPPatching *)mpPatching progress:(NSString *)progressStr
{
    NSString *msg = progressStr ?: @"";
    LogInfo(@"Patching progress: %@", msg);
    [self iLoadStatus:@"Status: %@", msg];
}

@end

