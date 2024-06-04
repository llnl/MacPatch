//
//  NSMetadataQuery+Synchronous.m
//  TestPercent
//
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

#import "NSMetadataQuery+Synchronous.h"

@implementation NSMetadataQuery (Synchronous)

- (NSArray *)resultsForSearchString:(NSString *)searchString
{
	// search everywhere
	return [self resultsForSearchString:searchString inFolders:nil];
}

- (NSArray *)resultsForSearchString:(NSString *)searchString inFolders:(NSSet *)paths
{
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(doneSearching:) name:NSMetadataQueryDidFinishGatheringNotification object:nil];
	NSPredicate *search = [NSPredicate predicateWithFormat:searchString];
	[self setPredicate:search];
	if (![paths isEqual:nil]) {
		NSMutableArray *pathURLs = [NSMutableArray array];
		for (NSString *path in paths) {
			NSURL *pathURL = [NSURL fileURLWithPath:path];
			[pathURLs addObject:pathURL];
		}
		[self setSearchScopes:pathURLs];
	}
	if ([self startQuery]) {
		CFRunLoopRun();
		[[NSNotificationCenter defaultCenter] removeObserver:self name:NSMetadataQueryDidFinishGatheringNotification object:nil];
		return [self results];
	} else {
		[[NSNotificationCenter defaultCenter] removeObserver:self name:NSMetadataQueryDidFinishGatheringNotification object:nil];
		qlerror(@"query failed to start: %@", searchString);
	}
	return nil;
}

- (void)doneSearching:(NSNotification *)note
{
	[self stopQuery];
	CFRunLoopStop(CFRunLoopGetCurrent());
}


@end
