//
//  MPAgentUp2DateController.h
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

#import <Cocoa/Cocoa.h>

@class MPServerConnection;
@class MPAsus;
@class MPDataMgr;

@interface MPAgentUp2DateController : NSObject 
{
	MPServerConnection *mpServerConnection;
    
    NSString        *_cuuid;
    NSString        *_appPid;
	NSDictionary    *_updateData;
    NSDictionary    *_osVerDictionary;
    
    MPAsus          *mpAsus;
    MPDataMgr       *mpDataMgr;
}

@property (nonatomic, strong)   NSString        *_cuuid;
@property (nonatomic, strong)   NSString        *_appPid;
@property (nonatomic, strong)   NSDictionary    *_updateData;
@property (nonatomic, strong)   NSDictionary    *_osVerDictionary;
@property (nonatomic, strong)   NSString        *_migrationPlist;

@property (strong)              NSTimer         *taskTimeoutTimer;
@property (nonatomic, assign)   NSTimeInterval  taskTimeoutValue;
@property (nonatomic, assign)   BOOL            taskTimedOut;

- (int)scanForUpdate;
- (void)scanAndUpdate;

@end
