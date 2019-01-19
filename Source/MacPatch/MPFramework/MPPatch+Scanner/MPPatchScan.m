//
//  MPPatchScan.m
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

#import "MPPatchScan.h"
#import "MPDataMgr.h"
#import "MPOSCheck.h"
#import "MPBundle.h"
#import "MPFileCheck.h"
#import "MPScript.h"
#include <unistd.h>
#import "MPSettings.h"

#undef  ql_component
#define ql_component lcl_cMPPatchScan

@interface MPPatchScan ()
{
    MPSettings *settings;
}

@end

@implementation MPPatchScan

@synthesize delegate;

- (BOOL)useDistributedNotification
{
    return useDistributedNotification;
}

- (void)setUseDistributedNotification:(BOOL)flag
{
    useDistributedNotification = flag;
}

#pragma mark -

- (id)init;
{
    self = [super init];
	if (self)
    {
        [self setUseDistributedNotification:NO];
        settings = [MPSettings sharedInstance];
    }
	return self;
}

-(NSArray *)scanForPatches
{
	NSArray         *resultArr = nil;
	NSMutableArray  *patchesNeeded = [[NSMutableArray alloc] init];
	NSDictionary    *notifyInfo;
	notifyInfo = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:0] forKey:@"patchesNeeded"];
	
	/*
	 1. Get Scan List
	 2. Scan for patches
	 3. Post patches needed
	 */ 
	
	// 1. Get the list
	NSDictionary *tmpDict;
	NSArray *customPatches;
	customPatches = [self retrieveCustomPatchScanList];
    if ([customPatches count] == 0) {
        qlwarning(@"Custom patch scan list is empty, no custom patches will be scaned for.");
		return resultArr;
    }
	// 2. Scan the host
	NSMutableDictionary *patch;
	BOOL result = NO;
	int i = 0;
    
	for(i=0; i<[customPatches count]; i++)
    {
		tmpDict = [NSDictionary dictionaryWithDictionary:[customPatches objectAtIndex:i]];
		qldebug(@"Patch Dict: %@",tmpDict);
		qlinfo(@"*******************");
		qlinfo(@"Scanning for %@(%@)",tmpDict[@"patch_name"], tmpDict[@"patch_ver"]);
        
        NSString *statusData = [@"Scanning for " stringByAppendingFormat:@"%@(%@)", tmpDict[@"patch_name"], tmpDict[@"patch_ver"]];
        [delegate patchScan:self didReciveStatusData:statusData];
		[self sendNotificationTo:@"ScanForNotification" userInfo:tmpDict];
		
		[NSThread sleepForTimeInterval:0.1];
		
		result = [self scanHostForPatch:tmpDict];
		if (result == YES) {
			patch = [[NSMutableDictionary alloc] init];
            @try
            {
                [patch setObject:@"Third" forKey:@"type"];
                [patch setObject:tmpDict[@"patch_name"] forKey:@"patch"];
                [patch setObject:tmpDict[@"patch_ver"] forKey:@"version"];
                [patch setObject:[NSString stringWithFormat:@"%@(%@)",tmpDict[@"patch_name"],tmpDict[@"patch_ver"]] forKey:@"description"];
                [patch setObject:@"0" forKey:@"size"];
                [patch setObject:@"Y" forKey:@"recommended"];
                [patch setObject:tmpDict[@"patch_reboot"] forKey:@"restart"];
                [patch setObject:tmpDict[@"puuid"] forKey:@"patch_id"];
                [patch setObject:tmpDict[@"bundle_id"] forKey:@"bundleID"];
                [patchesNeeded addObject:patch];
            }
            @catch (NSException *exception)
            {
                qlerror("%@\n%@",exception,tmpDict);
            }
			patch = nil;
		}
	}
	
    // 3. Post patches needed to web service
    NSError *wsErr = nil;
    MPRESTfull *mprest = [[MPRESTfull alloc] init];
    
    NSString *urlPath = [@"/api/v1/client/patch/scan/2" stringByAppendingPathComponent:settings.ccuid];
    BOOL rest_result = [mprest postDataToWS:urlPath data:@{@"rows":patchesNeeded} error:&wsErr];
    if (rest_result)
    {
        logit(lcl_vInfo,@"[MPPatchScan][scanForPatches]: Data post to web service (%@), returned true.", urlPath);
        logit(lcl_vDebug,@"Data post to web service (%@), returned true.", urlPath);
        notifyInfo = @{@"patchesNeeded":[NSNumber numberWithInt:(int)[patchesNeeded count]]};
    }
    else
    {
        logit(lcl_vError,@"Data post to web service (%@), returned false.", urlPath);
    }
    
	[delegate patchScan:self didReciveStatusData:@"Custom patch scan completed."];
	[self sendNotificationTo:@"ScanForNotificationFinished" userInfo:notifyInfo];
	return [NSArray arrayWithArray:patchesNeeded];
}

-(NSArray *)scanForPatchesWithbundleID:(NSString *)aBundleID
{
    NSArray *resultArr = nil;
	NSMutableArray *patchesNeeded = [[NSMutableArray alloc] init];
	NSDictionary *notifyInfo;
	notifyInfo = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:0] forKey:@"patchesNeeded"];
	
	/*
	 1. Get Scan List
	 2. Scan for patches
	 3. Post patches needed
	 */ 
	
	// 1. Get the list
	NSDictionary *tmpDict;
	NSArray *customPatches = [NSArray array];
	NSArray *customPatchesFull;
	customPatchesFull = [self retrieveCustomPatchScanList];
    if ([customPatchesFull count] == 0) {
        qlwarning(@"Custom patch scan list is empty, no custom patches will be scaned for.");
        return resultArr;
    }
	
	// Filter Scan list for just the required bundle id
	NSPredicate *fltr = [NSPredicate predicateWithFormat:@"(bundle_id == %@)", aBundleID];
	customPatches = [customPatchesFull filteredArrayUsingPredicate:fltr];
	
	if ([customPatches count] == 0) {
		qlwarning(@"Custom patch scan list is empty, no custom patches will be scaned for.");
		return resultArr;
	}
	
	// 2. Scan the host
	NSMutableDictionary *patch;
	BOOL result = NO;
	int i = 0;
    
    qlinfo(@"Patching bundleID: %@",aBundleID);
    
	for(i=0;i<[customPatches count];i++) {
		tmpDict = [NSDictionary dictionaryWithDictionary:[customPatches objectAtIndex:i]];
        if ([tmpDict hasKey:@"bundleID"]) {
            if ([[tmpDict objectForKey:@"bundleID"] isEqualToString:aBundleID] == NO) {
                continue;
            }
        }

		qlinfo(@"*******************");
		qldebug(@"Patch Data: %@",tmpDict);
		qlinfo(@"Scanning for %@(%@)",tmpDict[@"patch_name"],tmpDict[@"patch_ver"]);
        [delegate patchScan:self didReciveStatusData:[NSString stringWithFormat:@"Scanning for %@(%@)",tmpDict[@"patch_name"],tmpDict[@"patch_ver"]]];
		[NSThread sleepForTimeInterval:0.1];
		result = [self scanHostForPatch:tmpDict];
		if (result == YES) {
			patch = [[NSMutableDictionary alloc] init];
            @try {
                [patch setObject:tmpDict[@"patch_name"] forKey:@"patch"];
                [patch setObject:tmpDict[@"patch_ver"] forKey:@"version"];
                [patch setObject:@"Third" forKey:@"type"];
                [patch setObject:[NSString stringWithFormat:@"%@(%@)",tmpDict[@"patch_name"],tmpDict[@"patch_ver"]] forKey:@"description"];
                [patch setObject:@"0" forKey:@"size"];
                [patch setObject:@"Y" forKey:@"recommended"];
                [patch setObject:tmpDict[@"patch_reboot"] forKey:@"restart"];
                [patch setObject:tmpDict[@"puuid"] forKey:@"patch_id"];
                [patch setObject:tmpDict[@"bundle_id"] forKey:@"bundleID"];
                [patchesNeeded addObject:patch];
            }
            @catch (NSException *exception) {
                qlerror("%@",exception);
            }
			
			patch = nil;
		}
	}

    [delegate patchScan:self didReciveStatusData:@"Custom patch scan completed."];
	resultArr = [NSArray arrayWithArray:patchesNeeded];
	return resultArr;
}

/* Example Dict
 pname = "Microsoft Office 2008";
 puuid = "184D6FF9-0B2A-44AF-8942CA916C5C252A";
 pversion = "12.2.4";
 query =         (
 "OSType@Mac OS X, Mac OS X Server",
 "OSVersion@*",
 "File@EXISTS@/Applications/Microsoft Office 2008/Office/MicrosoftOffice.framework@True;EQ",
 "File@VERSION@/Applications/Microsoft Office 2008/Office/MicrosoftOffice.framework@12.2.4;LT"
 );
 reboot = No;
 */ 

-(BOOL)scanHostForPatch:(NSDictionary *)aPatch
{
	MPOSCheck	*mpos;
	MPBundle	*mpbndl;
	MPFileCheck	*mpfile;
	MPScript	*mpscript;
	
	
	BOOL result = NO;
	int count = 0;
	
	NSArray *queryArray;
	queryArray = [aPatch objectForKey:@"query"];
	
	// Loop vars
	NSArray *qryArr;
	NSString *typeQuery;
	NSString *typeQueryString;
	NSString *typeResult;
	
	qldebug(@"scanHostForPatch: %@",aPatch);
	
	int i = 0;
	for (i=0;i<[queryArray count];i++)
	{	
		qryArr = [[[queryArray objectAtIndex:i] objectForKey:@"qStr"] componentsSeparatedByString:@"@" escapeString:@"@@"];
		if ([@"OSArch" isEqualToString:[qryArr objectAtIndex:0]]) {
			mpos = [[MPOSCheck alloc] init];
			if ([mpos checkOSArch:[qryArr objectAtIndex:1]]) {
				qlinfo(@"OSArch=TRUE: %@",[qryArr objectAtIndex:1]);
				count++;
			} else {
				qlinfo(@"OSArch=FALSE: %@",[qryArr objectAtIndex:1]);
			}
		}
		
		if ([@"OSType" isEqualToString:[qryArr objectAtIndex:0]]) {
			mpos = [[MPOSCheck alloc] init];
			if ([mpos checkOSType:[qryArr objectAtIndex:1]]) {
				qlinfo(@"OSType=TRUE: %@",[qryArr objectAtIndex:1]);
				count++;
			} else {
				qlinfo(@"OSType=FALSE: %@",[qryArr objectAtIndex:1]);
			}
		}
		
		if ([@"OSVersion" isEqualToString:[qryArr objectAtIndex:0]]) {
			mpos = [[MPOSCheck alloc] init];
			if ([mpos checkOSVer:[qryArr objectAtIndex:1]]) {
				qlinfo(@"OSVersion=TRUE: %@",[qryArr objectAtIndex:1]);
				count++;
			} else {
				qlinfo(@"OSVersion=FALSE: %@",[qryArr objectAtIndex:1]);
			}
		}
		
		if ([@"BundleID" isEqualToString:[qryArr objectAtIndex:0]]) {
			mpbndl = [[MPBundle alloc] init];
			if ([qryArr count] != 4) {
				qlerror(@"Error, not enough args for patch query entry.");
				goto done;
			}
			
			/*
			 typeQuery		= [qryArr objectAtIndex:1];
			 typeQueryString = [qryArr objectAtIndex:2];
			 typeResult		= [qryArr objectAtIndex:3];
			 */
			
			if ([mpbndl queryBundleID:[qryArr objectAtIndex:2] action:[qryArr objectAtIndex:1] result:[qryArr objectAtIndex:3]]) {
				qlinfo(@"BundleID=TRUE: %@",[qryArr objectAtIndex:1]);
				count++;
			} else {
				qlinfo(@"BundleID=FALSE: %@",[qryArr objectAtIndex:1]);
			}
		}
		
		if ([@"File" isEqualToString:[qryArr objectAtIndex:0]]) {
			mpfile = [[MPFileCheck alloc] init];
			if ([qryArr count] != 4) {
				qlerror(@"Error, not enough args for patch query entry.");
				goto done;	
			}
			
			if ([mpfile queryFile:typeQueryString action:typeQuery param:typeResult]) {
				qlinfo(@"File=TRUE: %@",[qryArr objectAtIndex:1]);
				count++;
			} else {
				qlinfo(@"File=FALSE: %@",[qryArr objectAtIndex:1]);
			}
		}
		
		if ([@"Script" isEqualToString:[qryArr objectAtIndex:0]]) {
			mpscript = [[MPScript alloc] init];
			if ([qryArr count] > 2) {
				qlerror(@"Error, too many args. Sript will not be run.");
				goto done;
			}
			
			if ([mpscript runScript:[qryArr objectAtIndex:1]]) {
				qlinfo(@"SCRIPT=TRUE");
				count++;
			} else {
				qlinfo(@"SCRIPT=FALSE");
			}
		}
	}
	
	goto done;
	
done:
	if (count == [queryArray count]) {
		qlinfo(@"Patch needed.");
		result = YES;
	} else {
		qlinfo(@"Patch not needed.");
	}
	
	return result;
}

-(NSArray *)retrieveCustomPatchScanList
{
    NSError *wsErr = nil;
	NSArray  *scanListArray;
    MPRESTfull *rest = [[MPRESTfull alloc] init];
    scanListArray = [rest getCustomPatchScanListWithSeverity:nil error:&wsErr];
    if (wsErr) {
        qlerror(@"%@",[wsErr localizedDescription]);
        return [NSArray array];
    }
    return scanListArray;
}

-(void)sendNotificationTo:(NSString *)aName userInfo:(NSDictionary *)aUserInfo
{
	if (useDistributedNotification) {
		qldebug(@"sendNotificationTo(G): %@ with %@",aName,aUserInfo);
        [[NSDistributedNotificationCenter defaultCenter] postNotificationName:aName object:nil userInfo:aUserInfo options:NSNotificationPostToAllSessions];        
	} else {
        qldebug(@"sendNotificationTo: %@ with %@",aName,aUserInfo);
		[[NSNotificationCenter defaultCenter] postNotificationName:aName object:nil userInfo:aUserInfo];
	}
}

@end
