//
//  MPSWDistTaskOperation.h
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

@class MPSettings;

@interface MPSWDistTaskOperation : NSOperation
{
    BOOL isExecuting;
    BOOL isFinished;
    
@private
    MPSettings          *settings;
    MPCrypto            *mpc;
    NSOperationQueue    *l_queue;
    NSFileManager       *fm;
    NSString            *_swDiskTaskListHash;
}

@property (nonatomic, readonly) BOOL                isExecuting;
@property (nonatomic, readonly) BOOL                isFinished;
@property (nonatomic, strong) NSString              *_fileHash;
@property (nonatomic, assign) NSTimeInterval        _timerInterval;
@property (nonatomic, strong) NSOperationQueue      *l_queue;
@property (nonatomic, strong) NSString              *_swDiskTaskListHash;
@property (nonatomic, strong) NSString              *sw_dir;

- (void)checkAndInstallMandatoryApplications;

- (BOOL)softwareItemInstalled:(NSDictionary *)dict;
- (NSArray *)filterMandatorySoftwareContent:(NSArray *)content;
- (BOOL)softwareTaskInstalled:(NSString *)aTaskID;
- (void)postInstallResults:(int)resultNo resultText:(NSString *)resultString task:(NSDictionary *)taskDict;

@end
