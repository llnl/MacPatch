//
//  MPWebServices.h
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

@interface MPWebServices : NSObject

@property (nonatomic, strong) NSString *clientKey;

// Registration
- (BOOL)getIsClientAgentRegistered:(NSError **)err;
- (NSDictionary *)getServerPubKey:(NSError **)err;
- (BOOL)getIsValidPubKeyHash:(NSString *)aHash error:(NSError **)err;
- (NSDictionary *)getRegisterAgent:(NSString *)aRegKey hostName:(NSString *)hostName clientKey:(NSString *)clientKey error:(NSError **)err;
- (NSDictionary *)registerAgentUsingPayload:(NSDictionary *)regPayload regKey:(NSString *)aRegKey error:(NSError **)err;

// New REST calls
- (NSData *)getRequestWithURIforREST:(NSString *)aURI error:(NSError **)err;
- (NSData *)postRequestWithURIforREST:(NSString *)aURI body:(id)aBody error:(NSError **)err;
- (id)returnRequestWithType:(NSData *)requestData resultType:(NSString *)resultType error:(NSError **)err;

- (int)postOSMigrationStatusNew:(NSString *)aStatus label:(NSString *)Label migrationID:(NSString *)migrationID error:(NSError **)err;

#pragma mark Convience methods
- (NSDictionary *)getPatchGroupContent:(NSError **)err;
- (NSString *)getPatchGroupContentRev:(NSError **)err;
- (NSDictionary *)getCriticalPatchGroupContent:(NSError **)err;
- (NSDictionary *)getMPServerList:(NSError **)err;
- (NSDictionary *)getMPServerListVersion:(NSString *)aVersion listid:(NSString *)aListID error:(NSError **)err;
- (BOOL)postDataMgrData:(NSString *)aDataMgrJSON error:(NSError **)err;
- (NSArray *)getCustomPatchScanList:(NSError **)err;
- (NSArray *)getCustomPatchScanListWithSeverity:(NSString *)aSeverity error:(NSError **)err;
- (BOOL)postClientScanDataWithType:(NSArray *)scanData type:(NSInteger)aType error:(NSError **)err;
- (NSDictionary *)getAgentUpdates:(NSString *)curAppVersion build:(NSString *)curBuildVersion error:(NSError **)err;
- (NSDictionary *)getAgentUpdaterUpdates:(NSString *)curAppVersion error:(NSError **)err;
- (NSDictionary *)getSUSServerList:(NSError **)err;
- (NSDictionary *)getSUSServerListVersion:(NSString *)aVersion listid:(NSString *)aListID error:(NSError **)err;
- (BOOL)clientHasInvDataInDB:(NSError **)err;
- (int)postClientHasInvData:(NSError **)err;
- (BOOL)postPatchInstallResultsToWebService:(NSString *)aPatch patchType:(NSString *)aPatchType error:(NSError **)err;
- (NSArray *)getProfileIDDataForClient:(NSError **)err;
- (id)getSWDistGroups:(NSError **)err;
- (id)getSWDistGroupsWithState:(NSString *)aState error:(NSError **)err;
- (id)getSWTasksForGroup:(NSString *)aGroupName error:(NSError **)err;
- (int)postSWInstallResults:(NSDictionary *)aParams error:(NSError **)err;
- (id)getSWTaskForID:(NSString *)aTaskID error:(NSError **)err;
- (NSString *)getHashForPluginName:(NSString *)pName pluginBunleID:(NSString *)bundleID pluginVersion:(NSString *)pVer error:(NSError **)err;

- (id)GetClientPatchStatusCount:(NSError **)err;

- (BOOL)postClientAVData:(NSDictionary *)aDict error:(NSError **)err;

- (BOOL)getAgentRegStatusWithKeyHash:(NSString *)keyHash error:(NSError **)err;
- (BOOL)postAgentReister:(NSDictionary *)aDict regKey:(NSString *)aRegKey error:(NSError **)err;

@end
