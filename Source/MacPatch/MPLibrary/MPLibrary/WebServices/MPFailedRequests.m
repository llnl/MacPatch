//
//  MPFailedRequests.m
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

#import "MPFailedRequests.h"
//#import "MPWebServices.h"

@implementation MPFailedRequests

- (id)init
{
    self = [super init];
    if (self) {
        fm = [NSFileManager defaultManager];
    }
    return self;
}

- (NSDictionary *)readFailedRequestsPlist
{
    if ([fm fileExistsAtPath:WS_FAILED_REQ_PLIST])
    {
        NSDictionary *reqFile = [NSDictionary dictionaryWithContentsOfFile:WS_FAILED_REQ_PLIST];
        return reqFile;
    }
    return nil;
}

- (BOOL)writeFailedRequestsPlist:(NSDictionary *)aRequests
{
    NSError *fmErr = nil;
    NSDictionary *attr775 = [NSDictionary dictionaryWithObject:[NSNumber numberWithShort:0775] forKey:NSFilePosixPermissions];
    NSDictionary *attr777 = [NSDictionary dictionaryWithObject:[NSNumber numberWithShort:0777] forKey:NSFilePosixPermissions];

    // Create the Parent Dir if Missing
    if (![fm fileExistsAtPath:WS_FAILED_REQ_PLIST])
    {
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:[WS_FAILED_REQ_PLIST stringByDeletingLastPathComponent] isDirectory:&isDir]) {
            fmErr = nil;
            [fm createDirectoryAtPath:[WS_FAILED_REQ_PLIST stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:attr777 error:&fmErr];
            if (fmErr) {
                qlerror(@"%@",fmErr.localizedDescription);
                return NO;
            }
        }
    }

    // Write file
    fmErr = nil;
    [aRequests writeToFile:WS_FAILED_REQ_PLIST atomically:NO];
    [fm setAttributes:attr775 ofItemAtPath:WS_FAILED_REQ_PLIST error:&fmErr];
    if (fmErr) {
        qlerror(@"%@",fmErr.localizedDescription);
        return NO;
    }

    return YES;
}

- (BOOL)addFailedRequest:(NSString *)methodName params:(NSDictionary *)aParams errorNo:(NSInteger)errorNo errorMsg:(NSString *)errorMsg
{
    NSMutableDictionary *reqFile = [NSMutableDictionary dictionaryWithDictionary:[self readFailedRequestsPlist]];
    NSMutableArray *reqs;
    if ([reqFile objectForKey:@"failedAttempts"]) {
        reqs = [[NSMutableArray alloc] initWithArray:[reqFile objectForKey:@"failedAttempts"]];
    } else {
        reqs = [[NSMutableArray alloc] init];
    }
    NSMutableDictionary *req = [[NSMutableDictionary alloc] init];
    [req setObject:[NSDate date] forKey:@"failDate"];
    [req setObject:[NSNumber numberWithInteger:errorNo] forKey:@"errorno"];
    [req setObject:errorMsg forKey:@"errormsg"];
    [req setObject:methodName forKey:@"wsMethod"];
    [req setObject:[NSNumber numberWithInt:1] forKey:@"postAttempts"];
    if (aParams)
        [req setObject:aParams forKey:@"params"];

    [reqs addObject:(NSDictionary *)req];
    [reqFile setObject:reqs forKey:@"failedAttempts"];

    return [self writeFailedRequestsPlist:(NSDictionary *)reqFile];
}

- (BOOL)postFailedRequests
{
    /*
    NSMutableDictionary *reqFile = [NSMutableDictionary dictionaryWithDictionary:[self readFailedRequestsPlist]];
    if (!reqFile) {
        qlinfo(@"No failed requests to post. Failed requests file not found.");
        return YES;
    }

    NSArray *reqs;
    NSMutableArray *reqsFailed = [[NSMutableArray alloc] init];
    if ([reqFile objectForKey:@"failedAttempts"]) {
        reqs = [NSArray arrayWithArray:[reqFile objectForKey:@"failedAttempts"]];
        if ([reqs count] == 0) {
            qlinfo(@"No failed requests to post");
            return YES;
        }
    } else {
        qlinfo(@"No failed requests to post");
        return YES;
    }

    NSError *err = nil;
    MPWebServices *mpws = [[MPWebServices alloc] init];
    for (NSDictionary *req in reqs)
    {
        NSDictionary *params = [req objectForKey:@"params"];
        err = nil;

        if (![req objectForKey:@"wsMethod"]) {
            continue;
        }
        qlinfo(@"Attempting to re-post data for %@",[req objectForKey:@"wsMethod"]);
        if ([params objectForKey:@"aMethod"]) {
            qldebug(@"Params Method: %@",[params objectForKey:@"aMethod"]);
        }
        if ([[req objectForKey:@"wsMethod"] isEqualToString:@"postPatchScanResultsForType"]) {
            qlinfo(@"postPatchScanResultsForType is disabled");
            //[mpws postPatchScanResultsForType:(NSInteger)[params objectForKey:@"aPatchScanType"] results:[params objectForKey:@"resultsDictionary"] error:&err];

        } else if ([[req objectForKey:@"wsMethod"] isEqualToString:@"postPatchInstallResultsToWebService"]) {
            [mpws postPatchInstallResultsToWebService:[params objectForKey:@"aPatch"] patchType:[params objectForKey:@"aPatchType"] error:&err];

        } else if ([[req objectForKey:@"wsMethod"] isEqualToString:@"postClientAVData"]) {
            //CEH
            //[mpws postClientAVData:[params objectForKey:@"aDict"] error:&err];

        } else if ([[req objectForKey:@"wsMethod"] isEqualToString:@"postDataMgrXML"]) {
            //CEH
            //[mpws postDataMgrXML:[params objectForKey:@"aDataMgrXML"] error:&err];

        } else if ([[req objectForKey:@"wsMethod"] isEqualToString:@"postDataMgrData"]) {
            [mpws postDataMgrData:[params objectForKey:@"aDataMgrJSON"] error:&err];

        } else if ([[req objectForKey:@"wsMethod"] isEqualToString:@"postSAVDefsDataXML"]) {
            //CEH
            //[mpws postSAVDefsDataXML:[params objectForKey:@"aAVXML"] encoded:(BOOL)[params objectForKey:@"aEncoded"] error:&err];

        } else if ([[req objectForKey:@"wsMethod"] isEqualToString:@"postJSONDataForMethod"]) {
            //CEH
            //[mpws postJSONDataForMethod:[params objectForKey:@"aMethod"] data:[params objectForKey:@"aData"] error:&err];

        } else if ([[req objectForKey:@"wsMethod"] isEqualToString:@"postSWInstallResults"]) {
            [mpws postSWInstallResults:[params objectForKey:@"aParams"] error:&err];

        } else if ([[req objectForKey:@"wsMethod"] isEqualToString:@"postClientHasInvData"]) {
            [mpws postClientHasInvData:&err];

        } else {
            continue;
        }

        if (err) {
            qlerror(@"Error re-posting data for %@",[req objectForKey:@"wsMethod"]);
            qldebug(@"Params: %@",params);
            if ([[req objectForKey:@"postAttempts"] intValue] <= 15) {
                int p = [[req objectForKey:@"postAttempts"] intValue];
                p++;
                NSMutableDictionary *newReq = [NSMutableDictionary dictionaryWithDictionary:req];
                [newReq setObject:[NSNumber numberWithInt:p] forKey:@"postAttempts"];
                [reqsFailed addObject:newReq];
            } else {
                qlerror(@"%@ is being removed due to to many re-post attempts.",[req objectForKey:@"wsMethod"]);
            }
        }
    }

    [reqFile setObject:reqsFailed forKey:@"failedAttempts"];
    if ([self writeFailedRequestsPlist:reqFile]) {
        return YES;
    } else {
        return NO;
    }
     */
    return NO;
}

@end
