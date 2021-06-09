//
//  MPAgent.h
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

#import <Foundation/Foundation.h>

@interface MPAgent : NSObject
{
	NSDictionary		*g_OSVers;
	NSString			*g_cuuid;
	NSString			*g_serialNo;
	NSString			*g_agentVer;
	NSMutableDictionary	*g_AppHashes;
    NSString			*g_agentPid;
    NSString			*g_hostName;

    // SWDist
    NSMutableArray		*g_SWDistTasks;
	NSString			*g_SWDistTasksHash;
    NSString			*g_SWDistTasksJSONHash;
}

@property (nonatomic, strong) NSDictionary          *g_OSVers;
@property (nonatomic, strong) NSString              *g_cuuid;
@property (nonatomic, strong) NSString              *g_serialNo;
@property (nonatomic, strong) NSString              *g_agentVer;
@property (nonatomic, strong) NSMutableDictionary   *g_AppHashes;
@property (nonatomic, strong) NSString              *g_agentPid;
@property (nonatomic, strong) NSString              *g_hostName;
// SWDist
@property (nonatomic, strong) NSMutableArray        *g_SWDistTasks;
@property (nonatomic, strong) NSString              *g_SWDistTasksHash;
@property (nonatomic, strong) NSString              *g_SWDistTasksJSONHash;

+ (MPAgent *)sharedInstance;

- (NSString *)collectCUUIDFromHost;
- (NSDictionary *)systemVersionDictionary;
- (NSString *)getHostSerialNumber;
- (NSDictionary *)getOSInfo;
- (NSString *)clientKey;

- (BOOL)postAgentHasBeenInstalled;

@end
