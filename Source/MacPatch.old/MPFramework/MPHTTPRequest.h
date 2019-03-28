//
//  MPHTTPRequest.h
//
//  MPHTTPRequest uses NSURLSession for it's requests
//
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

#import <Foundation/Foundation.h>

@class MPWSResult;

@interface MPHTTPRequest : NSObject <NSURLSessionDelegate>

@property (nonatomic, weak, readonly) NSError *error;

- (id)initWithAgentPlist;

/**
 Create temporary download directory using url path

 @param urlPath URL path
 @return path to temp download file
 */
- (NSString *)createTempDownloadDir:(NSString *)urlPath;

/**
 ASyncronus GET Request

 @param urlPath - URL Path, server info will automatically be populated
 @param completion - MPWSResult object will get returned
 */
- (void)runASyncGET:(NSString *)urlPath completion:(void (^)(MPWSResult *result, NSError *error))completion;

/**
 ASyncronus POST Request

 @param urlPath - URL Path, server info will automatically be populated
 @param body Dictionary, will be converted to JSON object, use nil if empty
 @param completion - MPWSResult object will get returned
 */
- (void)runASyncPOST:(NSString *)urlPath body:(NSDictionary *)body completion:(void (^)(MPWSResult *result, NSError *error))completion;


/**
 Download a file using blocks

 @param urlPath - URL Path, server info will automatically be populated
 @param dlDir - Download Directory
 @param progressBar - NSProgressIndicator, use nil if empty
 @param progressPercent - Progress percent
 @param completion - File Name and File Path
 */
- (void)runDownloadRequest:(NSString *)urlPath downloadDirectory:(NSString *)dlDir
                  progress:(NSProgressIndicator *)progressBar progressPercent:(id)progressPercent
                completion:(void (^)(NSString *fileName, NSString *filePath, NSError *error))completion;

- (MPWSResult *)runSyncGET:(NSString *)urlPath;
- (MPWSResult *)runSyncGET:(NSString *)urlPath body:(NSDictionary *)body;
- (MPWSResult *)runSyncPOST:(NSString *)urlPath body:(NSDictionary *)body;

- (NSString *)runSyncFileDownload:(NSString *)urlPath downloadDirectory:(NSString *)dlDir error:(NSError **)err;

@end
