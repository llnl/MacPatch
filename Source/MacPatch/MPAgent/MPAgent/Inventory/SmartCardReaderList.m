//
//  SmartCardReaderList.m
//  MPAgent
/*
 Copyright (c) 2018, Lawrence Livermore National Security, LLC.
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
			qlerror(@"%@",exception);
		}
		
		while (mszReaders[++i] != 0) ;
	}
	
	SCardReleaseContext(hContext);
	return (NSArray *)readers;
}

@end
