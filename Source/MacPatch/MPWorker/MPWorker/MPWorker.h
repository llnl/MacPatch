//
//  MPWorker.h
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
#import "MPWorkerProtocol.h"
#import "MPPatchScan.h"

@interface MPWorker : NSObject <MPWorkerServer,MPPatchScanDelegate>
{
    
    int                 taskTimeoutValue;
    id<MPWorkerClient> _client;
    
@private

    NSFileManager       *fm;
    NSMutableArray      *connections;
    NSTask              *swTask;
    NSPipe              *pipe_task;
	NSFileHandle        *fh_task;
    
    NSTimer             *_timeoutTimer;
	BOOL                taskTimedOut;
    BOOL                taskIsRunning;
    int                 installtaskResult;
    NSURL               *mp_SOFTWARE_DATA_DIR;
    
    // SelfPatch
    NSTask              *spTask;
}

@property (nonatomic, strong) id<MPWorkerClient> _client;

@property (strong)              NSTimer     *_timeoutTimer;
@property (nonatomic, assign)   int         taskTimeoutValue;
@property (nonatomic, assign)   BOOL        taskTimedOut;
@property (nonatomic, assign)   BOOL        taskIsRunning;
@property (nonatomic, assign)   int         installtaskResult;
@property (nonatomic, strong)   NSURL       *mp_SOFTWARE_DATA_DIR;

// Software Dist
- (int)installSoftware:(NSDictionary *)aSWDict;
- (int)patchSoftware:(NSDictionary *)aSWDict;

@end
