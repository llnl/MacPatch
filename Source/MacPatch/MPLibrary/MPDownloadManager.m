//
//  MPDownloadManager.m
//
//  Created by Charles Heizer on 10/25/18.
//  Copyright © 2018 Charles Heizer. All rights reserved.
//

#import "MPDownloadManager.h"

const NSInteger		 kSessionMaxConnection		= 1;
const NSTimeInterval kSessionResourceTimeout	= 1800; // 30min
const NSTimeInterval kSessionRequestTimeout		= 300; // 5min

NSString * const 	 kDownloadDirectory 		= @"/private/tmp";

@interface MPDownloadManager ()<NSURLSessionDownloadDelegate>

@property (nonatomic, strong) NSURLSession 				*session;
@property (nonatomic, strong) NSURLSessionDownloadTask  *downloadTask;
@property (nonatomic, strong) NSData 					*resumeData;
@property (nonatomic, strong) NSOperationQueue 			*sessionCallbackQueue;
@property (nonatomic, assign) BOOL 						sessionPrepared;
@property (nonatomic, assign) BOOL 						isRunning;

// Private Read/Write Properties
@property (nonatomic, copy, readwrite) NSURL		*downloadedFile;
@property (nonatomic, copy, readwrite) NSError		*downloadError;
@property (nonatomic, assign, readwrite) NSInteger	httpStatusCode;

@end

@implementation MPDownloadManager
{
	struct {
		unsigned int downloadManagerProgress:1;
	} delegateRespondsTo;
}

@synthesize delegate;
@synthesize downloadDestination;
@synthesize downloadedFile;
@synthesize downloadError;
@synthesize httpStatusCode;
@synthesize requestTimeout;
@synthesize resourceTimeout;

- (void)setDelegate:(id )aDelegate
{
	if (delegate != aDelegate) {
		delegate = aDelegate;
		delegateRespondsTo.downloadManagerProgress = [delegate respondsToSelector:@selector(downloadManagerProgress:)];
	}
}

#pragma mark - singleton init

static id _sharedManager = nil;

+ (instancetype)sharedManager
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		_sharedManager = [[self alloc] init];
		[_sharedManager setDownloadDestination:kDownloadDirectory];
		[_sharedManager setResourceTimeout:kSessionResourceTimeout];
		[_sharedManager setRequestTimeout:kSessionRequestTimeout];
	});
	return _sharedManager;
}

+ (instancetype)allocWithZone:(struct _NSZone *)zone
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		if (!_sharedManager) {
			_sharedManager = [super allocWithZone:zone];
		}
	});
	return _sharedManager;
}

- (id)copyWithZone:(NSZone *)zone
{
	return _sharedManager;
}

#pragma mark - download

- (void)beginDownload
{
	self.downloadError = nil;
	self.downloadedFile = nil;
	self.session = nil;
	
	self.session = [self createSession];
	self.sessionPrepared = YES;

	self.downloadTask = [self.session downloadTaskWithURL:[NSURL URLWithString:self.downloadUrl]];
	
	[self.downloadTask resume];
}

- (NSURL *)beginSynchronousDownload
{
	self.downloadError = nil;
	self.downloadedFile = nil;
	self.session = nil;
	
	self.session = [self createSession];
	self.sessionPrepared = YES;
	
	self.downloadTask = [self.session downloadTaskWithURL:[NSURL URLWithString:self.downloadUrl]];
	[self.downloadTask resume];
	
	while (self.downloadTask)
	{
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
	}
	
	return self.downloadedFile;
}

- (void)reset
{
	self.downloadTask = nil;
	self.sessionPrepared = NO;
}

#pragma mark create session
- (NSURLSession *)createSession
{
	NSURLSession *session = nil;
	session = [self backgroundSession];
	return session;
}

- (NSURLSession *)foregroundSession
{
	NSURLSessionConfiguration *foregroundSessionConfig 		= [NSURLSessionConfiguration defaultSessionConfiguration];
	foregroundSessionConfig.HTTPMaximumConnectionsPerHost	= kSessionMaxConnection;
	foregroundSessionConfig.timeoutIntervalForResource		= self.resourceTimeout;
	foregroundSessionConfig.timeoutIntervalForRequest 		= self.requestTimeout;
	
	NSOperationQueue *sQueue 			= [[NSOperationQueue alloc] init];
	sQueue.maxConcurrentOperationCount	= 1;
	self.sessionCallbackQueue 			= sQueue;
	
	return [NSURLSession sessionWithConfiguration:foregroundSessionConfig delegate:self delegateQueue:sQueue];
}

- (NSURLSession *)backgroundSession
{
	NSString *bgSessionID 					= [NSString stringWithFormat:@"mp.download.session.%@",[[NSUUID UUID] UUIDString]];
	NSURLSessionConfiguration *config 		= [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:bgSessionID];
	config.HTTPMaximumConnectionsPerHost	= kSessionMaxConnection;
	qldebug(@"Setting timeoutIntervalForResource to %f",self.resourceTimeout);
	config.timeoutIntervalForResource 	 	= self.resourceTimeout;
	qldebug(@"Setting timeoutIntervalForRequest to %f",self.requestTimeout);
	config.timeoutIntervalForRequest 		= self.requestTimeout;
	
	NSOperationQueue *sQueue 			= [[NSOperationQueue alloc] init];
	sQueue.maxConcurrentOperationCount	= 1;
	self.sessionCallbackQueue 			= sQueue;
	
	return [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:sQueue];
}

#pragma mark - NSURLSession Delegates
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
	double progress = 1.0 * totalBytesWritten / totalBytesExpectedToWrite;
	if (self.progressHandler) self.progressHandler(progress * 100, totalBytesWritten, totalBytesExpectedToWrite);
	[self.delegate downloadManagerProgress:progress * 100];
	
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didResumeAtOffset:(int64_t)fileOffset expectedTotalBytes:(int64_t)expectedTotalBytes {
	//NSLog(@"%@ - %lld - %lld", downloadTask, fileOffset, expectedTotalBytes);
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location
{
	NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse*)downloadTask.response;
	self.httpStatusCode = httpResponse.statusCode;
	if (httpResponse.statusCode >= 200 && httpResponse.statusCode <= 304)
	{
		NSString *fileName = downloadTask.response.suggestedFilename;
		NSString *destinationPath = [downloadDestination stringByAppendingPathComponent:fileName];
		
		NSError *error = nil;
		self.downloadedFile = [self moveDownloadAtPath:location.path toPath:destinationPath isFileDelete:YES error:&error];
		if (error) {
			self.downloadError = error;
		}
	} else {
		self.downloadError = [NSError errorWithDomain:@"gov.llnl.mp" code:httpResponse.statusCode userInfo:@{NSLocalizedDescriptionKey:@"Error downloading file."}];
	}
	
	if (self.completionHandler) self.completionHandler((int)self.httpStatusCode, self.downloadedFile, self.downloadError);
	[self reset];
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler
{
	
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data
{
	
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
	if (error) {
		qlerror(@"MPDownloadManager [didCompleteWithError][Error] %@",error.localizedDescription);
		self.downloadError = error;
	}
	
	if (self.completionHandler) self.completionHandler((int)self.httpStatusCode, self.downloadedFile, self.downloadError);
	[self reset];
}

#pragma mark - Private

- (NSURL *)moveDownloadAtPath:(NSString *)path toPath:(NSString *)toPath isFileDelete:(BOOL)fileDelete error:(NSError **)error
{
	BOOL moveFileToTemp = NO;
	NSString *fileName = [toPath lastPathComponent];
	toPath = [toPath stringByDeletingLastPathComponent];
	
	NSError *err = nil;
	NSFileManager *fm = [NSFileManager defaultManager];
	BOOL isDir;
	BOOL exists = [fm fileExistsAtPath:toPath isDirectory:&isDir];
	if (exists)
	{
		if(!isDir)
		{
			//It's a file
			if (fileDelete)
			{
				// Remove file with same name as new dir
				err = nil;
				[fm removeItemAtPath:toPath error:&err];
				if (err) {
					// Err removing file, move file to tmp dir
					moveFileToTemp = YES;
				}
				else
				{
					// Create destination directory, file delete was good
					err = nil;
					[fm createDirectoryAtPath:toPath withIntermediateDirectories:YES attributes:nil error:&err];
					if (err) {
						// Err create destination directory file, move file to tmp dir
						moveFileToTemp = YES;
					}
				}
			}
		}
	}
	else
	{
		err = nil;
		[fm createDirectoryAtPath:toPath withIntermediateDirectories:YES attributes:nil error:NULL];
		if (err) {
			// Err create destination directory file, move file to tmp dir
			moveFileToTemp = YES;
		}
	}
	
	// Change toPath to /tmp since we coudl not create our dest directory
	if (moveFileToTemp) toPath = kDownloadDirectory;
	toPath = [toPath stringByAppendingPathComponent:fileName];
	
	err = nil;
	[fm moveItemAtPath:path toPath:toPath error:&err];
	if (err)
	{
		if (error != NULL) *error = err;
	}
	
	return [NSURL fileURLWithPath:toPath];
}

@end
