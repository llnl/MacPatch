//
//  MPClientDatabase.m
//  MPLibrary
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


#import "MPClientDatabase.h"
#import "FMDatabase.h"
#import "FMXDatabaseManager.h"
#import "DBMigration.h"

// Models
#import "DBInstalledSoftware.h"
#import "DBRequiredPatches.h"

@implementation MPClientDatabase

- (id)init
{
	self = [super init];
	if (self)
	{
		[self setupDatabase];
	}
	return self;
}

- (void)setupDatabase
{
	FMXDatabaseManager *manager = [FMXDatabaseManager sharedManager];
	DBMigration *migration = [[DBMigration alloc] init];
	[manager registerDefaultDatabaseWithPath:MP_AGENT_DB migration:migration];
	FMDatabase *db = [manager defaultDatabase];
	[db open];
	[db close];
}

#pragma mark - Software

/**
Record the install of a software task.

@param swTask - Software Task Dictionary
@return BOOL
*/
- (BOOL)recordSoftwareInstall:(NSDictionary *)swTask
{
	BOOL result = NO;
	@try
	{
		FMXDatabaseManager *manager = [FMXDatabaseManager sharedManager];
		DBMigration *migration = [[DBMigration alloc] init];
		[manager registerDefaultDatabaseWithPath:MP_AGENT_DB migration:migration];
		
		FMDatabase *db = [manager defaultDatabase];
		[db open];
		
		DBInstalledSoftware *sw;
		NSInteger count = [DBInstalledSoftware countWhere:@"tuuid = :tuuid" parameters:@{@"tuuid": swTask[@"id"]}];
		if (count >= 1)
		{
			// Update Record
			sw = (DBInstalledSoftware *)[DBInstalledSoftware modelWhere:@"tuuid = :tuuid" parameters:@{@"tuuid": swTask[@"id"]}];
			if (swTask[@"Software"][@"sw_uninstall"]) {
				sw.has_uninstall = @(1);
				sw.uninstall = swTask[@"Software"][@"sw_uninstall"];
			} else {
				sw.has_uninstall = @(0);
				sw.uninstall = @"";
			}
			
			sw.install_date = [NSDate date];
			NSError *error = nil;
			NSData *jsonData = [NSJSONSerialization dataWithJSONObject:swTask options:0 error:&error];
			if (!jsonData) {
				qlerror(@"%s: error: %@", __func__, error.localizedDescription);
				sw.json_data = @"[]";
			} else {
				sw.json_data = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
			}
		}
		else
		{
			// Add Record
			sw = [[DBInstalledSoftware alloc] init];
			sw.name = swTask[@"name"];
			sw.tuuid = swTask[@"id"];
			sw.suuid = swTask[@"Software"][@"sid"];
			if (swTask[@"Software"][@"sw_uninstall"]) {
				sw.has_uninstall = @(1);
				sw.uninstall = swTask[@"Software"][@"sw_uninstall"];
			} else {
				sw.has_uninstall = @(0);
				sw.uninstall = @"";
			}
			
			sw.install_date = [NSDate date];
			NSError *error = nil;
			NSData *jsonData = [NSJSONSerialization dataWithJSONObject:swTask options:0 error:&error];
			if (!jsonData) {
				qlerror(@"%s: error: %@", __func__, error.localizedDescription);
				sw.json_data = @"[]";
			} else {
				sw.json_data = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
			}
		}
		
		[sw save];
		[db close];
		
		result = YES;
		[self recordHistory:kMPSoftwareType name:swTask[@"name"] uuid:swTask[@"id"] action:kMPInstallAction result:0 errorMsg:NULL];
		return result;
	}
	@catch (NSException *exception) {
		qlerror(@"%@",exception);
		return result;
	}
	return result;
}

/**
 Record the uninstall of a software task.
 
 @param swTaskName - SW Task Name
 @param swTaskID - SW Task ID
 @return BOOL
 */
- (BOOL)recordSoftwareUninstall:(NSString *)swTaskName taskID:(NSString *)swTaskID
{
	[self recordHistory:kMPSoftwareType name:swTaskName uuid:swTaskID action:kMPUnInstallAction result:0 errorMsg:NULL];
	[self removeSoftwareTaskFormInstalledSoftware:swTaskID];
	return YES;
}

/**
 Return an array of all software tasks installed
 
 @return NSArray
 */
- (NSArray *)retrieveInstalledSoftwareTasks
{
	NSMutableArray *swTasks = [NSMutableArray new];
	@try
	{
		FMXDatabaseManager *manager = [FMXDatabaseManager sharedManager];
		[manager registerDefaultDatabaseWithPath:MP_AGENT_DB migration:nil];
		FMDatabase *db = [manager defaultDatabase];
		[db open];
		
		// Query all records
		NSArray *records = [[DBInstalledSoftware query] allRecords];
		qldebug(@"Installed Software tasks found %lu.",(unsigned long)records.count);
		
		for (DBInstalledSoftware *row in records) {
			[swTasks addObject:row.tuuid];
		}
		
		[db close];
		return [swTasks copy];
	}
	@catch (NSException *exception) {
		qlerror(@"%@",exception);
	}
	
	return [swTasks copy];
}

/**
 Method answers if a software task is installed.
 
 @param tuuid - Software task id
 @return BOOL
 */
- (BOOL)isSoftwareTaskInstalled:(NSString *)swTaskID
{
	BOOL result = NO;
	@try
	{
		FMXDatabaseManager *manager = [FMXDatabaseManager sharedManager];
		[manager registerDefaultDatabaseWithPath:MP_AGENT_DB migration:nil];
		FMDatabase *db = [manager defaultDatabase];
		[db open];
		
		NSInteger count = [DBInstalledSoftware countWhere:@"tuuid = :tuuid" parameters:@{@"tuuid": swTaskID}];
		if (count >= 1) {
			result = YES;
		}
		[db close];
		
		return result;
	} @catch (NSException *exception) {
		qlerror(@"%@",exception);
		return result;
	}
}

#pragma mark - Patching

/**
 Record the insatll of a patch
 
 @param patch - NSDictionary
 @return BOOL
 */
- (BOOL)recordPatchInstall:(NSDictionary *)patch
{
	BOOL result = NO;
	@try
	{
		NSString *_patch = patch[@"patch"];
		NSString *_patchID;
		NSString *_type;
		if ([patch[@"type"] isEqualToString:@"Apple"]) {
			_patchID = patch[@"patch"];
			_type = @"Apple";
		} else {
			_patchID = patch[@"patch_id"];
			_type = @"Third";
		}
		
		result = [self recordHistory:kMPPatchType name:_patch uuid:_patchID action:kMPInstallAction result:0 errorMsg:NULL];
		[self removeRequiredPatch:_type patchID:_patchID patch:_patch];
		qldebug(@"%@ patch install was added to local db.",_patch);
	}
	@catch (NSException *exception)
	{
		qlerror(@"%@",exception);
	}
	
	return result;
}

// Patching
// Add required patch to database table to manage state.
- (BOOL)addRequiredPatch:(NSDictionary *)patch
{
	BOOL result = NO;
	@try
	{
		qlinfo(@"addRequiredPatch: %@",patch);
		
		NSNumber *patchReboot = @(0);
		NSString *patchVersion = @"0";
		NSString *patchID = [patch[@"type"] isEqualToString:@"Apple"] ? patch[@"patch"] : patch[@"patch_id"];
		
		if ([patch[@"restart"] isEqualToString:@"Yes"]) patchReboot = @(1);
		if (![patch[@"version"] isKindOfClass:[NSNull class]]) patchVersion = patch[@"version"];
		
		FMXDatabaseManager *manager = [FMXDatabaseManager sharedManager];
		[manager registerDefaultDatabaseWithPath:MP_AGENT_DB migration:nil];
		FMDatabase *db = [manager defaultDatabase];
		[db open];
		
		DBRequiredPatches *rp = [[DBRequiredPatches alloc] init];
		qlinfo(@"rp.type = %@;",patch[@"type"]);
		rp.type = patch[@"type"];
		qlinfo(@"rp.patchID = %@;",patchID);
		rp.patch_id = patchID;
		qlinfo(@"rp.patch = %@;",patch[@"patch"]);
		rp.patch = patch[@"patch"];
		qlinfo(@"rp.patchVersion = %@;",patchVersion);
		rp.patch_version = patchVersion;
		qlinfo(@"rp.patchReboot = %d;",(int)patchReboot);
		rp.patch_reboot = patchReboot;
		rp.patch_data = [NSKeyedArchiver archivedDataWithRootObject:patch];
		rp.patch_scandate = [NSDate date];
		
		[rp save];
		[db close];
		result = YES;
		return result;
	}
	@catch (NSException *exception)
	{
		qlerror(@"%@",exception);
	}
	return result;
}

// Patching
// After patch has been installed the record is removed from database table of required patches.
- (BOOL)removeRequiredPatch:(NSString *)type patchID:(NSString *)patchID patch:(NSString *)patch
{
	BOOL result = NO;
	@try
	{
		qlinfo(@"RemoveRequiredPatch: %@, %@, %@", type,patchID,patch);
		FMXDatabaseManager *manager = [FMXDatabaseManager sharedManager];
		[manager registerDefaultDatabaseWithPath:MP_AGENT_DB migration:nil];
		FMDatabase *db = [manager defaultDatabase];
		[db open];
		
		[db executeUpdate:@"DELETE FROM required_patches WHERE type = ? AND patch_id = ? AND patch = ?", type, patchID, patch];
		if ([db lastErrorCode] != 0) {
			qlerror(@"Error, unable to find patch id %@ to remove record.", patchID);
			qlerror(@"Error %d: %@", [db lastErrorCode], [db lastErrorMessage]);
		} else {
			result = YES;
		}

		[db close];
		return result;
	}
	@catch (NSException *exception) {
		qlerror(@"%@",exception);
	}
	
	return result;
}

- (NSArray *)retrieveRequiredPatches
{
	NSMutableArray *patches = [NSMutableArray new];
	@try
	{
		FMXDatabaseManager *manager = [FMXDatabaseManager sharedManager];
		[manager registerDefaultDatabaseWithPath:MP_AGENT_DB migration:nil];
		FMDatabase *db = [manager defaultDatabase];
		[db open];
		
		// Query all records
		NSArray *records = [[DBRequiredPatches query] allRecords];
		qldebug(@"Required patches found %lu.",(unsigned long)records.count);
		
		for (DBInstalledSoftware *row in records) {
			[patches addObject:row.tuuid];
		}
		
		[db close];
		return [patches copy];
	}
	@catch (NSException *exception) {
		qlerror(@"%@",exception);
	}
	
	return [patches copy];
}

/**
 Clear all required patches from database table. This is
 done prior to adding new found patches after a scan.
 
 @return BOOL
 */
- (BOOL)clearRequiredPatches
{
	BOOL result = NO;
	@try
	{
		qlinfo(@"Clearing required patches.");
		FMXDatabaseManager *manager = [FMXDatabaseManager sharedManager];
		[manager registerDefaultDatabaseWithPath:MP_AGENT_DB migration:nil];
		FMDatabase *db = [manager defaultDatabase];
		[db open];
		[db executeUpdate:@"Delete FROM required_patches;"];
		//[db executeQueryWithFormat:@"Delete FROM required_patches;"];
		//[db commit];
		[db close];
		result = YES;
		return result;
	}
	@catch (NSException *exception)
	{
		qlerror(@"%@",exception);
	}
	return result;
}


#pragma mark - History

/**
 Record a action in the history table. This is done for software installs and
 uninstalls. It's also done for patch installs.
 
 @param hstType - History Type
 @param aName - Name
 @param aUUID - Type ID PUUID or TUUID
 @param aAction - Action type (install or remove)
 @param code - Action return code
 @param aErrMsg - If, error message
 @return BOOL
 */
- (BOOL)recordHistory:(DBHistoryType)hstType name:(NSString *)aName uuid:(NSString *)aUUID
			   action:(DBHistoryAction)aAction result:(NSInteger)code errorMsg:(NSString * _Nullable)aErrMsg
{
	@try
	{
		FMXDatabaseManager *manager = [FMXDatabaseManager sharedManager];
		[manager registerDefaultDatabaseWithPath:MP_AGENT_DB migration:nil];
		FMDatabase *db = [manager defaultDatabase];
		[db open];
		
		NSDate *d = [NSDate date];
		
		DBHistory *hst = [[DBHistory alloc] init];
		hst.type = [NSNumber numberWithInt:(int)hstType];
		hst.name = aName;
		hst.uuid = aUUID;
		NSString *_action = (aAction == kMPInstallAction) ? @"Install" : @"Uninstall";
		hst.action = _action;
		hst.result_code = [NSNumber numberWithInt:(int)code];
		if (aErrMsg != NULL) {
			hst.error_msg = aErrMsg;
		}
		hst.cdate = d;
		
		[hst save];
		[db close];
		return YES;
	}
	@catch (NSException *exception)
	{
		qlerror(@"%@",exception);
		return NO;
	}
}

#pragma mark - Private

// Private

/**
 Private Method
 This method removes the installed record from the client software table.
 This method is private since history should be recorded prior to removing.
 Public Method: - (BOOL)recordSoftwareUninstall:(NSString *)swTaskName taskID:(NSString *)swTaskID;

 @param tuuid - SW Task ID
 @return BOOL
 */
- (BOOL)removeSoftwareTaskFormInstalledSoftware:(NSString *)tuuid
{
	BOOL result = NO;
	@try
	{
		FMXDatabaseManager *manager = [FMXDatabaseManager sharedManager];
		[manager registerDefaultDatabaseWithPath:MP_AGENT_DB migration:nil];
		FMDatabase *db = [manager defaultDatabase];
		[db open];
		
		DBInstalledSoftware *sw;
		NSInteger count = [DBInstalledSoftware countWhere:@"tuuid = :tuuid" parameters:@{@"tuuid": tuuid}];
		if (count >= 1)
		{
			// Delete Record
			sw = (DBInstalledSoftware *)[DBInstalledSoftware modelWhere:@"tuuid = :tuuid" parameters:@{@"tuuid": tuuid}];
			[sw delete];
			result = YES;
		} else {
			qlerror(@"Error, unable to find task id %@ to remove install record.", tuuid);
		}
		
		[db close];
		return result;
	}
	@catch (NSException *exception) {
		qlerror(@"%@",exception);
		return result;
	}
	
	return result;
}

@end
