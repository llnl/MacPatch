//
//  MPAsus.h
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

/*
	MPAsus, is the class to collect and install Apple Software Updates data 
*/

#import <Cocoa/Cocoa.h>
#import "MPNSTask.h"
@class MPNetworkUtils;

@protocol MPAsusDelegate

@optional
- (void)asusProgress:(NSString *)data;
@end

@interface MPAsus : NSObject <MPNSTaskDelegate>

@property (weak, nonatomic) id <MPAsusDelegate> delegate;
@property (nonatomic, assign) BOOL allowClient; // Allow Install on Mac OS X
@property (nonatomic, assign) BOOL allowServer; // Allow Install on Mac OS X Server - Default NO

@property (nonatomic, assign, readonly) BOOL patchMustShutdown; // Patch Install Reboot Status

/**
 Scan System for Apple Software Updates

 @return NSArray of apple software updates
 */
- (NSArray *)scanForAppleUpdates;


/**
 Install a single apple software update

 @param approvedUpdate SUPatchName
 @return BOOL
 */
- (BOOL)installAppleSoftwareUpdate:(NSString *)approvedUpdate;

/**
 Download Apple Update for install with out network connection.

 @param updateName supatchname
 @return BOOL
 */
- (BOOL)downloadAppleUpdate:(NSString *)updateName;

@end
