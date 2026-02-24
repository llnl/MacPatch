//
//  Patching.h
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

#import <Foundation/Foundation.h>
#import "MacPatch.h"

NS_ASSUME_NONNULL_BEGIN

@interface Patching : NSObject <MPPatchingDelegate>
{
    int taskPID;
    NSString *taskFile;
    
@private
    
    NSFileManager *fm;
}

@property (nonatomic, assign) BOOL                iLoadMode;
@property (nonatomic, assign) int                 taskPID;
@property (nonatomic)         NSString            *taskFile;


@property (nonatomic, assign) MPPatchContentType patchFilter;
@property (nonatomic, assign) int                scanType;
@property (nonatomic)         NSString           *bundleID;
@property (nonatomic, assign) BOOL               forceRun;

- (void)patchScan;
- (void)patchScan:(MPPatchContentType)contentType forceRun:(BOOL)aForceRun;

- (void)patchScanAndUpdate;
- (void)patchScanAndUpdate:(MPPatchContentType)contentType bundleID:(NSString *)bundleID;

- (void)applPatchScanAndUpdate;
@end

NS_ASSUME_NONNULL_END

