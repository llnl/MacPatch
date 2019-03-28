//
//  AppStoreOperation.m
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

#import "AppStoreOperation.h"
#import "MPAppStore.h"
#import "MacPatch.h"
#import "MPSettings.h"
#import "MPClientKey.h"


@interface AppStoreOperation (Private)

- (void)collectDataAndPostIt;
- (BOOL)processData:(NSArray *)dataArray table:(NSString *)tableName;
- (BOOL)sendResultsToWebService:(NSDictionary *)aDataMgrData;

@end

@implementation AppStoreOperation

@synthesize isExecuting;
@synthesize isFinished;

- (id)init
{
    if ((self = [super init]))
    {
        isExecuting = NO;
        isFinished  = NO;
        settings    = [MPSettings sharedInstance];
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
    isExecuting = NO;
    isFinished = YES;
    [self didChangeValueForKey:@"isExecuting"];
    [self didChangeValueForKey:@"isFinished"];
}

- (void)start
{
    if ([self isCancelled]) {
        [self willChangeValueForKey:@"isFinished"];
        isFinished = YES;
        [self didChangeValueForKey:@"isFinished"];
    } else {
        [self willChangeValueForKey:@"isExecuting"];
        [self performSelectorInBackground:@selector(main) withObject:nil];
        isExecuting = YES;
        [self didChangeValueForKey:@"isExecuting"];
    }
}

- (void)main
{
    @try {
        [self collectDataAndPostIt];
    }
    @catch (NSException * e) {
        logit(lcl_vError,@"[NSException]: %@",e);
    }
    [self finish];
}

- (void)collectDataAndPostIt
{
    @autoreleasepool
    {
        logit(lcl_vInfo,@"Running client check in.");
        @try {
            MPAppStore *mpas = [[MPAppStore alloc] init];
            NSArray *installedProducts = [mpas installedProducts];
            NSArray *outdatedProducts = [mpas availableUpdates];
            
            [self processData:installedProducts table:@"AppStoreInstalled"];
            [self processData:outdatedProducts table:@"AppStoreUpdates"];
            
        }
        @catch (NSException * e) {
            logit(lcl_vError,@"[NSException]: %@",e);
            logit(lcl_vError,@"No client checkin data will be posted.");
            return;
        }
    }
}

- (BOOL)processData:(NSArray *)dataArray table:(NSString *)tableName
{
    MPDataMgr       *dataMgr = [[MPDataMgr alloc] init];
    NSDictionary    *dataMgrJSON;
    
    dataMgrJSON = [dataMgr GenDataForDataMgr:dataArray
                                     dbTable:tableName
                               dbTablePrefix:@"mpi_"
                               dbFieldPrefix:@"mpa_"
                                updateFields:@"rid,cuuid"
                                   deleteCol:@"cuuid"
                              deleteColValue:[settings ccuid]];
    
    if ([self sendResultsToWebService:dataMgrJSON]) {
        logit(lcl_vInfo,@"Results for %@ posted.",tableName);
    } else {
        logit(lcl_vError,@"Results for %@ not posted.",tableName);
    }

    return YES;
}

- (BOOL)sendResultsToWebService:(NSDictionary *)aDataMgrData
{
    MPHTTPRequest *req;
    MPWSResult *result;
    
    req = [[MPHTTPRequest alloc] init];
    
    NSString *urlPath = [@"/api/v1/client/inventory" stringByAppendingPathComponent:[settings ccuid]];
    result = [req runSyncPOST:urlPath body:aDataMgrData];
    
    if (result.statusCode >= 200 && result.statusCode <= 299) {
        logit(lcl_vInfo,@"AppStore Data post, returned true.");
        logit(lcl_vDebug,@"AppStore Data Result: %@",result.result);
    } else {
        logit(lcl_vError,@"AppStore Data post, returned false.");
        logit(lcl_vDebug,@"%@",result.toDictionary);
        return NO;
    }
    
    return YES;
}

@end
