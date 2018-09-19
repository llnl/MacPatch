//
//  MPOSCheck.m
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

#import <Cocoa/Cocoa.h>
#import "MPOSCheck.h"

#undef  ql_component
#define ql_component lcl_cMPOSCheck


@interface NSApplication (SystemVersion)

- (NSArray *)osVersionOctets;

@end

@implementation NSApplication (SystemVersion)

- (NSArray *)osVersionOctets
{
    NSArray *sysVer;
    
    if (floor(NSAppKitVersionNumber) >= NSAppKitVersionNumber10_10) {
        NSOperatingSystemVersion os = [[NSProcessInfo processInfo] operatingSystemVersion];
        sysVer = @[[NSNumber numberWithInt:(int)os.majorVersion],[NSNumber numberWithInt:(int)os.minorVersion],[NSNumber numberWithInt:(int)os.patchVersion]];
    } else {
        SInt32 OSmajor, OSminor, OSrevision;
        OSErr err1 = Gestalt(gestaltSystemVersionMajor, &OSmajor);
        OSErr err2 = Gestalt(gestaltSystemVersionMinor, &OSminor);
        OSErr err3 = Gestalt(gestaltSystemVersionBugFix, &OSrevision);
        if (!err1 && !err2 && !err3)
        {
            sysVer = @[[NSNumber numberWithInt:OSmajor],[NSNumber numberWithInt:OSminor],[NSNumber numberWithInt:OSrevision]];
        }
    }
    
    return sysVer;
}

@end


@implementation MPOSCheck


- (NSArray *)curOSVerArray
{
    return curOSVerArray; 
}
- (void)setCurOSVerArray:(NSArray *)aCurOSVerArray
{
    if (curOSVerArray != aCurOSVerArray) {
        curOSVerArray = aCurOSVerArray;
    }
}

- (id)init;
{
    self = [super init];
	if (!self)
		return nil;
	
    curOSVerArray = [[NSApplication sharedApplication] osVersionOctets];
	return self;
}

-(BOOL)checkOSArch:(NSString *)osArchString
{
	BOOL result = NO;
	
#if defined __i386__ || defined __x86_64__
	NSString *procType = @"X86";
#elif defined __ppc__ || defined __ppc64__
	NSString *procType = @"PPC";
#elif defined __arm__
	NSString *procType = @"ARM";
#else
	NSString *procType = @"Unknown Architecture";
#endif
	
	NSArray *reqOSArchArray = [osArchString componentsSeparatedByString:@","];
	for (int i = 0;i < [reqOSArchArray count]; i++) {
		if ([[[[reqOSArchArray objectAtIndex:i] uppercaseString] trim] isEqualToString:procType] == TRUE) 
		{
			result = TRUE;
			goto done;
		}
	}
	
done:	
	return result;
}

-(BOOL)checkOSType:(NSString *)osTypeString
{
	BOOL osTypePass	= FALSE;
	NSDictionary *sysInfo = [self getSWVers];
	NSString *osTypeVal = [sysInfo objectForKey:@"ProductName"];
	// 					   
	NSArray *reqOSTypeArray = [osTypeString componentsSeparatedByString:@","];
	for (int i = 0;i < [reqOSTypeArray count]; i++) {
		if ([[[reqOSTypeArray objectAtIndex:i] trim] isEqualToString:osTypeVal] == TRUE) 
		{
			osTypePass = TRUE;
			goto done;
		}
	}
	
done:	
	return osTypePass;
}

-(BOOL)checkOSVer:(NSString *)osVersString
{
	BOOL osTypePass	= FALSE;
	
	// if it's just * then pass, it's a wildcard for all
	if ([osVersString isEqualToString:@"*"] == TRUE)
	{
		osTypePass = TRUE; 
		return osTypePass;
	}
	
	// else, lets create out array
	NSArray *reqOSVerArray = [osVersString componentsSeparatedByString:@","];
	if ([reqOSVerArray count] <= 0) {
		qlerror(@"Error: Required OS Version String Check was malformed. Unable to parse.");
		osTypePass = FALSE; 
		return osTypePass;
	}

	int osMatchCount = 0;
	for(int i = 0; i<[reqOSVerArray count];i++)
	{
		if ([[reqOSVerArray objectAtIndex:i] isEqualToString:[curOSVerArray componentsJoinedByString:@"."]] == TRUE)
		{	
			osTypePass = TRUE; 
			return osTypePass;
		}
        // Test for +, which means greater than 
        if ([[reqOSVerArray objectAtIndex:i] containsString:@"+"] == TRUE) 
        {
            NSArray *_allowOctsPlus = [[reqOSVerArray objectAtIndex:i] componentsSeparatedByString:@"."];
            for (int y = 0; y < [_allowOctsPlus count]; y++)
            {
                if ([[_allowOctsPlus objectAtIndex:y] containsString:@"+"] == TRUE) {
                    if ([[curOSVerArray objectAtIndex:y] intValue] >= [[_allowOctsPlus objectAtIndex:y] intValue]) {
                        osTypePass = TRUE;
                        return osTypePass;
                    }
                } else {
                    if ([[curOSVerArray objectAtIndex:y] intValue] == [[_allowOctsPlus objectAtIndex:y] intValue]) {
                        continue;
                    } else if ([[curOSVerArray objectAtIndex:y] intValue] < [[_allowOctsPlus objectAtIndex:y] intValue]) {
                        osTypePass = FALSE;
                        return osTypePass;
                    } else {
                        osTypePass = TRUE;
                        return osTypePass;
                    }
                }
            }
        }
		if ([[reqOSVerArray objectAtIndex:i] containsString:@"*"] == TRUE)
		{	
			osMatchCount = 0;
			NSArray *_allowOctsStar = [[reqOSVerArray objectAtIndex:i] componentsSeparatedByString:@"."];
            qldebug(@"_allowOctsStar: %@",_allowOctsStar);
			for (int x=0;x<[_allowOctsStar count]; x++)
			{	
				if ([[curOSVerArray objectAtIndex:x] intValue] == [[_allowOctsStar objectAtIndex:x] intValue] || [[_allowOctsStar objectAtIndex:x] isEqualToString:@"*"] == TRUE)
				{	
					osMatchCount++;		
				}
			}
			int octets = (int)[_allowOctsStar count];
			if (osMatchCount == octets)
			{		
				osTypePass = TRUE;
				return osTypePass;
			} else {
				qldebug(@"OS octets is %d and matched octets is %d. They must match to pass.",octets,osMatchCount);
			}
		}
	}

    return osTypePass;
}

-(NSDictionary *)getSWVers
{
	NSDictionary *results = NULL;
	NSString *clientVerPath = @"/System/Library/CoreServices/SystemVersion.plist";
	NSString *serverVerPath = @"/System/Library/CoreServices/ServerVersion.plist";
	
	if ([[NSFileManager defaultManager] fileExistsAtPath:serverVerPath] == TRUE) {
		results = [NSDictionary dictionaryWithContentsOfFile:serverVerPath];
	} else {
		if ([[NSFileManager defaultManager] fileExistsAtPath:clientVerPath] == TRUE) {
			results = [NSDictionary dictionaryWithContentsOfFile:clientVerPath];
		}
	}
	
	return results;
}

@end
