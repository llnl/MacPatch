//
//  MPPatchScan.m
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

#import "MPPatchScan.h"
#import "MPSettings.h"
#import "MPOSCheck.h"
#import "MPBundle.h"
#import "MPFileCheck.h"
#import "MPScript.h"
#include <unistd.h>

#undef  ql_component
#define ql_component lcl_cMPPatchScan

@interface MPPatchScan ()
{
    MPSettings *settings;
}

// Scanning
- (BOOL)scanHostForPatch:(NSDictionary *)aPatch;
- (NSDictionary *)patchDataForIDUsingArray:(NSString *)patchID patchArray:(NSArray *)approvedPatches;
// Network
- (NSArray *)retrieveCustomPatchScanList;
// Delegate
- (void)postProgressToDelegate:(NSString *)str, ...;
// -(void)sendNotificationTo:(NSString *)aName userInfo:(NSDictionary *)aUserInfo;
@end

@implementation MPPatchScan

@synthesize delegate;

#pragma mark -

- (id)init;
{
    self = [super init];
	if (self)
    {
        //[self setUseDistributedNotification:NO];
        settings = [MPSettings sharedInstance];
    }
	return self;
}


/**
 Scan a system for custom patches. Return NSArray of required patches

 @return NSArray
 */
- (NSArray *)scanForPatches
{
	NSArray  *patchesNeeded = [self scanForPatchesOrScanForBundleID:NULL];

    // Post patches needed to web service
	MPRESTfull *mprest = [MPRESTfull new];
    NSError *wsErr = nil;
    NSString *urlPath = [@"/api/v1/client/patch/scan/2" stringByAppendingPathComponent:settings.ccuid];
    BOOL rest_result = [mprest postDataToWS:urlPath data:@{@"rows":patchesNeeded} error:&wsErr];
    if (rest_result)
    {
        logit(lcl_vInfo,@"[MPPatchScan][scanForPatches]: Data post to web service (%@), returned true.", urlPath);
        logit(lcl_vDebug,@"Data post to web service (%@), returned true.", urlPath);
        // notifyInfo = @{@"patchesNeeded":[NSNumber numberWithInt:(int)[patchesNeeded count]]};
    }
    else
    {
        logit(lcl_vError,@"Data post to web service (%@), returned false.", urlPath);
    }
	
	[self postProgressToDelegate:@"Custom patch scan completed."];
	return [NSArray arrayWithArray:patchesNeeded];
}

/**
 Scan a system for custom patch based on BundleID. Return NSArray of required patches
 
 @param aBundleID - Custom patch bundle id
 @return NSArray
 */
- (NSArray *)scanForPatchesWithbundleID:(NSString *)aBundleID
{
	return [self scanForPatchesOrScanForBundleID:aBundleID];
}

/**
 This method is the main patch scanning method. If BundleID is passed it will only scan for
 that bundle id, otherwise it will scan for all patches. If no bundle id is use please pass
 NULL to the aBundleID param.

 @param aBundleID - Patch Bundle ID or NULL
 @return NSArray of needed patches
 */
- (NSArray *)scanForPatchesOrScanForBundleID:(NSString *)aBundleID
{
	//[self postProgressToDelegate:@"Begin custom patch scan."];
	
	NSArray         *resultArr = nil;
	NSMutableArray  *patchesNeeded = [[NSMutableArray alloc] init];
	
	/*
	 1. Get Scan List
	 2. Scan for patches
	 3. Post patches needed
	 */
	NSError *wsErr = nil;
	MPRESTfull *mprest = [[MPRESTfull alloc] init];
	NSDictionary *patchGroupPatches = [mprest getApprovedPatchesForClient:&wsErr];
	if (wsErr)
	{
		qlerror(@"Error: %@",wsErr.localizedDescription);
	}
	
	// 1. Get the list
	NSArray *customPatches = [self retrieveCustomPatchScanList];
	
	// Filter Scan list for just the required bundle id
	if (aBundleID != NULL) {
		[self postProgressToDelegate:@"Filter scan using BundleID %@", aBundleID];
		NSPredicate *fltr = [NSPredicate predicateWithFormat:@"(bundle_id == %@)", aBundleID];
		customPatches = [customPatches filteredArrayUsingPredicate:fltr];
	}
	
	if ([customPatches count] == 0)
	{
		qlwarning(@"Custom patch scan list is empty, no custom patches will be scaned for.");
		return resultArr;
	}
	// 2. Scan the host
	BOOL result = NO;
	int i = 0;
	
	for(i=0; i < customPatches.count; i++)
	{
		NSDictionary *tmpDict = [NSDictionary dictionaryWithDictionary:customPatches[i]];
		if (aBundleID != NULL)
		{
			if ([tmpDict hasKey:@"bundleID"])
			{
				if ([tmpDict[@"bundleID"] isEqualToString:aBundleID] == NO) continue;
			}
		}
		
		qlinfo(@"*******************");
		qlinfo(@"Scanning for %@(%@)",tmpDict[@"patch_name"],tmpDict[@"patch_ver"]);
		[self postProgressToDelegate:@"Scanning for %@(%@)", tmpDict[@"patch_name"], tmpDict[@"patch_ver"]];
		
		result = [self scanHostForPatch:tmpDict];
        if (result == YES)
        {
            NSMutableDictionary *patch = [[NSMutableDictionary alloc] init];
            NSDictionary *patchData = [self patchDataForIDUsingArray:tmpDict[@"puuid"] patchArray:patchGroupPatches[@"Custom"]];
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
                if (patchData) {
                    [patch setObject:patchData forKey:@"patchData"];
                } else {
                    qlinfo(@"%@ (%@) was detected but not approved for install yet.",tmpDict[@"patch_name"],tmpDict[@"puuid"]);
                }
                [patchesNeeded addObject:[patch copy]];
            }
            @catch (NSException *exception)
            {
                qlerror(@"%@\n%@",exception,tmpDict);
            }
            patch = nil;
        }
        /* Orig
		if (result == YES)
		{
			NSMutableDictionary *patch = [[NSMutableDictionary alloc] init];
			NSDictionary *patchData = [self patchDataForIDUsingArray:tmpDict[@"puuid"] patchArray:patchGroupPatches[@"Custom"]];
			if (patchData)
			{
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
					if (patchData) {
						[patch setObject:patchData forKey:@"patchData"];
					}
					[patchesNeeded addObject:[patch copy]];
				}
				@catch (NSException *exception)
				{
					qlerror(@"%@\n%@",exception,tmpDict);
				}
			} else {
				qlinfo(@"%@ (%@) was detected but not approved for install yet.",tmpDict[@"patch_name"],tmpDict[@"puuid"]);
				
			}
			patch = nil;
		}
         */
	}
    qlinfo(@"*******************");
	return [patchesNeeded copy];
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
#pragma mark - Private

- (BOOL)scanHostForPatch:(NSDictionary *)aPatch
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
		
        /* CEH: Dsable for now, no longer needed. */
		if ([@"OSType" isEqualToString:[qryArr objectAtIndex:0]]) {
            count++;
            /*
			mpos = [[MPOSCheck alloc] init];
			if ([mpos checkOSType:[qryArr objectAtIndex:1]]) {
				qlinfo(@"OSType=TRUE: %@",[qryArr objectAtIndex:1]);
				count++;
			} else {
				qlinfo(@"OSType=FALSE: %@",[qryArr objectAtIndex:1]);
			}
             */
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
            
			typeQuery		= [qryArr objectAtIndex:1];
			typeQueryString = [qryArr objectAtIndex:2];
			typeResult		= [qryArr objectAtIndex:3];
			
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

- (NSDictionary *)patchDataForIDUsingArray:(NSString *)patchID patchArray:(NSArray *)approvedPatches
{
	qldebug(@"Searching for %@",patchID );
	
	NSDictionary *result = nil;
	NSArray *filteredarray = [approvedPatches filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"(puuid == %@)", patchID]];
	if (filteredarray)
	{
		if (filteredarray.count == 1) {
			result = [filteredarray objectAtIndex:0];
		}
	}
	if (!result){
		qldebug(@"%@ was not found.",patchID );
	}
	return result;
}

- (NSArray *)retrieveCustomPatchScanList
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

/*
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
*/

#pragma mark - Delegate Helper

- (void)postProgressToDelegate:(NSString *)str, ...
{
	va_list va;
	va_start(va, str);
	NSString *string = [[NSString alloc] initWithFormat:str arguments:va];
	va_end(va);
	
	qltrace(@"%@",string);
	[self.delegate scanProgress:string];
}
@end
