//
//  MPDefaults.m
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

#import "MPDefaults.h"
#import "Constants.h"

#undef  ql_component
#define ql_component lcl_cMPDefaults

@implementation MPDefaults

#pragma mark -
#pragma mark init

//=========================================================== 
//  init 
//=========================================================== 

- (id)init 
{
	return [self initWithPlist:AGENT_PREFS_PLIST];
}

- (id)initWithPlist:(NSString *)sPlistPath
{
	self = [super init];
	if (self) {
		qldebug(@"Reading plist from file '%@'",sPlistPath);
        [self setPlist:sPlistPath];
		[self readPlist:sPlistPath];
    }
    
    return self;
}

- (id)initWithDictionary:(NSDictionary *)aDictionary
{
	self = [super init];
	if (self) {
		[self setDefaults:aDictionary];
        [self setPlist:nil];
    }
    return self;
}


#pragma mark -
#pragma mark Getters & Setters
//=========================================================== 
//  Getters & Setters 
//=========================================================== 

- (NSDictionary *)defaults
{
    return defaults; 
}

- (void)setDefaults:(NSDictionary *)aDefaults
{
    if (defaults != aDefaults) {
        defaults = [aDefaults copy];
    }
}

- (NSString *)plist
{
    return plist;
}

- (void)setPlist:(NSString *)aPlist
{
    if (plist != aPlist) {
        plist = [aPlist copy];
    }
}

#pragma mark -
#pragma mark Class Methods
//=========================================================== 
//  methods
//=========================================================== 

- (void)readPlist:(NSString *)aPlist
{
	NSFileManager *fileManager = [NSFileManager defaultManager];
	if ([fileManager fileExistsAtPath:aPlist]) {
		NSString *error;
		NSPropertyListFormat format;
		NSData *data = [NSData dataWithContentsOfFile:aPlist];
		NSMutableDictionary *thePlist = [NSPropertyListSerialization propertyListFromData:data 
																		 mutabilityOption:NSPropertyListImmutable 
																				   format:&format 
																		 errorDescription:&error];
		if (!thePlist) {
			qlerror(@"Error reading plist from file '%@', error = '%@'",aPlist,error);
			return;
		} 
		[self setDefaults:[NSDictionary dictionaryWithDictionary:thePlist]];
	} else {
		qlerror(@"Error plist file '%@' does not exist.",aPlist);
		exit(1);
	}
    
}

- (id)readPlist:(NSString *)aPlist objectForKey:(NSString *)aKey
{
	id result;
	[self readPlist:aPlist];
	result = [[self defaults] objectForKey:aKey];
	return (id)result;
}

- (NSDictionary *)readDefaults
{
    if (plist) {
        [self readPlist:plist];
        return defaults;
    } else {
        return defaults;
    }
}

#pragma mark - MacPatch 3.1 Methods
// MP 3.1
- (id)initUsingSettings
{
    self = [super init];
    if (self) {
        
    }
    return self;
}

- (void)updateSettingsData:(NSDictionary *)settingsRevisons
{
    
}

- (NSInteger)revisionForKey:(MPSettingsKey)key
{
    return 0;
}

- (id)settingsForKey:(MPSettingsKey)key
{
    return nil;
}

@end
