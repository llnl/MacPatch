//
//  MPHTTPRequest.h
//
//  MPHTTPRequest uses NSURLSession for it's requests
//
//  Created by Charles Heizer on 9/15/17.
//  Copyright © 2017 LLNL. All rights reserved.
//

#import <Foundation/Foundation.h>

@class MPWSResult;

@protocol MPHTTPRequestDelegate <NSObject>
@optional
- (void)downloadProgress:(NSString *)progressStr, ...;
@end

@interface MPHTTPRequest : NSObject <NSURLSessionDelegate, MPHTTPRequestDelegate>

@property (nonatomic, weak) id <MPHTTPRequestDelegate> delegate;
@property (nonatomic, weak, readonly) NSError *error;

@property (nonatomic, assign) NSTimeInterval	requestTimeout;
@property (nonatomic, assign) NSTimeInterval	resourceTimeout;

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
- (NSString *)runSyncFileDownloadAlt:(NSString *)urlPath downloadDirectory:(NSString *)dlDir error:(NSError **)err;

- (NSData *)dataForURLPath:(NSString *)aURLPath;
@end


