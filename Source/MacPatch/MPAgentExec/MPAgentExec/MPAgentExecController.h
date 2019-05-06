//
//  MPAgentExecController.h
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

#import <Foundation/Foundation.h>
#import "MacPatch.h"

@interface MPAgentExecController : NSObject

@property (nonatomic, strong)           NSString    *_appPid;
//OK
@property (nonatomic, assign)           BOOL        iLoadMode;
//OK
@property (nonatomic, assign)           BOOL        forceTaskRun;

@property (nonatomic, assign, readonly) int         errorCode;
@property (nonatomic, strong, readonly) NSString    *errorMsg;
@property (nonatomic, assign, readonly) int         needsReboot;

@property (nonatomic, strong)           NSURL       *mp_SOFTWARE_DATA_DIR;

// Scan for Patches
- (void)scanForPatches:(MPPatchContentType)contentType forceRun:(BOOL)forceRun;

// Scan for a Patch using a bundleID, used for patching software installs
- (void)scanForPatchUsingBundleID:(NSString *)aBundleID;

// Scan and patch system
// Use bundleID when targeting a single custom patch, otherwise use NULL
- (void)patchScanAndUpdate:(MPPatchContentType)contentType bundleID:(NSString *)bundleID;


-(BOOL)checkPatchPreAndPostForRebootRequired:(NSArray *)aDictArray;
-(void)removeInstalledPatchFromCacheFile:(NSString *)aPatchName;
-(void)scanAndUpdateAgentUpdater;
-(NSDictionary *)getAgentUpdaterInfo;

-(BOOL)isLocalUserLoggedIn;
-(void)postNotificationTo:(NSString *)aName info:(NSString *)info isGlobal:(BOOL)glb;

-(BOOL)installSoftwareTask:(NSString *)aTask;
-(int)installSoftwareTasksForGroup:(NSString *)aGroupName;
-(int)installSoftwareTasksUsingPLIST:(NSString *)aPlist;

@end
