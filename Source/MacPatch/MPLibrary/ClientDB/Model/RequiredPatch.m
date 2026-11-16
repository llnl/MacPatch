//
//  RequiredPatch.m
//  MPLibrary
/*
 Copyright (c) 2026, Lawrence Livermore National Security, LLC.
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

#import "RequiredPatch.h"

@implementation RequiredPatch

+ (NSString *)tableName
{
	return @"required_patches";
}

+ (NSString *)createTableSQL
{
	return @"CREATE TABLE IF NOT EXISTS required_patches ("
		   @"id INTEGER PRIMARY KEY AUTOINCREMENT, "
		   @"type TEXT NOT NULL, "
		   @"patch_id TEXT NOT NULL UNIQUE, "
		   @"patch TEXT NOT NULL, "
		   @"patch_version TEXT, "
		   @"patch_reboot INTEGER DEFAULT 0, "
		   @"patch_data BLOB, "
		   @"patch_scandate REAL NOT NULL DEFAULT (julianday('now')))";
}

- (instancetype)init
{
	self = [super init];
	if (self) {
		self.patch_scandate = [NSDate date];
		self.patch_reboot = @(0);
	}
	return self;
}

@end
