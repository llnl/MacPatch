//
//  MPAppUsage.m
/*
 Copyright (c) 2024, Lawrence Livermore National Security, LLC.
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

#import "MPAppUsage.h"
#import "MacPatch.h"

@interface MPAppUsage ()
{
    FMDatabase *db;
}

@end

@implementation MPAppUsage
@synthesize dbPath;

-(id)init
{
	self = [super init];
	if (self) {
		NSString *appSupportPath = [[NSFileManager defaultManager] applicationSupportDirectoryForDomain:NSSystemDomainMask];
		NSString *appSupportFile = [appSupportPath stringByAppendingPathComponent:@"mpapp.db"];
		dbPath = [NSString stringWithString:appSupportFile];
		[self initAndPrepDB];
	}
	return self;
}


-(int)initAndPrepDB
{
	db = [[FMDatabase alloc] initWithPath:dbPath];
	if (![db open]) 
    {
		logit(lcl_vError,@"Could not open db.");
        return 1;
    }
	
	[db executeUpdate:@"create table appUsage (app_name text, app_path text, app_version text, last_launched text, times_launched INTEGER)"];
	return 0;
}

-(void)cleanDB
{
	[db beginTransaction];
    [db executeUpdate:@"Delete from appUsage where app_version IS NULL"];
	[db commit];
}

-(void)insertLaunchDataForApp:(NSString *)aAppName appPath:(NSString *)aAppPath appVersion:(NSString *)aAppVer
{
	int noTimesLaunched = [self numberOfPreviousLaunchesForApp:aAppName appPath:aAppPath appVersion:aAppVer];
	[db beginTransaction];
	if (noTimesLaunched == 0) {
		[db executeUpdate:@"insert into appUsage (app_name,app_path,app_version,last_launched,times_launched) values (?,?,?,current_timestamp,1)",aAppName,aAppPath,aAppVer];
	} else {
		noTimesLaunched++;
		[db executeUpdate:@"update appUsage set times_launched = ?, last_launched = current_timestamp WHERE app_name = ? AND app_path = ? AND app_version = ?" , [NSNumber numberWithInt:noTimesLaunched], aAppName, aAppPath, aAppVer];
	}
	[db commit];
}

-(int)numberOfPreviousLaunchesForApp:(NSString *)aAppName appPath:(NSString *)aAppPath appVersion:(NSString *)aAppVer
{
	int result = 0;
	result = [db intForQuery:@"select times_launched FROM appUsage WHERE app_name = ? AND app_path = ? AND app_version = ?", aAppName, aAppPath, aAppVer];
	return result;
}


@end
