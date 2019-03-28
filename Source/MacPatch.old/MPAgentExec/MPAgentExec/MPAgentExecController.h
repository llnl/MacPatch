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
#import "MPWorkerProtocol.h"

@class MPAsus;
@class MPDataMgr;

@interface MPAgentExecController : NSObject <MPWorkerClient>
{
    MPAsus          *mpAsus;
    MPDataMgr       *mpDataMgr;
    NSFileManager   *fm;

    // Helper
	id              proxy;
}

@property (nonatomic, strong)           NSString    *_appPid;

@property (nonatomic, assign)           BOOL        iLoadMode;
@property (nonatomic, assign)           BOOL        forceRun;

@property (nonatomic, strong)           NSArray     *approvedPatches;

@property (nonatomic, assign, readonly) int         errorCode;
@property (nonatomic, strong, readonly) NSString    *errorMsg;
@property (nonatomic, assign, readonly) int         needsReboot;

@property (nonatomic, strong)           NSURL       *mp_SOFTWARE_DATA_DIR;

-(id)initForBundleUpdate;

-(void)scanForPatches;
-(void)scanForPatchesWithFilter:(int)aFilter;
-(void)scanForPatchesWithFilter:(int)aFilter byPassRunning:(BOOL)aByPass;
-(void)scanForPatchesWithFilterWaitAndForce:(int)aFilter byPassRunning:(BOOL)aByPass;
-(void)scanForPatchesWithFilterWaitAndForceWithCritical:(int)aFilter byPassRunning:(BOOL)aByPass critical:(BOOL)aCritical;
-(void)scanForPatchUsingBundleID:(NSString *)aBundleID;
// TEST
- (void)scanForPatchUsingBundleIDAlt:(NSString *)aBundleID error:(NSError **)error;

-(void)scanForPatchesAndUpdate;
-(void)scanForPatchesAndUpdateWithFilter:(int)aFilter;
-(void)scanForPatchesAndUpdateWithFilterCritical:(int)aFilter critical:(BOOL)aCritical;
-(void)scanAndUpdateCustomWithPatchBundleID:(NSString *)aPatchBundleID;

-(BOOL)checkPatchPreAndPostForRebootRequired:(NSArray *)aDictArray;
-(void)removeInstalledPatchFromCacheFile:(NSString *)aPatchName;
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
