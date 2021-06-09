//
//  MPPatchScan.h
/*
 Copyright (c) 2021, Lawrence Livermore National Security, LLC.
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

#import <Cocoa/Cocoa.h>

@protocol MPPatchScanDelegate

@optional
- (void)scanProgress:(NSString *)scanStr;

@end

@interface MPPatchScan : NSObject

@property (weak, nonatomic) id <MPPatchScanDelegate> delegate;

/**
 Convience method
 
 Scan a system for custom patches. Return NSArray of required patches
 
 @return NSArray
 */
-(NSArray *)scanForPatches;
/**
 Convience method
 
 Scan a system for custom patch based on BundleID. Return NSArray of required patches
 
 @param aBundleID - Custom patch bundle id
 @return NSArray
 */
-(NSArray *)scanForPatchesWithbundleID:(NSString *)aBundleID;

/**
 This method is the main patch scanning method. If BundleID is passed it will only scan for
 that bundle id, otherwise it will scan for all patches. If no bundle id is use please pass
 NULL to the aBundleID param.
 
 @param aBundleID - Patch Bundle ID or NULL
 @return NSArray of needed patches
 */
- (NSArray *)scanForPatchesOrScanForBundleID:(NSString *)aBundleID;

@end


