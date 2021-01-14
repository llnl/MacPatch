//
//  SPSmartCard.m
//  MPAgent
//
//  Created by Charles Heizer on 9/1/20.
//  Copyright © 2020 LLNL. All rights reserved.
//

#import "SPSmartCard.h"

@implementation SPSmartCard

- (NSArray *)parseXMLFile:(NSString *)xmlFile
{
	NSArray *result = nil;
	NSFileManager *dm = [NSFileManager defaultManager];
	if ([dm fileExistsAtPath:xmlFile] == NO)
	{
		logit(lcl_vError,@"Inventory cache file was not found. Data will not be parsed.");
		return result;
	}

	NSArray *spX = [NSArray arrayWithContentsOfFile:xmlFile];
	NSDictionary *rootDict = [spX objectAtIndex:0];
	NSArray *itemsArray = [rootDict objectForKey:@"_items"];
	if (itemsArray.count >= 2) {
		result = itemsArray.copy;
	}
	return result;
}

- (NSArray *)getSPSmartCardReaders:(NSArray *)spData
{
	NSMutableArray *result = [NSMutableArray new];
	for (NSDictionary *d in spData)
	{
		if ([d[@"_name"] isEqualToString:@"READERS"])
		{
			for (NSString *k in d.allKeys)
			{
				if ([k hasPrefix:@"#"]) {
					[result addObject:@{@"readerID": k, @"reader": d[k]}];
				}
			}
		}
	}
	return result.copy;
}

- (NSArray *)getSPSmartCardReaderDrivers:(NSArray *)spData
{
	NSMutableArray *result = [NSMutableArray new];
	for (NSDictionary *d in spData)
	{
		if ([d[@"_name"] isEqualToString:@"READERS_DRIVERS"])
		{
			for (NSString *k in d.allKeys)
			{
				if ([k hasPrefix:@"#"]) {
					[result addObject:@{@"readerID": k, @"driver": d[k]}];
				}
			}
		}
	}
	return result.copy;
}

- (NSArray *)getSPSmartCardTokendDrivers:(NSArray *)spData
{
	NSMutableArray *result = [NSMutableArray new];
	for (NSDictionary *d in spData)
	{
		if ([d[@"_name"] isEqualToString:@"TOKEN_DRIVERS"])
		{
			for (NSString *k in d.allKeys)
			{
				if ([k hasPrefix:@"#"]) {
					[result addObject:@{@"readerID": k, @"driver": d[k]}];
				}
			}
		}
	}
	return result.copy;
}

- (NSArray *)getSPSmartCardDrivers:(NSArray *)spData
{
	NSMutableArray *result = [NSMutableArray new];
	for (NSDictionary *d in spData)
	{
		if ([d[@"_name"] isEqualToString:@"SMARTCARDS_DRIVERS"])
		{
			for (NSString *k in d.allKeys)
			{
				if ([k hasPrefix:@"#"]) {
					[result addObject:@{@"readerID": k, @"driver": d[k]}];
				}
			}
		}
	}
	return result.copy;
}

@end
