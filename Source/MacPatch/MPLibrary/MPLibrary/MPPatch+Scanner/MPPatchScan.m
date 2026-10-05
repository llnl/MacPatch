//
//  MPPatchScan.m
/*
 Copyright (c) 2026, Lawrence Livermore National Security, LLC.
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
@end

@implementation MPPatchScan

@synthesize delegate;

#pragma mark -

- (id)init;
{
    self = [super init];
	if (self)
    {
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
        LogInfo(@"[MPPatchScan][scanForPatches]: Data post to web service (%@), returned true.", urlPath);
        LogDebug(@"Data post to web service (%@), returned true.", urlPath);
        // notifyInfo = @{@"patchesNeeded":[NSNumber numberWithInt:(int)[patchesNeeded count]]};
    }
    else
    {
        LogError(@"Data post to web service (%@), returned false.", urlPath);
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
		LogError(@"Error: %@",wsErr.localizedDescription);
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
		LogWarning(@"Custom patch scan list is empty, no custom patches will be scaned for.");
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

		LogInfo(@"*******************");
		//LogInfo(@"[scanForCustomUpdatesUsingBundleID] Processing patch %d of %d", i+1, (int)customPatches.count);
        LogInfo(@"Processing patch %d of %d", i+1, (int)customPatches.count);
		//LogDebug(@"[scanForCustomUpdatesUsingBundleID] Full patch data: %@", tmpDict);

		// Try multiple possible key names for patch name and version
		NSString *patchName = tmpDict[@"patch_name"] ?: tmpDict[@"name"] ?: tmpDict[@"description"] ?: tmpDict[@"bundle_id"] ?: @"Unknown";
		NSString *patchVer = tmpDict[@"patch_ver"] ?: tmpDict[@"version"] ?: tmpDict[@"patch_version"] ?: @"";

		// Debug: log which fields were found
		//LogInfo(@"[scanForCustomUpdatesUsingBundleID] Extracted: name='%@', version='%@'", patchName, patchVer);
		if (!tmpDict[@"patch_name"]) {
			LogInfo(@"[scanForCustomUpdatesUsingBundleID] Note: 'patch_name' field not found. Available keys: %@", [tmpDict allKeys]);
		}

		LogInfo(@"Scanning for %@(%@)", patchName, patchVer);
		[self postProgressToDelegate:@"Scanning for %@(%@)", patchName, patchVer];
		
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
                    LogInfo(@"%@ (%@) was detected but not approved for install yet.",tmpDict[@"patch_name"],tmpDict[@"puuid"]);
                }
                [patchesNeeded addObject:[patch copy]];
            }
            @catch (NSException *exception)
            {
                LogError(@"%@\n%@",exception,tmpDict);
            }
            patch = nil;
        }
	}
    LogInfo(@"*******************");
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
	LogDebug(@"scanHostForPatch: %@", aPatch);

	NSArray *queryArray = aPatch[@"query"];
	if (!queryArray || queryArray.count == 0) {
		LogInfo(@"No queries to evaluate, patch not needed.");
		return NO;
	}

	NSUInteger matchedQueries = 0;

	for (NSDictionary *queryItem in queryArray) {
		NSArray *queryComponents = [self parseQueryItem:queryItem];
		if (!queryComponents || queryComponents.count == 0) {
			LogError(@"Failed to parse query item: %@", queryItem);
			continue;
		}

		NSString *queryType = queryComponents[0];
		BOOL queryResult = [self evaluateQuery:queryComponents ofType:queryType];

		if (queryResult) {
			matchedQueries++;
		}
	}

	BOOL patchNeeded = (matchedQueries == queryArray.count);
	LogInfo(@"Patch %@: %lu of %lu queries matched",
			patchNeeded ? @"needed" : @"not needed",
			(unsigned long)matchedQueries,
			(unsigned long)queryArray.count);

	return patchNeeded;
}

#pragma mark - Query Parsing Helper

- (NSArray *)parseQueryItem:(NSDictionary *)queryItem
{
	// New format: { type: "File", type_data: "Exists@/path@True" }
	if (queryItem[@"type"]) {
		NSString *type = queryItem[@"type"];
		NSString *typeData = queryItem[@"type_data"] ?: @"";

		NSArray *dataComponents = [typeData componentsSeparatedByString:@"@" escapeString:@"@@"];
		NSMutableArray *result = [NSMutableArray arrayWithObject:type];
		[result addObjectsFromArray:dataComponents];
		return result;
	}

	// Old format: { qStr: "File@Exists@/path@True" }
	if (queryItem[@"qStr"]) {
		return [queryItem[@"qStr"] componentsSeparatedByString:@"@" escapeString:@"@@"];
	}

	return nil;
}

#pragma mark - Query Evaluation

- (BOOL)evaluateQuery:(NSArray *)components ofType:(NSString *)type
{
	if ([type isEqualToString:@"OSArch"]) {
		return [self checkOSArch:components];
	}

	if ([type isEqualToString:@"OSType"]) {
		return [self checkOSType:components];
	}

	if ([type isEqualToString:@"OSVersion"]) {
		return [self checkOSVersion:components];
	}

	if ([type isEqualToString:@"BundleID"]) {
		return [self checkBundleID:components];
	}

	if ([type isEqualToString:@"File"]) {
		return [self checkFile:components];
	}

	if ([type isEqualToString:@"Script"]) {
		return [self checkScript:components];
	}

	LogError(@"Unknown query type: %@", type);
	return NO;
}

- (BOOL)checkOSArch:(NSArray *)components
{
	if (components.count < 2) {
		LogError(@"OSArch query requires at least 2 components");
		return NO;
	}

	MPOSCheck *osCheck = [[MPOSCheck alloc] init];
	BOOL result = [osCheck checkOSArch:components[1]];
	LogInfo(@"OSArch=%@: %@", result ? @"TRUE" : @"FALSE", components[1]);
	return result;
}

- (BOOL)checkOSType:(NSArray *)components
{
	// OSType check disabled, always returns true
	//LogInfo(@"OSType=TRUE (check disabled)");
    LogInfo(@"OSType=TRUE");
	return YES;
}

- (BOOL)checkOSVersion:(NSArray *)components
{
	if (components.count < 2) {
		LogError(@"OSVersion query requires at least 2 components");
		return NO;
	}

	MPOSCheck *osCheck = [[MPOSCheck alloc] init];
	BOOL result = [osCheck checkOSVer:components[1]];
	LogInfo(@"OSVersion=%@: %@", result ? @"TRUE" : @"FALSE", components[1]);
	return result;
}

- (BOOL)checkBundleID:(NSArray *)components
{
	if (components.count != 4) {
		LogError(@"BundleID query requires exactly 4 components (type, action, bundleID, result), got %lu",
				 (unsigned long)components.count);
		return NO;
	}

	MPBundle *bundle = [[MPBundle alloc] init];
	NSString *action = components[1];
	NSString *bundleID = components[2];
	NSString *expectedResult = components[3];

	BOOL result = [bundle queryBundleID:bundleID action:action result:expectedResult];
	LogInfo(@"BundleID=%@: %@ (action: %@, expected: %@)",
			result ? @"TRUE" : @"FALSE", bundleID, action, expectedResult);
	return result;
}

- (BOOL)checkFile:(NSArray *)components
{
	if (components.count != 4) {
		LogError(@"File query requires exactly 4 components (type, action, path, param), got %lu",
				 (unsigned long)components.count);
		return NO;
	}

	MPFileCheck *fileCheck = [[MPFileCheck alloc] init];
	NSString *action = components[1];
	NSString *path = components[2];
	NSString *param = components[3];
    //LogInfo(@"Components(%@)", components);

	BOOL result = [fileCheck queryFile:path action:action param:param];
	//LogInfo(@"File[]=%@: %@ (action: %@)", result ? @"TRUE" : @"FALSE", action, path);
    LogInfo(@"File[%@]=%@ (%@ - %@)", action, result ? @"TRUE" : @"FALSE", [path lastPathComponent], param);
	return result;
}

- (BOOL)checkScript:(NSArray *)components
{
	if (components.count > 2) {
		LogError(@"Script query has too many arguments (%lu), script will not run",
				 (unsigned long)components.count);
		return NO;
	}

	if (components.count < 2) {
		LogError(@"Script query requires script content");
		return NO;
	}

	MPScript *script = [[MPScript alloc] init];
	BOOL result = [script runScript:components[1]];
	LogInfo(@"Script=%@", result ? @"TRUE" : @"FALSE");
	return result;
}


- (NSDictionary *)patchDataForIDUsingArray:(NSString *)patchID patchArray:(NSArray *)approvedPatches
{
    LogDebug(@"Searching for %@", patchID);

    // Validate inputs
    if (![approvedPatches isKindOfClass:[NSArray class]]) {
        LogError(@"approvedPatches is not an NSArray: %@", approvedPatches);
        return nil;
    }

    if (patchID.length == 0) {
        LogWarning(@"patchID is nil or empty.");
        return nil;
    }

    // Use a block-based predicate to avoid KVC crashes on unexpected types
    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(id obj, NSDictionary<NSString *, id> * _Nullable bindings) {
        if (![obj isKindOfClass:[NSDictionary class]]) { return NO; }
        id value = [(NSDictionary *)obj objectForKey:@"puuid"];
        if (![value isKindOfClass:[NSString class]]) { return NO; }
        return [(NSString *)value isEqualToString:patchID];
    }];

    NSArray *filteredArray = [approvedPatches filteredArrayUsingPredicate:predicate];

    if (filteredArray.count == 1) {
        return filteredArray.firstObject;
    } else if (filteredArray.count > 1) {
        LogWarning(@"Multiple entries found for puuid=%@; returning first.", patchID);
        return filteredArray.firstObject;
    } else {
        LogDebug(@"%@ was not found.", patchID);
        return nil;
    }
}


- (NSArray *)retrieveCustomPatchScanList
{
	NSError *wsErr = nil;
	NSArray  *scanListArray;
	MPRESTfull *rest = [[MPRESTfull alloc] init];
	scanListArray = [rest getCustomPatchScanListWithSeverity:nil error:&wsErr];
	if (wsErr) {
		LogError(@"%@",[wsErr localizedDescription]);
		return [NSArray array];
	}

	// Debug: Log the web service response
	LogInfo(@"[retrieveCustomPatchScanList] Retrieved %lu patches from web service", (unsigned long)[scanListArray count]);
	//if ([scanListArray count] > 0) {
		//LogInfo(@"[retrieveCustomPatchScanList] Sample patch data (first item):");
		//LogInfo(@"%@", scanListArray[0]);
		//if ([scanListArray count] > 1) {
		//	LogInfo(@"[retrieveCustomPatchScanList] All patch keys from first item: %@", [scanListArray[0] allKeys]);
		//}
	//}

	return scanListArray;
}


#pragma mark - Delegate Helper

- (void)postProgressToDelegate:(NSString *)str, ...
{
	va_list va;
	va_start(va, str);
	NSString *string = [[NSString alloc] initWithFormat:str arguments:va];
	va_end(va);
	
	LogDebug(@"%@",string);
	[self.delegate scanProgress:string];
}
@end
