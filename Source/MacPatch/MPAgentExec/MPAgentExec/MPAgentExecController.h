//
//  MPAgentExecController.h
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

#import <Foundation/Foundation.h>
#import "MacPatch.h"
#import "MPWorkerProtocol.h"
#import "MPNetRequest.h"

@class MPAsus;
@class MPDataMgr;

@interface MPAgentExecController : NSObject <MPWorkerClient, MPNetRequestController>
{
    NSDictionary    *_defaults;
    NSString        *_cuuid;
    NSString        *_appPid;
    
    MPAsus          *mpAsus;
    MPDataMgr       *mpDataMgr;
	
    BOOL			iLoadMode;
	BOOL			forceRun;
	
	NSArray			*approvedPatches;
    NSFileManager   *fm;
    
    int             errorCode;
    NSString        *errorMsg;

    // Helper
	id              proxy;
}

@property (nonatomic, strong) NSDictionary       *_defaults;
@property (nonatomic, strong) NSString           *_cuuid;
@property (nonatomic, strong) NSString           *_appPid;

@property (nonatomic, assign) BOOL               iLoadMode;
@property (nonatomic, assign) BOOL               forceRun;
@property (nonatomic, assign) BOOL               overrideRebootPatchInstalls;

@property (nonatomic, strong) NSArray            *approvedPatches;

@property (nonatomic, readonly, assign) int      errorCode;
@property (nonatomic, readonly, strong) NSString *errorMsg;
@property (nonatomic, readonly, assign) int      needsReboot;
@property (nonatomic, strong)           NSURL    *mp_SOFTWARE_DATA_DIR;

-(id)initForBundleUpdate;
-(void)overRideDefaults:(NSDictionary *)aDict;

-(void)scanForPatches;
-(void)scanForPatchesWithFilter:(int)aFilter;
-(void)scanForPatchesWithFilter:(int)aFilter byPassRunning:(BOOL)aByPass;
-(void)scanForPatchesWithFilterWaitAndForce:(int)aFilter byPassRunning:(BOOL)aByPass;
-(void)scanForPatchesWithFilterWaitAndForceWithCritical:(int)aFilter byPassRunning:(BOOL)aByPass critical:(BOOL)aCritical;
-(void)scanForPatchUsingBundleID:(NSString *)aBundleID;

-(void)scanForPatchesAndUpdate;
-(void)scanForPatchesAndUpdateWithFilter:(int)aFilter;
-(void)scanForPatchesAndUpdateWithFilterCritical:(int)aFilter critical:(BOOL)aCritical;
-(void)scanAndUpdateCustomWithPatchBundleID:(NSString *)aPatchBundleID;

-(BOOL)checkPatchPreAndPostForRebootRequired:(NSArray *)aDictArray;
-(void)removeInstalledPatchFromCacheFile:(NSString *)aPatchName;
-(void)scanForAVDefs;
-(void)scanForAVDefsAndUpdate;
-(void)scanAndUpdateAgentUpdater;
-(NSDictionary *)getAgentUpdaterInfo;

-(BOOL)isTaskRunning:(NSString *)aTaskName;
-(void)writeTaskRunning:(NSString *)aTaskName;
-(void)removeTaskRunning:(NSString *)aTaskName;

-(BOOL)isLocalUserLoggedIn;
-(void)postNotificationTo:(NSString *)aName info:(NSString *)info isGlobal:(BOOL)glb;

-(int)installSoftwareTasks:(NSString *)aTasks;
-(int)installSoftwareTasksForGroup:(NSString *)aGroupName;
-(int)installSoftwareTasksUsingPLIST:(NSString *)aPlist;

@end
