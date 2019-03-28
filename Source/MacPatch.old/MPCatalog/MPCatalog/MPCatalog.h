//
//  MPCatalog.h
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

#import <Cocoa/Cocoa.h>

@interface MPCatalog : NSObject
{
	NSDictionary		*g_Defaults;
	NSDictionary		*g_OSVers;
	NSString			*g_cuuid;
	NSString			*g_serialNo;
	NSString			*g_osVer;
	NSString			*g_osType;
	NSString			*g_agentVer;
    NSMutableArray		*g_Tasks;
	NSString			*g_TasksHash;
	NSMutableDictionary	*g_AppHashes;
    NSString			*g_agentPid;
    // SWDist
    NSMutableArray		*g_SWDistTasks;
	NSString			*g_SWDistTasksHash;
    NSString			*g_SWDistTasksJSONHash;
}

@property (nonatomic, retain) NSDictionary *g_Defaults;
@property (nonatomic, retain) NSDictionary *g_OSVers;
@property (nonatomic, retain) NSString *g_cuuid;
@property (nonatomic, retain) NSString *g_serialNo;
@property (nonatomic, retain) NSString *g_osVer;
@property (nonatomic, retain) NSString *g_osType;
@property (nonatomic, retain) NSString *g_agentVer;
@property (nonatomic, retain) NSMutableArray *g_Tasks;
@property (nonatomic, retain) NSString *g_TasksHash;
@property (nonatomic, retain) NSMutableDictionary *g_AppHashes;
@property (nonatomic, retain) NSString *g_agentPid;
// SWDist
@property (nonatomic, retain) NSMutableArray    *g_SWDistTasks;
@property (nonatomic, retain) NSString          *g_SWDistTasksHash;
@property (nonatomic, retain) NSString          *g_SWDistTasksJSONHash;

+ (MPCatalog *)sharedInstance;
- (NSString *)collectCUUIDFromHost;
- (NSDictionary *)systemVersionDictionary;
- (NSString *)getHostSerialNumber;
- (NSDictionary *)getOSInfo;

@end
