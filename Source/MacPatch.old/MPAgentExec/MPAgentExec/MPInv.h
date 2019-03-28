//
//  MPInv.h
/*
 Copyright (c) 2013, Lawrence Livermore National Security, LLC.
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

@interface MPInv : NSObject 
{    
	NSArray		*invResults;
	NSString	*cUUID;
}
// Getters * Setters
@property (nonatomic, strong) NSArray *invResults;
@property (nonatomic, strong) NSString *cUUID;

// Main SP Inventory
- (BOOL)validateCollectionType:(NSString *)aColType;
- (int)collectInventoryData;
- (int)collectCustomData;
- (int)collectInventoryDataForType:(NSString *)aSPType;
- (NSString *)getProfileData:(NSString *)profileType error:(NSError **)error;

// Audit Data Collection
- (int)collectAuditTypeData;
- (NSString *)replaceXMLVariables:(NSString *)aFilePath;
- (BOOL)validateDataMgrXML:(NSString *)aFilePath;


// Parse Profiler Data
- (NSArray *)parseHardwareOverview:(NSString *)fileToParse;
- (NSArray *)parseNetworkData:(NSString *)fileToParse;
- (NSArray *)parseSystemOverviewData:(NSString *)fileToParse;
- (NSArray *)parseApplicationsData:(NSString *)fileToParse;
- (NSArray *)parseApplicationsDataFromXML:(NSString *)xmlFileToParse;
- (NSArray *)parseFrameworksDataFromXML:(NSString *)xmlFileToParse;

// Custom
- (NSDictionary *)emptyDirectoryServicesDataRecord;
- (NSArray *)parseDirectoryServicesData;
- (NSArray *)parseDirectoryServicesDataForLion;
- (NSArray *)parseDirectoryServicesDataForPreLion;
- (NSArray *)parseInternetPlugins;
- (NSArray *)parseAppUsageData;
- (NSArray *)parseLocalClientTasks;
- (NSString *)readKeyFromFile:(NSString *)aPath key:(NSString *)aKey error:(NSError **)err;
- (NSArray *)parseLocalDiskInfo;
- (NSArray *)parseLocalUsers;
- (NSArray *)parseLocalGroups;
- (NSArray *)parseFileVaultInfo;
- (NSArray *)parsePowerManagmentInfo;
- (NSArray *)parseBatteryInfo;
- (NSArray *)parseConfigProfilesInfo;
- (NSArray *)parseAppStoreData;
- (NSArray *)parseAgentServerInfo;
- (NSArray *)parseAgentServerList;

// Helpers for Directory Data from Daniel
- (NSDictionary *)stringToDict:(NSString *)theString theDelimiter:(NSString *)theDelimiter;
- (BOOL)sendResultsToWebService:(NSString *)aDataMgrXML;


@end
