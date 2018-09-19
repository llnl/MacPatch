//
//  SmartCardReaderList.m
//  MPAgent
//
//  Created by Charles Heizer on 12/7/17.
//  Copyright © 2017 LLNL. All rights reserved.
//

#import "SmartCardReaderList.h"

#import <CoreFoundation/CFPlugInCOM.h>
#include <stdio.h>
#include <stdlib.h>

#include <PCSC/winscard.h>
#include <PCSC/wintypes.h>

@implementation SmartCardReaderList

- (NSArray *)getSmartCardReaders
{
	NSMutableArray *readers = [NSMutableArray array];
	
	LONG returnVal = 0;
	SCARDCONTEXT hContext;
	DWORD dwReaders;
	
	char *mszReaders;
	const char *mszGroups;
	int i;
	
	returnVal = SCardEstablishContext(SCARD_SCOPE_SYSTEM, NULL, NULL, &hContext);
	if (returnVal != SCARD_S_SUCCESS) {
		return (NSArray *)readers;
	}
	
	mszGroups = 0;
	returnVal = SCardListReaders(hContext, mszGroups, 0, &dwReaders);
	if (returnVal != SCARD_S_SUCCESS) {
		printf("No reader found");
		return (NSArray *)readers;
	}
	
	mszReaders = (char *) malloc(sizeof(char) * dwReaders);
	returnVal = SCardListReaders(hContext, mszGroups, mszReaders, &dwReaders);
	if (returnVal != SCARD_S_SUCCESS)
	{
		SCardReleaseContext(hContext);
		return (NSArray *)readers;
	}
	
	NSString *readerName = NULL;
	for (i = 0; i < dwReaders - 1; i++)
	{
		@try {
			readerName = [NSString stringWithFormat:@"%s",&mszReaders[i]];
			[readers addObject:@{@"screader":readerName}];
			readerName = NULL;
		}
		@catch (NSException *exception) {
			NSLog(@"%@",exception);
		}
		
		while (mszReaders[++i] != 0) ;
	}
	
	SCardReleaseContext(hContext);
	return (NSArray *)readers;
}

@end
