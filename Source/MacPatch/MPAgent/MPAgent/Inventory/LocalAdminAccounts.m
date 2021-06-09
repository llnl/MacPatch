//
//  LocalAdminAccounts.m
//  MPAgent
//
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

#import "LocalAdminAccounts.h"
#import "MPUsersAndGroups.h"

@implementation LocalAdminAccounts


- (NSArray *)gatherLocalAdminAccounts
{
	NSMutableArray *accounts = [NSMutableArray array];
	MPUsersAndGroups *m = [[MPUsersAndGroups alloc] init];
	NSArray *localGroups = [m getLocalGroups:NULL];
	
	// Admin Group is #80, no need to process after 80 is found
	NSDictionary *result;
	for (NSDictionary *d in localGroups) {
		if ([[d objectForKey:@"GroupID"] integerValue] == 80) {
			result = d;
			break;
		}
	}
	
	NSDictionary *account;
	NSArray *_idList = [[result objectForKey:@"GroupMembers"] componentsSeparatedByString:@","];
	for (NSString *gid in _idList)
	{
		account = [m getInfoForUserGUID:gid];
		if (account != nil) {
			[accounts addObject:account];
		}
	}
	
	return (NSArray *)accounts;
}

@end
