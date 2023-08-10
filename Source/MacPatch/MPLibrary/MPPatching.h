//
//  MPPatching.h
//  MPLibrary
/*
 Copyright (c) 2023, Lawrence Livermore National Security, LLC.
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
#import "MPPatchScan.h"
#import "MPAsus.h"
#import "MPHTTPRequest.h"

@class MPPatching;


@protocol MPPatchingDelegate <NSObject>

@optional

- (void)patchProgress:(NSString *)progressStr;
- (void)patchingProgress:(MPPatching *)mpPatching progress:(NSString *)progressStr;

@end

@class MPPatchScan;

@interface MPPatching : NSObject <MPPatchingDelegate, MPPatchScanDelegate, MPAsusDelegate, MPHTTPRequestDelegate>

@property (weak, nonatomic) id <MPPatchingDelegate> delegate;

@property (nonatomic, assign) BOOL forceTaskRun;
@property (nonatomic, assign) BOOL iLoadMode;
@property (nonatomic, assign) BOOL installRebootPatchesWhileLoggedIn;

- (BOOL)patchingForHostIsPaused;
+ (NSString *)isPatchingForHostIsPausedAsString;

// Scan for Patches
- (NSArray *)scanForPatchUsingBundleID:(NSString *)aBundleID;
- (NSArray *)scanForPatchesUsingTypeFilter:(MPPatchContentType)contentType forceRun:(BOOL)forceRun;
- (NSArray *)scanForPatchesUsingTypeFilterOrBundleIDWithPatchAll:(MPPatchContentType)contentType bundleID:(NSString *)bundleID forceRun:(BOOL)forceRun patchAllFound:(BOOL)patchAll;

// Patch System

/**
 Install single patch
 
 This is just a convience method. It simple wraps the dictionary in an array and
 passes it on the installPatchesUsingTypeFilter method

 @param approvedPatch Dictionary containf the patch
 @param contentType - Content type filter All, Apple, Custom
 @return NSDictionary
 */
- (NSDictionary *)installPatchUsingTypeFilter:(NSDictionary *)approvedPatch typeFilter:(MPPatchContentType)contentType;

// Returns NSDictionary with 2 keys
// - patchesNeedingReboot = Number of installed patches needing reboot
// - rebootPatchesNeeded = Number of reboot patches needing to be installed
- (NSDictionary *)installPatchesUsingTypeFilter:(NSArray *)approvedPatches typeFilter:(MPPatchContentType)contentType;


// Scan and Patch for 

@end

