//
//  MPBundle.m
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

#import "MPBundle.h"
#import <Foundation/Foundation.h>

#undef  ql_component
#define ql_component lcl_cMPBundle

@implementation MPBundle

#pragma mark -
#pragma mark init
//=========================================================== 
//  init 
//=========================================================== 
-(id)initWithBundleIDString:(NSString *)aBundleID; {
    self = [super init];
	
    if ( self ) {
        if ([self parseBundleIDString:aBundleID] != TRUE)
		{
			qlerror(@"Error: bundle id was not properly formatted.");	
		}
    }
	
    return self;
}

#pragma mark -
#pragma mark Getters & Setters
//=========================================================== 
//  Getters & Setters 
//=========================================================== 
- (NSString *)bundleID
{
	return bundleID;
}
- (void)setBundleID:(NSString *)aBundleID
{
	if (bundleID != aBundleID) {
        bundleID = [aBundleID copy];
    }
}

- (NSString *)bundleIDName
{
	return bundleIDName;
}
- (void)setBundleIDName:(NSString *)aBundleIDName
{
	if (bundleIDName != aBundleIDName) {
        bundleIDName = [aBundleIDName copy];
    }
}

#pragma mark -
#pragma mark Class Methods
//=========================================================== 
//  Class Methods
//=========================================================== 

-(BOOL)parseBundleIDString:(NSString *)aBundleID
{
	
	NSArray *bArray = [aBundleID componentsSeparatedByString: @";"];
	if ([bArray count] == 0) {
		qlerror(@"Error: Bundle id parsing is empty.");
		return FALSE;
	} else if ([bArray count] == 1) {
		[self setBundleID:[NSString stringWithString:[bArray objectAtIndex:0]]];
		return TRUE;
	} else if ([bArray count] == 2) {
		[self setBundleID:[NSString stringWithString:[bArray objectAtIndex:0]]];
		[self setBundleIDName:[NSString stringWithString:[bArray objectAtIndex:1]]];
		return TRUE;
	}
	
	qlerror(@"Error: reached end without knowing why?");
	return FALSE;
}

-(BOOL)queryBundleID:(NSString *)aBundleID action:(NSString *)aAction result:(NSString *)aResult
{
	BOOL result = NO;
	if ([self parseBundleIDString:aBundleID] == NO) {
		result = NO;
		goto done;
	}
		
	result = [self queryBundleID:aAction result:aResult];
	
	
done:	
	return result;
}


-(BOOL)queryBundleID:(NSString *)action result:(NSString *)aResult
{
	BOOL result = FALSE;
	
	NSString *vAction = NULL;
	vAction = [NSString stringWithString:[action uppercaseString]];
	
	// Make Sure Action is Either EXISTS or VERSION
	if ([vAction isEqualToString:@"EXISTS"] == FALSE && [vAction isEqualToString:@"VERSION"] == FALSE) {
		qlerror(@"BundleID param was not vaild.");
		result = FALSE;
		return result;
	}
	
	// Find app, refresh  app list & get filePath for bundle ID
	[[NSWorkspace sharedWorkspace] findApplications];
	NSString *bIDFilePath = NULL;
	bIDFilePath = [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:[self bundleID]];
	
	// Check for EXISTS
	if ([vAction isEqualToString:@"EXISTS"] == TRUE) {
		
		BOOL opr = YES;
		
		if ([[aResult uppercaseString] isEqualToString:@"TRUE"] || [[aResult uppercaseString] isEqualToString:@"YES"]){
			opr = YES;
		} else if ([[aResult uppercaseString] isEqualToString:@"FALSE"] || [[aResult uppercaseString] isEqualToString:@"NO"]) {
			opr = NO;
		} else {
			qlerror(@"Operator was not defined properly, operator is set to True.");
			opr = YES;
		}

		
		if ([[NSFileManager defaultManager] fileExistsAtPath:bIDFilePath] == opr) {
			result = TRUE;
			return result;
		} else {
			result = FALSE;
			return result;
		}

	}

	// Check for VERSION
	if ([vAction isEqualToString:@"VERSION"] == TRUE) {
		if ([[NSFileManager defaultManager] fileExistsAtPath:bIDFilePath] == FALSE) {
			qlinfo(@"BundleID was not found.");
			result = FALSE;
			return result;
		} else {
			NSDictionary *dict = [self getBundleIDInfo:[self bundleID]];
			NSString	*appVer = [dict objectForKey:@"CFBundleShortVersionString"];
			NSArray		*tmpRes = [aResult componentsSeparatedByString:@";"];
			NSString	*tmpVer;
			NSString	*tmpOpr = @"LT";
			
			// Parse the result param to see if a Operator is present otherwise use LT
			if ([tmpRes count] == 1) {
				tmpVer = [NSString stringWithString:[tmpRes objectAtIndex:0]];
			} else {
				tmpVer = [NSString stringWithString:[tmpRes objectAtIndex:0]];
				tmpOpr = [NSString stringWithString:[tmpRes objectAtIndex:1]];
			}

			if (appVer) {
				// Compare the version strings
				result = [self compareVersion:appVer operator:tmpOpr compareTo:tmpVer];
				return result;
			}	
		}
	}

    return result;
}

#pragma mark -
#pragma mark Class Methods
//=========================================================== 
//  Class Helper
//=========================================================== 

-(NSDictionary *)getBundleIDInfo:(NSString *)aBundleID
{
	NSMutableDictionary *resultDictTmp;
	NSDictionary		*result;
	CFURLRef			appURL;
	
	OSStatus error = 0;
	error = LSFindApplicationForInfo(kLSUnknownCreator,(__bridge CFStringRef)aBundleID, nil, (FSRef *)nil, &appURL);
	
	if (error != 0) {
		qlerror(@"Error trying to get bundle ID \"%@\". Error %d",aBundleID,(int)error);
		result = NULL;
		goto done;
	} else {
		NSDictionary *dict;
		NSBundle *bundle = [NSBundle bundleWithPath:[(__bridge NSURL*)appURL path]];
		dict = [bundle infoDictionary];
		if (dict)
		{
			resultDictTmp = [[NSMutableDictionary alloc] initWithDictionary:dict];
			[resultDictTmp setObject:[(__bridge NSURL*)appURL path] forKey:@"ApplicationPath"];
			result = [NSDictionary dictionaryWithDictionary:resultDictTmp];
			resultDictTmp = nil;
			goto done;
		} else {
			qlerror(@"Error trying to get bundle ID info for \"%@\". Error %d",aBundleID,(int)error);
			result = NULL;
			goto done;
		}
	}

	
done:
	return result;
}

-(BOOL)compareVersion:(NSString *)leftVersion operator:(NSString *)aOp compareTo:(NSString *)rightVersion
{
	BOOL fileVerPass = FALSE;
	int i;
	
	// Break version into fields (separated by '.')
	NSMutableArray *leftFields  = [[NSMutableArray alloc] initWithArray:[leftVersion  componentsSeparatedByString:@"."]];
	NSMutableArray *rightFields = [[NSMutableArray alloc] initWithArray:[rightVersion componentsSeparatedByString:@"."]];
	
	// Implict ".0" in case version doesn't have the same number of '.'
	if ([leftFields count] < [rightFields count]) {
		while ([leftFields count] != [rightFields count]) {
			[leftFields addObject:@"0"];
		}
	} else if ([leftFields count] > [rightFields count]) {
		while ([leftFields count] != [rightFields count]) {
			[rightFields addObject:@"0"];
		}
	}
	
	// Do a numeric comparison on each field
	NSComparisonResult result = NSOrderedSame;
	for(i = 0; i < [leftFields count]; i++) {
		result = [[leftFields objectAtIndex:i] compare:[rightFields objectAtIndex:i] options:NSNumericSearch];
		if (result != NSOrderedSame) {
			break;
		}
	}
	
	/*
	 * compareVersions(@"10.4",             @"10.3")             returns NSOrderedDescending (1)
	 * compareVersions(@"10.5",             @"10.5.0")           returns NSOrderedSame (0)
	 * compareVersions(@"10.4 Build 8L127", @"10.4 Build 8P135") returns NSOrderedAscending (-1)
	 */
	
	NSString *op = [NSString stringWithString:[aOp uppercaseString]];
	
	if ([op isEqualToString:@"EQ"] || [op isEqualToString:@"="] || [op isEqualToString:@"=="] ) 
	{
		if ( result == NSOrderedSame ) {
			fileVerPass = YES; goto done;
		} else {
			fileVerPass = NO; goto done;
		}
	}
	else if ([op isEqualToString:@"NEQ"] || [op isEqualToString:@"!="] || [op isEqualToString:@"=!"]) 
	{
		if ( result == NSOrderedSame ) {
			fileVerPass = NO; goto done;
		} else {
			fileVerPass = YES; goto done;
		}
		
	}
	else if ([op isEqualToString:@"LT"] || [op isEqualToString:@"<"]) 
	{
		if ( result == NSOrderedAscending ) {
			fileVerPass = YES; goto done;
		} else {
			fileVerPass = NO; goto done;
		}
	}
	else if ([op isEqualToString:@"LTE"] || [op isEqualToString:@"<="]) 
	{
		if ( result == NSOrderedAscending || result == NSOrderedSame ) {
			fileVerPass = YES; goto done;
		} else {
			fileVerPass = NO; goto done;
		}
	}
	else if ([op isEqualToString:@"GT"] || [op isEqualToString:@">"]) 
	{
		if ( result == NSOrderedDescending ) {
			fileVerPass = YES; goto done;
		} else {
			fileVerPass = NO; goto done;
		}
	}
	else if ([op isEqualToString:@"GTE"] || [op isEqualToString:@">="]) 
	{
		if ( result == NSOrderedDescending || result == NSOrderedSame ) {
			fileVerPass = YES; goto done;
		} else {
			fileVerPass = NO; goto done;
		}
	}
	
	
done:
	;
	return fileVerPass;
}

@end
