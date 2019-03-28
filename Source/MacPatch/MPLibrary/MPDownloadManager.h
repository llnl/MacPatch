//
//  MPDownloadManager.h
//  AFNetworkingNewTest
//
//  Created by Charles Heizer on 10/25/18.
//  Copyright © 2018 Charles Heizer. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol MPDownloadManagerDelegate <NSObject>
// Delegate method used for progress on Syncronous Download
- (void)downloadManagerProgress:(double)downloadProgress;
@end


@interface MPDownloadManager : NSObject

// Delegate used for progress on Syncronous Download
@property (nonatomic, weak) id  delegate;

@property (nonatomic, copy)   NSString			*downloadUrl;
@property (nonatomic, copy)   NSString			*downloadDestination;
@property (nonatomic, assign) NSTimeInterval	requestTimeout;
@property (nonatomic, assign) NSTimeInterval	resourceTimeout;

// Read Only
@property (nonatomic, copy, readonly) NSURL			*downloadedFile;
@property (nonatomic, copy, readonly) NSError		*downloadError;
@property (nonatomic, assign, readonly) NSInteger	httpStatusCode;

// Block Handlers
@property (nonatomic, copy) void (^completionHandler)(int httpStatusCode, NSURL *downloadedFile, NSError *downloadError);
@property (nonatomic, copy) void (^progressHandler)(double progressPercent, double sizeDownloaded, double sizeComplete);

+ (instancetype)sharedManager;

/**
 Starts the asyncronous file download.
 
 Optional Handlers:
 	progressHandler
 	completionHandler
 */
- (void)beginDownload;

/**
 Starts a synchronous download, returns the downloaded file
 in URL format.
 
 Note: although a download destination maybe set, if and error
 occurs creating or using that location the method will return
 a alternate location for the downloaded file.
 */
- (NSURL *)beginSynchronousDownload;

@end
