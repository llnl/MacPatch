//
//  TaskCommands.m
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

#import "TaskCommands.h"
#import <Foundation/Foundation.h>

#import "MacPatch.h"
#import "CheckIn.h"
#import "MPInv.h"
#import "Patching.h"
#import "AntiVirus.h"
#import "MPAgentUpdater.h"
#import "SoftwareController.h"
/*

#import "MPAgentRegister.h"


#import "MPOSUpgrade.h"
#import "TasksDaemon.h"
#import "MPProvision.h"


#import "MPFileVault.h"
 */

#ifndef TASKCOMMAND_ENUM_DEFINED
#define TASKCOMMAND_ENUM_DEFINED 1
// Define TaskCommand locally if not provided by the header to avoid "Expected a type" errors.
typedef NS_ENUM(NSInteger, TaskCommand) {
    CommandUnknown = 0,
    kMPCheckIn,
    kMPAgentCheck,
    kMPVulScan,
    kMPVulUpdate,
    kMPAVInfo,
    kMPAVCheck,
    kMPInvScan,
    kMPProfiles,
    kMPSrvList,
    kMPSUSrvList,
    kMPSWDistMan,
    kMPWSPost,
    kMPPatchCrit,
    kMPPatchApple,
    kMPAppStore
};
#endif

@interface TaskCommands ()

@property (nonatomic, strong) NSOperationQueue *operationQueue;

@end


@implementation TaskCommands

- (TaskCommand)commandFromString:(NSString *)string {
    static NSDictionary<NSString *, NSNumber *> *mapping = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        mapping = @{
            @"kMPCheckIn": @(kMPCheckIn),
            @"kMPAgentCheck": @(kMPAgentCheck),
            @"kMPVulScan": @(kMPVulScan),
            @"kMPVulUpdate": @(kMPVulUpdate),
            @"kMPAVInfo": @(kMPAVInfo),
            @"kMPAVCheck": @(kMPAVCheck),
            @"kMPInvScan": @(kMPInvScan),
            @"kMPProfiles": @(kMPProfiles),
            @"kMPSrvList": @(kMPSrvList),
            @"kMPSUSrvList": @(kMPSUSrvList),
            @"kMPSWDistMan": @(kMPSWDistMan),
            @"kMPWSPost": @(kMPWSPost),
            @"kMPPatchCrit": @(kMPPatchCrit),
            @"kMPPatchApple": @(kMPPatchApple),
            @"kMPAppStore": @(kMPAppStore)
        };
    });
    
    NSNumber *command = mapping[string];
    return command ? [command integerValue] : CommandUnknown;
}

- (void)runTaskCommand:(NSString*)cmd
{
    switch ([self commandFromString:cmd]) {
        case kMPCheckIn:
            [self clientCheckIn];
            break;
        case kMPAgentCheck:
            [self scanAndUpdateAgentUpdater];
            break;
        case kMPVulScan:
            [self patchScan];
            break;
        case kMPVulUpdate:
            [self patchScanAndUpdate];
            break;
        case kMPAVInfo:
            [self avInfoScan];
            break;
        case kMPAVCheck:
            [self avInfoScanAndDefsUpdate];
            break;
        case kMPInvScan:
            [self inventoryCollection];
            break;
        case kMPProfiles:
            [self profilesScanAndInstall];
            break;
        case kMPSrvList:
            LogDebug(@"MacPatch Server list as been removed.");
            break;
        case kMPSUSrvList:
            LogDebug(@"Apple Software Update Server list as been removed.");
            break;
        case kMPSWDistMan:
            [self swDistScanAndInstall];
            break;
        case kMPWSPost:
            [self postFailedWSRequests];
            break;
        case kMPPatchCrit:
            // CEH TODO
            LogDebug(@"kMPPatchCrit");
            break;
        case kMPPatchApple:
            [self applePatchScanAndUpdate];
        case kMPAppStore:
            // CEH TODO
            LogDebug(@"kMPAppStore");
            break;
        default:
            qlerror(@"Unknown command %@", cmd);
            break;
    }
}

- (void)waitForOperationQueueCompletion
{
    if ([NSThread isMainThread]) {
        // Keep the run loop active while operations are in progress
        // to prevent blocking the main thread
        while (self.operationQueue.operationCount > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }
    } else {
        [self.operationQueue waitUntilAllOperationsAreFinished];
    }
}

#pragma mark - Task Commands
- (void)clientCheckIn
{
    LogInfo(@"%s: Was Called.", __func__);
    CheckIn *ac = [[CheckIn alloc] init];
    [ac runClientCheckIn];
}

-(void)inventoryCollection
{
    LogInfo(@"%s: Was Called.", __func__);
    MPInv *inv = [[MPInv alloc] init];
    [inv collectInventoryData];
}

- (void)patchScan
{
    LogInfo(@"%s: Was Called.", __func__);
    Patching *p = [[Patching alloc] init];
    [p patchScan];
}

- (void)patchScanAndUpdate
{
    LogDebug(@"%s: Was Called.", __func__);
    Patching *p = [[Patching alloc] init];
    [p patchScanAndUpdate];
}

- (void)applePatchScanAndUpdate
{
    LogDebug(@"%s: Was Called.", __func__);
    Patching *p = [[Patching alloc] init];
    [p applPatchScanAndUpdate];
}

- (void)avInfoScan
{
    LogDebug(@"%s: Was Called.", __func__);
    AntiVirus *mpav = [[AntiVirus alloc] init];
    [mpav scanDefs];
}

- (void)avInfoScanAndDefsUpdate
{
    LogDebug(@"%s: Was Called.", __func__);
    AntiVirus *mpav = [[AntiVirus alloc] init];
    [mpav scanAndUpdateDefs];
}

-(void)scanAndUpdateAgentUpdater
{
    LogDebug(@"%s: Was Called.", __func__);
    MPAgentUpdater *agentUpdater = [[MPAgentUpdater alloc] init];
    [agentUpdater scanAndUpdateAgentUpdater];
}

- (void)swDistScanAndInstall
{
    LogDebug(@"%s: Was Called.", __func__);
    SoftwareController *swc = [[SoftwareController alloc] init];
    [swc setILoadMode:NO];
    [swc installMandatorySoftware];
}

- (void)profilesScanAndInstall
{
    LogDebug(@"%s: Was Called. Profile Support has been removed.", __func__);
}

- (void)postFailedWSRequests
{
    LogDebug(@"%s: Was Called.", __func__);
    MPFailedRequests *mpf = [[MPFailedRequests alloc] init];
    [mpf postFailedRequests];
}


@end

