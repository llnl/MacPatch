//
//  MPConfigProfiles.m
//  MPLibrary
/*
 Copyright (c) 2023, Lawrence Livermore National Security, LLC.
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


#import "MPConfigProfiles.h"
#import "ConfigProfile.h"
#include <unistd.h>

@interface MPConfigProfiles ()

@property (nonatomic, strong) NSDictionary *profileData;

@end

@implementation MPConfigProfiles

- (NSArray *)readProfileStoreReturnAsConfigProfile
{
	unsigned int myuid = getuid();
	if (myuid != 0) {
		qlinfo(@"Reading profiles requires root priviledges.");
		return nil;
	}
	
	NSFileManager *fm = [NSFileManager defaultManager];
	
	NSString *fileName = [NSString stringWithFormat: @"%.0f.%@", [NSDate timeIntervalSinceReferenceDate] * 1000.0, @"plist"];
	//NSString *filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];
	NSString *filePath = [@"/private/tmp" stringByAppendingPathComponent:fileName];
	
	// Write Profile Data To Plist
	NSArray *cmdArgs = [NSArray arrayWithObjects:@"-P",@"-o",filePath, nil];
	[[NSTask launchedTaskWithLaunchPath:@"/usr/bin/profiles" arguments:cmdArgs] waitUntilExit];
	
	if (![fm fileExistsAtPath:filePath]) {
		qlerror(@"Could not find/read profile data from %@",filePath);
		return nil;
	} else {
		qldebug(@"Reading profiles file %@",filePath);
	}
	
	self.profileData = [NSDictionary dictionaryWithContentsOfFile:filePath];
	NSMutableArray *profiles = [[NSMutableArray alloc] init];
	
	if ([self.profileData objectForKey:@"_computerlevel"])
	{
		for (NSDictionary *p in [self.profileData objectForKey:@"_computerlevel"])
		{
			ConfigProfile *cp = [[ConfigProfile alloc] initWithDictionary:p];
			[profiles addObject:[cp copy]];
		}
	} else {
		qlinfo(@"No computerlevel profiles.");
		return nil;
	}
	
	return [profiles copy];
}

- (NSArray *)readProfileStoreFromFileReturnAsConfigProfile:(NSString *)profileStorePath
{
	NSFileManager *fm = [NSFileManager defaultManager];
	
	if (![fm fileExistsAtPath:profileStorePath]) {
		qlerror(@"Could not find/read profile data from %@",profileStorePath);
		return nil;
	} else {
		qldebug(@"Reading profiles file %@",profileStorePath);
	}
	
	self.profileData = [NSDictionary dictionaryWithContentsOfFile:profileStorePath];
	NSMutableArray *profiles = [[NSMutableArray alloc] init];
	
	if ([self.profileData objectForKey:@"_computerlevel"])
	{
		for (NSDictionary *p in [self.profileData objectForKey:@"_computerlevel"])
		{
			ConfigProfile *cp = [[ConfigProfile alloc] initWithDictionary:p];
			[profiles addObject:[cp copy]];
		}
	} else {
		qlinfo(@"No computerlevel profiles.");
		return nil;
	}
	
	return [profiles copy];
}

@end
