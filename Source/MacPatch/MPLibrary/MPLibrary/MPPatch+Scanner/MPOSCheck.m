//
//  MPOSCheck.m
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

#import <Cocoa/Cocoa.h>
#import "MPOSCheck.h"
#include "TargetConditionals.h"

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
    // CEH: Allow all right now.
	BOOL result = YES;
    
#if TARGET_OS_OSX
  // Put CPU-independent macOS code here.
  #if TARGET_CPU_ARM64
    // Put 64-bit Apple silicon macOS code here.
    qldebug(@"checkOSArch: TARGET_CPU_ARM64");
    NSString *procType = @"ARM";
  #elif TARGET_CPU_X86_64
    qldebug(@"checkOSArch: TARGET_CPU_X86_64");
    NSString *procType = @"X86";
  #else
    NSString *procType = @"Unknown Architecture";
  #endif
#elif TARGET_OS_MACCATALYST
   // Put Mac Catalyst-specific code here.
    qldebug(@"checkOSArch: TARGET_OS_MACCATALYST");
    NSString *procType = @"Unknown Architecture";
#elif TARGET_OS_IOS
  // Put iOS-specific code here.
    qldebug(@"checkOSArch: TARGET_OS_IOS");
    NSString *procType = @"Unknown Architecture";
#else
    NSString *procType = @"Unknown Architecture";
#endif
    
	NSArray *reqOSArchArray = [osArchString componentsSeparatedByString:@","];
	for (int i = 0;i < [reqOSArchArray count]; i++) {
		NSString *_arch = [NSString stringWithString:[[reqOSArchArray objectAtIndex:i] uppercaseString]];
		_arch = [_arch stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if ([_arch isEqualToString:procType] == TRUE)
		{
			result = TRUE;
			goto done;
		}
	}
	
done:	
	return result;
}

-(BOOL)checkOSArchPreBS:(NSString *)osArchString
{
    BOOL result = NO;
    
#if defined __i386__ || defined __x86_64__
    NSString *procType = @"X86";
#elif defined __ppc__ || defined __ppc64__
    NSString *procType = @"PPC";
#elif defined __arm__
    NSString *procType = @"ARM";
#elif defined __APPLE__
    NSString *procType = @"ARM";
#else
    NSString *procType = @"Unknown Architecture";
#endif
    
    qlinfo(@"checkOSArch: %@",procType);
    
    NSArray *reqOSArchArray = [osArchString componentsSeparatedByString:@","];
    for (int i = 0;i < [reqOSArchArray count]; i++) {
        NSString *_arch = [NSString stringWithString:[[reqOSArchArray objectAtIndex:i] uppercaseString]];
        _arch = [_arch stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([_arch isEqualToString:procType] == TRUE)
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
    // CEH: Disable for now, not really needed since there is no server any more
    return TRUE;
    
	BOOL osTypePass	= FALSE;
	NSDictionary *sysInfo = [self getSWVers];
	NSString *osTypeVal = [[sysInfo objectForKey:@"ProductName"] uppercaseString];

    if ([osTypeVal isEqualToString:@"MACOS"]) {
        osTypeVal = @"MAC OS X";
    }

	NSArray *reqOSTypeArray = [osTypeString componentsSeparatedByString:@","];
	for (int i = 0;i < [reqOSTypeArray count]; i++) {
		NSString *_osType = [NSString stringWithString:[[reqOSTypeArray objectAtIndex:i] uppercaseString]];
		_osType = [_osType stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if ([_osType isEqualToString:osTypeVal] == TRUE)
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
	NSString *curOSVer = [curOSVerArray componentsJoinedByString:@"."];
	qldebug(@"curOSVer: %@",curOSVer);
	
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

	for(int i = 0; i<[reqOSVerArray count];i++)
	{
		NSString *_reqOSVer = [NSString stringWithString:[reqOSVerArray objectAtIndex:i]];
		qldebug(@"_reqOSVer: %@",_reqOSVer);
		
		if ([_reqOSVer isEqualToString:curOSVer] == TRUE)
		{	
			osTypePass = TRUE; 
			break;
		}
        // Test for +, which means greater than 
        if ([_reqOSVer containsString:@"+"] == TRUE)
        {
			int foundOctMatch = 0;
			//NSString *findStr = [_reqOSVer stringByReplacingOccurrencesOfString:@"+" withString:@""];
			NSArray *findOcts = [_reqOSVer componentsSeparatedByString:@"."];
			
			/* Example
			 Cur OS = 10.11.3
			 Req OS = 10.10+
			 Loop:
			 	(Cur)10 >= (Req)10 [= foundOctMatch++]
			 	(Cur)11 >= (Req)10 [= foundOctMatch++]
			 
			 If foundOctMatch == findOcts.count = PASS
			*/
			
			for (int y = 0; y < [findOcts count]; y++)
			{
				if ([[curOSVerArray objectAtIndex:y] intValue] >= [[findOcts objectAtIndex:y] intValue])
				{
					foundOctMatch++;
				}
			}
			
			if (foundOctMatch >= findOcts.count) {
				osTypePass = TRUE;
				break; // Break out of outer loop
			}
        }
		if ([_reqOSVer containsString:@"*"] == TRUE)
		{
			NSString *findStr = [_reqOSVer stringByReplacingOccurrencesOfString:@"*" withString:@""];
			qldebug(@"If curOSVer(%@) containsString:(%@)",curOSVer,findStr);
			if ([curOSVer containsString:findStr])
			{
				qldebug(@"Found");
				osTypePass = TRUE;
				break;
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
