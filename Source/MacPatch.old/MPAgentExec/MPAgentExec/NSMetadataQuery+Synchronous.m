//
//  NSMetadataQuery+Synchronous.m
//  TestPercent
//
//  Created by Heizer, Charles on 7/30/14.
//  Copyright (c) 2014 Lawrence Livermore National Laboratory. All rights reserved.
//

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
		NSLog(@"query failed to start: %@", searchString);
	}
	return nil;
}

- (void)doneSearching:(NSNotification *)note
{
	[self stopQuery];
	CFRunLoopStop(CFRunLoopGetCurrent());
}


@end
