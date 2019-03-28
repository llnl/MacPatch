//
//  MPLog.m
/*
 Copyright (c) 2017, Lawrence Livermore National Security, LLC.
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

#import "MPLog.h"


@implementation MPLog

+ (void)setupLogging:(NSString *)aFilePath level:(_lcl_level_t)aLogLevel
{
	[LCLLogFile setPath:aFilePath];
    lcl_configure_by_name("*", aLogLevel);
}

+ (void)changeLogLevel:(_lcl_level_t)aLogLevel
{
	lcl_configure_by_name("*", aLogLevel);
}

+ (void)appendToLogFile:(BOOL)aAppend
{
	[LCLLogFile setAppendsToExistingLogFile:aAppend];
}

+ (void)MirrorMessagesToStdErr:(BOOL)aMirror
{
	if (aMirror) {
		[LCLLogFile setMirrorsToStdErr:aMirror];
	}	
}


@end
