//
//  MPDefaults.h
/*
 Copyright (c) 2021, Lawrence Livermore National Security, LLC.
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

/*	MPDefaults, is the class to read the plist for configuration settings */

#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, MPSettingsKey) {
    kMPServers  = 0,
    kMPSettings = 1,
    kMPSUServers = 2,
    kMPTasks = 3
};

@interface MPDefaults : NSObject 
{
	NSDictionary *defaults;
	NSURL *mpwsURL;
    NSString *plist;
}

- (id)initWithPlist:(NSString *)sPlistPath;
- (id)initWithDictionary:(NSDictionary *)aDictionary;

- (NSDictionary *)defaults;
- (void)setDefaults:(NSDictionary *)aDefaults;

- (void)readPlist:(NSString *)aPlist;
- (id)readPlist:(NSString *)aPlist objectForKey:(NSString *)aKey;
- (NSDictionary *)readDefaults;


// MP 3.1
- (id)initUsingSettings;

- (void)updateSettingsData:(NSDictionary *)settingsRevisons;

- (NSInteger)revisionForKey:(MPSettingsKey)key;
- (id)settingsForKey:(MPSettingsKey)key;

@end
