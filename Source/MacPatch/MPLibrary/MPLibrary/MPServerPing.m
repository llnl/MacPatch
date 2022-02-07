//
//  MPServerPing.m
//  MPLibrary
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

#import "MPServerPing.h"
#include <stdio.h>
#include <curl/curl.h>

static NSString *ServerTestURI = @"/api/v1/server/status/nodb";

@implementation MPServerPing

/*  Simple API Server Test Path
    This allows us to see which servers are reachable and responding.
 */
- (BOOL)serverHostIsReachable:(NSString *)hostName port:(NSInteger)port
{
    BOOL res = NO;
    NSString *hostURL = [NSString stringWithFormat:@"https://%@:%ld%@",hostName,(long)port,ServerTestURI];
    const char *hostURLStr = [hostURL cStringUsingEncoding:NSASCIIStringEncoding];
    
    CURL *curl;
    CURLcode curlRes = 0;
    long http_code = 0;
    curl_global_init(CURL_GLOBAL_ALL);
    curl = curl_easy_init();
    if(curl)
    {
        curl_easy_setopt(curl, CURLOPT_URL, hostURLStr);
        curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 1);
        curl_easy_setopt(curl, CURLOPT_NOBODY, 1);
        curlRes = curl_easy_perform(curl);
        curl_easy_getinfo (curl, CURLINFO_RESPONSE_CODE, &http_code);
        curl_easy_cleanup(curl);
    }
    curl_global_cleanup();
    //qldebug(@"Testing %@",hostURL);
    if (curlRes == 0) {
        if (http_code == 200 && curlRes != CURLE_ABORTED_BY_CALLBACK) {
            res = YES;
        }
    }
    
    return res;
}

@end
