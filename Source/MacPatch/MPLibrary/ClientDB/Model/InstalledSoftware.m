//
//  InstalledSoftware.m
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

#import "InstalledSoftware.h"

@implementation InstalledSoftware

+ (NSString *)tableName
{
	return @"installed_software";
}

+ (NSString *)createTableSQL
{
	return @"CREATE TABLE IF NOT EXISTS installed_software ("
		   @"id INTEGER PRIMARY KEY AUTOINCREMENT, "
		   @"name TEXT NOT NULL, "
		   @"suuid TEXT, "
		   @"tuuid TEXT NOT NULL UNIQUE, "
		   @"uninstall TEXT, "
		   @"has_uninstall INTEGER DEFAULT 0, "
		   @"json_data TEXT, "
		   @"install_date REAL NOT NULL DEFAULT (julianday('now')))";
}

- (instancetype)init
{
	self = [super init];
	if (self) {
		self.install_date = [NSDate date];
		self.has_uninstall = @(0);
	}
	return self;
}

@end
