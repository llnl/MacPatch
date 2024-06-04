//
//  Profiles.m
/*
 Copyright (c) 2024, Lawrence Livermore National Security, LLC.
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

#import "Profiles.h"
#import "MPSettings.h"
#import "MacPatch.h"

static NSString *kMPProfilesData = @"Data/gov.llnl.mp.custom.profiles.plist";

@interface Profiles (Private)

- (void)scanAndInstallPofiles;
- (NSArray *)retrieveProfileIDData;
- (NSArray *)readLocalProfileData;
- (NSArray *)readMPInstalledProfiles;
- (NSArray *)readMPInstalledProfileData;
- (NSString *)writeProfileToDisk:(NSString *)aData;
- (BOOL)installProfile:(NSString *)aProfilePath;
- (BOOL)removeProfile:(NSString *)aProfileIdentifier;
- (void)recordProfileInstallToDisk:(NSDictionary *)aProfile;
- (BOOL)profileIsInstalledOnDisk:(NSString *)profileID installedProfiles:(NSArray *)localProfiles;

@end


@implementation Profiles

@synthesize isExecuting;
@synthesize isFinished;
@synthesize taskName;

- (id)init
{
    self = [super init];
	if (self) {
		self.isExecuting = NO;
        self.isFinished  = NO;
		settings	= [MPSettings sharedInstance];
		fm          = [NSFileManager defaultManager];
	}

	return self;
}

- (BOOL)isConcurrent
{
    return YES;
}

- (void)cancel
{
    [self finish];
}

- (void)finish
{
    [self willChangeValueForKey:@"isFinished"];
    [self willChangeValueForKey:@"isExecuting"];
    self.isExecuting = NO;
    self.isFinished = YES;
    [self didChangeValueForKey:@"isExecuting"];
    [self didChangeValueForKey:@"isFinished"];
}

- (void)start
{
    if ([self isCancelled]) {
        [self willChangeValueForKey:@"isFinished"];
        self.isFinished = YES;
        [self didChangeValueForKey:@"isFinished"];
    } else {
        [self willChangeValueForKey:@"isExecuting"];
		[self performSelectorInBackground:@selector(main) withObject:nil];
        self.isExecuting = YES;
        [self didChangeValueForKey:@"isExecuting"];
    }
}

- (void)main
{
	@try {
        if (@available(macOS 11.0, *)) {
            qlinfo(@"Profile installs are not supported on MacOS 11 and higher.");
        } else {
            if ([fm fileExistsAtPath:MP_PROVISION_BEGIN] && ![fm fileExistsAtPath:MP_PROVISION_DONE]) {
                qlinfo(@"Profile install operations is deferred while provisioning.");
            } else {
                [self scanAndInstallPofiles];
            }
        }
	}
	@catch (NSException * e) {
		logit(lcl_vError,@"[NSException]: %@",e);
	}
	[self finish];
}

- (void)scanAndInstallPofiles
{
	@autoreleasepool
    {
        NSArray *profiles = [self retrieveProfileIDData];
        if (!profiles) {
            qlinfo(@"No profile data.");
            return;
        } else {
            qldebug(@"MP Profiles:%@",profiles);
        }
        
        NSMutableArray *profileIdentities 	= [[NSMutableArray alloc] init];
        NSMutableArray *profilesToRemove 	= [[NSMutableArray alloc] init];
        NSArray *installedProfiles 			= [self readMPInstalledProfileData]; // returns an array of recorded installed profile id's
        NSArray *installedProfilesRaw 		= [self readMPInstalledProfiles]; // returns and array of complete install profile dicts
        NSArray *localProfiles 				= [self readLocalProfileData];

        // Install Profiles
        for (NSDictionary *p in profiles)
        {
            qldebug(@"API Profile ID: %@" , [p objectForKey:@"profileIdentifier"]);
            qldebug(@"API Profile Rev: %@", [p objectForKey:@"rev"]);
            
            if ([p objectForKey:@"profileIdentifier"] == (id)[NSNull null] || [[p objectForKey:@"profileIdentifier"] length] == 0 ) {
                NSString *pName = @"NA";
                if ([p objectForKey:@"id"]) {
                    pName = [p objectForKey:@"id"];
                }
                qlerror(@"profileIdentifier is null. Skipping %@",pName);
                qldebug(@"%@",p);
                continue;
            }
            
            BOOL needsInstall = NO;
            BOOL needsUpdate = NO;
            BOOL foundInMPInstalledArray = NO;
            
            BOOL profileIDIsInstalled = [self profileIsInstalledOnDisk:[p objectForKey:@"profileIdentifier"] installedProfiles:localProfiles];
            if (!profileIDIsInstalled)
			{
                qlinfo(@"Profile %@ needs to be installed.",[p objectForKey:@"profileIdentifier"]);
                needsInstall = YES;
            }
			else
			{
                // Profile ID Is installed
                // See if it needs an update
                for (NSDictionary *mpInstProfile in installedProfilesRaw)
                {
                    // Check if profile has been recorded as installed by MP
                    // Note: we can not update if we dont record a revision number
                    if ([[mpInstProfile objectForKey:@"profileIdentifier"] isEqualToString:[p objectForKey:@"profileIdentifier"]])
                    {
                        foundInMPInstalledArray = YES;
                        
                        int currentProfileRev = [[mpInstProfile objectForKey:@"rev"] intValue];
                        int wsProfileRev = [[p objectForKey:@"rev"] intValue];
                        qldebug(@"CurrentProfileRev: %d <> APIProfileRev: %d",currentProfileRev,wsProfileRev);
                        if (currentProfileRev < wsProfileRev) {
                            qlinfo(@"ProfileIdentifier: %@ needs an update.",[p objectForKey:@"profileIdentifier"]);
                            needsUpdate = YES;
                        }
                    }
                }
                
                if (foundInMPInstalledArray == NO)
				{
                    qlinfo(@"Profile %@ needs to be installed. Was not found to be installed via MP.",[p objectForKey:@"profileIdentifier"]);
                    [self recordProfileInstallToDisk:p];
                }
                
                if ([p objectForKey:@"data"])
                {
                    if (needsUpdate == YES) {
                        // In order to update, remove first
                        [self removeProfile:[p objectForKey:@"profileIdentifier"]];
                        needsInstall = YES;
                    }
                }
            }
            
            // Install Needed Profile
            if (needsInstall == YES)
            {
				BOOL passProfileCriteria = YES;
				// Check if profile has criteria that needs to be run on the client
				// If it passes the criteria it will be installed
				if ([p objectForKey:@"criteria"])
				{
					NSArray *criArr = [p objectForKey:@"criteria"];
					if (criArr.count >= 1) {
						passProfileCriteria = [self evaluateProfileCriteria:criArr];
					}
				}
				
				if (passProfileCriteria)
				{
					NSString *profileOnDisk = [self writeProfileToDisk:[p objectForKey:@"data"]];
					if (!profileOnDisk) {
						qlerror(@"Error, unable to install profile %@",[p objectForKey:@"profileIdentifier"]);
					}
					if ([self installProfile:profileOnDisk] == NO) {
						qlerror(@"Error, install profile %@ failed.",[p objectForKey:@"profileIdentifier"]);
					} else {
						qlinfo(@"Profile, %@ was installed.",[p objectForKey:@"profileIdentifier"]);
						[fm removeItemAtPath:profileOnDisk error:NULL];
						[self recordProfileInstallToDisk:p];
					}
				}
            }
        }
        
        // Build Profiles to Remove Array
        for (NSDictionary *rp in profiles)
        {
            if ([rp objectForKey:@"profileIdentifier"]) {
                [profileIdentities addObject:[rp objectForKey:@"profileIdentifier"]];
            }
        }
        
        [profilesToRemove addObjectsFromArray:installedProfiles];
        [profilesToRemove removeObjectsInArray:profileIdentities];
        
        // Remove Old Profiles
        if (profilesToRemove.count >= 1)
        {
            qldebug(@"Profiles to remove %@",profilesToRemove);
            for (NSString *profileID in profilesToRemove)
            {
                if ([self removeProfile:profileID]) {
                    qlinfo(@"Profile %@ was removed.",profileID);
                } else {
                    qlerror(@"Error, profile %@ was not removed.",profileID);
                }
            }
        }
        
        // Refresh MCX
        NSArray *cmdArgs = [NSArray arrayWithObjects:@"-n",@"root", nil];
        [[NSTask launchedTaskWithLaunchPath:@"/usr/bin/mcxrefresh" arguments:cmdArgs] waitUntilExit];
    }
}

- (NSArray *)retrieveProfileIDData
{
    NSArray *data = nil;
    MPHTTPRequest *req;
    MPWSResult *result;
    
    req = [[MPHTTPRequest alloc] init];
    
    NSString *urlPath = [NSString stringWithFormat:@"/api/v2/client/profiles/%@",settings.ccuid];
    result = [req runSyncGET:urlPath];
    
    if (result.statusCode >= 200 && result.statusCode <= 299) {
        logit(lcl_vInfo,@"Agent Settings data, returned true.");
        data = result.result[@"data"];
    } else {
        logit(lcl_vError,@"Agent Settings data, returned false.");
        logit(lcl_vDebug,@"%@",result.toDictionary);
        return nil;
    }
    
    return data;
}

- (NSArray *)readLocalProfileData
{
    NSString *fileName = [NSString stringWithFormat: @"%.0f.%@", [NSDate timeIntervalSinceReferenceDate] * 1000.0, @"plist"];
    NSString *filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];

    // Write Profile Data To Plist
    NSArray *cmdArgs = [NSArray arrayWithObjects:@"-P",@"-o",filePath, nil];
    [[NSTask launchedTaskWithLaunchPath:@"/usr/bin/profiles" arguments:cmdArgs] waitUntilExit];

    if (![fm fileExistsAtPath:filePath]) {
        qlerror(@"Could not find/read profile data from %@",filePath);
        if ([fm fileExistsAtPath:@"/tmp/foo.plist"]) {
            filePath = @"/tmp/foo.plist";
        } else {
            return nil;
        }
    } else {
        qldebug(@"Reading profiles file %@",filePath);
    }

    NSDictionary *profileDict = [NSDictionary dictionaryWithContentsOfFile:filePath];
    NSMutableArray *profileIDs = [[NSMutableArray alloc] init];

    if ([profileDict objectForKey:@"_computerlevel"])
    {
        for (NSDictionary *p in [profileDict objectForKey:@"_computerlevel"])
        {
            qldebug(@"Adding:\n%@",[p objectForKey:@"ProfileIdentifier"]);
            [profileIDs addObject:p];
        }
    } else {
        qlinfo(@"No computerlevel profiles.");
        return nil;
    }
    return [NSArray arrayWithArray:[profileIDs copy]];
}

- (NSArray *)readMPInstalledProfiles
{
    NSString *filePath = [MP_ROOT_CLIENT stringByAppendingPathComponent:kMPProfilesData];
    NSDictionary *mpProfileDict = [NSDictionary dictionaryWithContentsOfFile:filePath];

    if ([mpProfileDict objectForKey:@"installed"])
    {
        return [mpProfileDict objectForKey:@"installed"];
    }

    return nil;
}

- (NSArray *)readMPInstalledProfileData
{
    NSString *filePath = [MP_ROOT_CLIENT stringByAppendingPathComponent:kMPProfilesData];
    NSDictionary *mpProfileDict = [NSDictionary dictionaryWithContentsOfFile:filePath];
    NSMutableArray *profileIDs = [[NSMutableArray alloc] init];

    if ([mpProfileDict objectForKey:@"installed"])
    {
        for (NSDictionary *p in [mpProfileDict objectForKey:@"installed"])
        {
            if ([p objectForKey:@"remove"]) {
                if ([[p objectForKey:@"remove"] integerValue] != 1) {
                    continue;
                }
            }
            [profileIDs addObject:[p objectForKey:@"profileIdentifier"]];
        }
    } else {
        return nil;
    }

    // Quick Clean Up
    return [NSArray arrayWithArray:profileIDs];
}

- (NSString *)writeProfileToDisk:(NSString *)aData
{
    NSString *fileName = [NSString stringWithFormat: @"%.0f.%@", [NSDate timeIntervalSinceReferenceDate] * 1000.0, @"mobileconfig"];
    NSString *filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];
    // Fix Bug, on 10.8 systems. initWithBase64EncodedString on 10.9 and higher
    // NSData *pData = [[NSData alloc] initWithBase64EncodedString:aData options:0];
    NSData *pData = [NSData dataFromBase64String:aData];
    NSError *err = nil;
    [pData writeToFile:filePath options:NSDataWritingAtomic error:&err];
    if (err) {
        qlerror(@"Error, %@",err.localizedDescription);
        return nil;
    }

    return filePath;
}

- (BOOL)installProfile:(NSString *)aProfilePath
{
    // Write Profile Data To Plist
    NSTask *task = [NSTask launchedTaskWithLaunchPath:@"/usr/bin/profiles" arguments:@[@"-I",@"-F",aProfilePath]];
    [task waitUntilExit];

    int result = task.terminationStatus;
    if (result == 0) {
        return YES;
    } else {
        return NO;
    }
}

- (BOOL)removeProfile:(NSString *)aProfileIdentifier
{
    // Write Profile Data To Plist
    NSTask *task = [NSTask launchedTaskWithLaunchPath:@"/usr/bin/profiles" arguments:@[@"-R",@"-p",aProfileIdentifier]];
    [task waitUntilExit];

    int result = task.terminationStatus;
    if (result == 0) {
        [self removeProfileInstallFromDisk:aProfileIdentifier];
        return YES;
    } else {
        return NO;
    }
}

- (void)recordProfileInstallToDisk:(NSDictionary *)aProfile
{
    NSString *pID = nil;
    if ([aProfile objectForKey:@"id"])
    {
        pID = [aProfile objectForKey:@"id"];
        qlinfo(@"pID %@",pID);
    }

    NSMutableArray *_installedProfiles = [[NSMutableArray alloc] init]; // Read
    
    NSString *filePath = [MP_ROOT_CLIENT stringByAppendingPathComponent:kMPProfilesData];
    qlinfo(@"Recording profile install for %@",[aProfile objectForKey:@"profileIdentifier"]);
    
    NSMutableDictionary *profileData = [NSMutableDictionary dictionaryWithContentsOfFile:filePath];
    if (!profileData) {
        profileData = [NSMutableDictionary dictionary];
    }

    if ([profileData objectForKey:@"installed"])
    {
        _installedProfiles = [NSMutableArray arrayWithArray:[profileData objectForKey:@"installed"]];
    }
    
    BOOL isAdded = NO;
    for (NSDictionary *iProfile in [profileData objectForKey:@"installed"]) {
        if ([[[iProfile objectForKey:@"id"] uppercaseString] isEqualToString:[pID uppercaseString]]) {
            isAdded = YES;
            break;
        }
    }
    
    if (!isAdded) {
        [_installedProfiles addObject:(NSDictionary *)aProfile];
    }
    

    [@{@"installed":(NSArray *)_installedProfiles} writeToFile:filePath atomically:NO];
    if (![fm fileExistsAtPath:filePath])
    {
        qlerror(@"%@ file was not found.",filePath);
    }
}

- (void)removeProfileInstallFromDisk:(NSString *)aProfileID
{
    NSMutableArray *_installedProfiles = [[NSMutableArray alloc] init];
    NSString *filePath = [MP_ROOT_CLIENT stringByAppendingPathComponent:kMPProfilesData];
    qlinfo(@"Remove recorded profile ID (%@) for disk.",aProfileID);
    
    NSMutableDictionary *profileData = [NSMutableDictionary dictionaryWithContentsOfFile:filePath];
    if ([profileData objectForKey:@"installed"])
    {
        for (NSDictionary *x in [profileData objectForKey:@"installed"]) {
            if ([aProfileID isEqualToString:[x objectForKey:@"profileIdentifier"]]) {
                continue;
            } else {
                [_installedProfiles addObject:x];
            }
        }
    }
    
    [@{@"installed":(NSArray *)_installedProfiles} writeToFile:filePath atomically:NO];
    if (![fm fileExistsAtPath:filePath])
    {
        qlerror(@"%@ file was not found.",filePath);
    }
}

- (BOOL)profileIsInstalledOnDisk:(NSString *)profileID installedProfiles:(NSArray *)localProfiles
{
    @try {
        if (profileID == (id)[NSNull null] || profileID.length == 0 ) {
            qlerror(@"profileID is null. ");
            return NO;
        }
        
        BOOL result = NO;
        
        for (NSDictionary *p in localProfiles)
        {
            if ([p objectForKey:@"ProfileIdentifier"]) {
                qldebug(@"%@ == %@",[p objectForKey:@"ProfileIdentifier"], profileID);
                
                if ([[[p objectForKey:@"ProfileIdentifier"] uppercaseString] isEqualToString:[profileID uppercaseString]]) {
                    result = YES;
                    break;
                }
            }
        }
        return result;
    } @catch (NSException *exception) {
        qlerror(@"%@",exception);
        return NO;
    }
}

- (NSDictionary *)getProfileFromID:(NSString*)profileID profilesArray:(NSArray *)profiles
{
    NSDictionary *result = nil;
    for (NSDictionary *p in profiles)
    {
        qlinfo(@"profileID: %@",profileID);
        qlinfo(@"p: %@",p[@"ProfileIdentifier"]);
        if ([[p objectForKey:@"ProfileIdentifier"] isEqualToString:profileID])
        {
            result = [p copy];
            break;
        }
    }
    return result;
}

- (BOOL)evaluateProfileCriteria:(NSArray *)criteria
{
	int count = 0;
	
	MPBundle	*mpbndl;
	MPFileCheck	*mpfile;
	MPScript	*mpscript;
	
	// Loop vars
	NSArray *qryArr;
	
	int i = 0;
	for (i=0; i < criteria.count; i++)
	{
		NSDictionary *criteriaObj = [criteria objectAtIndex:i];
		NSString *criString = [criteriaObj[@"type_data"] decodeBase64AsString];
		qryArr = [criString componentsSeparatedByString:@"@" escapeString:@"@@"];

		/*
		 typeQuery  	 = [qryArr objectAtIndex:1];
		 typeQueryString = [qryArr objectAtIndex:2];
		 typeResult		 = [qryArr objectAtIndex:3];
		 */
		
		if ([@"BundleID" isEqualToString:criteriaObj[@"type"]])
		{
			mpbndl = [[MPBundle alloc] init];
			if ([qryArr count] != 3) {
				qlerror(@"Error, not enough args for patch query entry.");
				break;
			}

			if ([mpbndl queryBundleID:qryArr[1] action:qryArr[0] result:qryArr[2]])
			{
				qlinfo(@"BundleID=TRUE: %@",[qryArr objectAtIndex:1]);
				count++;
			}
			else
			{
				qlinfo(@"BundleID=FALSE: %@",[qryArr objectAtIndex:1]);
			}
		}
		
		if ([@"File" isEqualToString:criteriaObj[@"type"]])
		{
			mpfile = [[MPFileCheck alloc] init];
			if ([qryArr count] != 3) {
				qlerror(@"Error, not enough args for patch query entry.");
				break;
			}
			
			if ([mpfile queryFile:qryArr[1] action:qryArr[0] param:qryArr[2]])
			{
				qlinfo(@"File=TRUE: %@",qryArr[1]);
				count++;
			}
			else
			{
				qlinfo(@"File=FALSE: %@",qryArr[1]);
			}
		}
		
		if ([@"Script" isEqualToString:criteriaObj[@"type"]])
		{
			mpscript = [[MPScript alloc] init];
			if ([qryArr count] > 1)
			{
				qlerror(@"Error, too many args. Sript will not be run.");
				break;
			}
			
			if ([mpscript runScript:qryArr[0]])
			{
				qlinfo(@"SCRIPT=TRUE");
				count++;
			}
			else
			{
				qlinfo(@"SCRIPT=FALSE");
			}
		}
	}
	
	if (count == criteria.count)
	{
		return YES;
	} else {
		return NO;
	}
}

@end
