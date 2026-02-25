//
//  MPDownloadManager.m
//
//  Created by Charles Heizer on 10/25/18.
//  Copyright © 2018 Charles Heizer. All rights reserved.
//

#import "MPDownloadManager.h"

static const void *kMPDownloadManagerStateQueueKey = &kMPDownloadManagerStateQueueKey;

const NSInteger		 kSessionMaxConnection		= 1;
const NSTimeInterval kSessionResourceTimeout	= 5400; // 30min
const NSTimeInterval kSessionRequestTimeout		= 300; // 5min

NSString * const 	 kDownloadDirectory 		= @"/private/tmp";

@interface MPDownloadManager ()<NSURLSessionDownloadDelegate>

@property (nonatomic, strong) NSURLSession 				*session;
@property (nonatomic, strong) NSURLSessionDownloadTask  *downloadTask;
@property (nonatomic, strong) NSData 					*resumeData;
@property (nonatomic, strong) NSOperationQueue 			*sessionCallbackQueue;
@property (nonatomic, assign) BOOL 						sessionPrepared;
@property (nonatomic, assign) BOOL 						isRunning;
@property (nonatomic, strong) dispatch_queue_t           stateQueue;

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
@synthesize allowSelfSignedCert;

- (void)setDelegate:(id )aDelegate
{
    if (dispatch_get_specific(kMPDownloadManagerStateQueueKey)) {
        if (self->delegate != aDelegate) {
            self->delegate = aDelegate;
            self->delegateRespondsTo.downloadManagerProgress = [self->delegate respondsToSelector:@selector(downloadManagerProgress:)];
        }
    } else {
        dispatch_sync(self.stateQueue, ^{
            if (self->delegate != aDelegate) {
                self->delegate = aDelegate;
                self->delegateRespondsTo.downloadManagerProgress = [self->delegate respondsToSelector:@selector(downloadManagerProgress:)];
            }
        });
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
        [_sharedManager setAllowSelfSignedCert:NO];
        {
            dispatch_queue_t q = dispatch_queue_create("gov.llnl.mpdownloadmanager.state", DISPATCH_QUEUE_SERIAL);
            dispatch_queue_set_specific(q, kMPDownloadManagerStateQueueKey, (void *)kMPDownloadManagerStateQueueKey, NULL);
            [_sharedManager setStateQueue:q];
        }
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
    __block NSURLSessionDownloadTask *task = nil;
    if (dispatch_get_specific(kMPDownloadManagerStateQueueKey)) {
        self.downloadError = nil;
        self.downloadedFile = nil;
        self.session = nil;
        self.session = [self createSession];
        self.sessionPrepared = YES;
        task = [self.session downloadTaskWithURL:[NSURL URLWithString:self.downloadUrl]];
        self.downloadTask = task;
    } else {
        dispatch_sync(self.stateQueue, ^{
            self.downloadError = nil;
            self.downloadedFile = nil;
            self.session = nil;
            self.session = [self createSession];
            self.sessionPrepared = YES;
            task = [self.session downloadTaskWithURL:[NSURL URLWithString:self.downloadUrl]];
            self.downloadTask = task;
        });
    }
    [task resume];
}

- (NSURL *)beginSynchronousDownload
{
    __block NSURLSessionDownloadTask *task = nil;
    if (dispatch_get_specific(kMPDownloadManagerStateQueueKey)) {
        self.downloadError = nil;
        self.downloadedFile = nil;
        self.session = nil;
        self.session = [self createSession];
        self.sessionPrepared = YES;
        task = [self.session downloadTaskWithURL:[NSURL URLWithString:self.downloadUrl]];
        self.downloadTask = task;
    } else {
        dispatch_sync(self.stateQueue, ^{
            self.downloadError = nil;
            self.downloadedFile = nil;
            self.session = nil;
            self.session = [self createSession];
            self.sessionPrepared = YES;
            task = [self.session downloadTaskWithURL:[NSURL URLWithString:self.downloadUrl]];
            self.downloadTask = task;
        });
    }
    
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    __block NSURL *result = nil;
    // Wrap existing completion to signal semaphore
    __block void (^origCompletion)(int, NSURL *, NSError *) = nil;
    if (dispatch_get_specific(kMPDownloadManagerStateQueueKey)) {
        origCompletion = self.completionHandler;
        self.completionHandler = ^(int status, NSURL *url, NSError *err) {
            if (origCompletion) origCompletion(status, url, err);
            result = url;
            dispatch_semaphore_signal(sema);
        };
    } else {
        dispatch_sync(self.stateQueue, ^{
            origCompletion = self.completionHandler;
            self.completionHandler = ^(int status, NSURL *url, NSError *err) {
                if (origCompletion) origCompletion(status, url, err);
                result = url;
                dispatch_semaphore_signal(sema);
            };
        });
    }
    [task resume];
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    // Restore original completion
    if (dispatch_get_specific(kMPDownloadManagerStateQueueKey)) {
        self.completionHandler = origCompletion;
    } else {
        dispatch_sync(self.stateQueue, ^{
            self.completionHandler = origCompletion;
        });
    }
    return result;
}

- (void)reset
{
    if (dispatch_get_specific(kMPDownloadManagerStateQueueKey)) {
        self.downloadTask = nil;
        self.sessionPrepared = NO;
    } else {
        dispatch_sync(self.stateQueue, ^{
            self.downloadTask = nil;
            self.sessionPrepared = NO;
        });
    }
}

#pragma mark create session
- (NSURLSession *)createSession
{
	NSURLSession *session = nil;
	session = [self foregroundSession];
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
	config.requestCachePolicy 				= NSURLRequestReloadIgnoringLocalCacheData;
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
    __block void (^progressBlock)(double,double,double) = nil;
    __block id localDelegate = nil;
    if (dispatch_get_specific(kMPDownloadManagerStateQueueKey)) {
        progressBlock = self.progressHandler;
        localDelegate = self->delegate;
    } else {
        dispatch_sync(self.stateQueue, ^{
            progressBlock = self.progressHandler;
            localDelegate = self->delegate;
        });
    }
    if (progressBlock) progressBlock(progress * 100, totalBytesWritten, totalBytesExpectedToWrite);
    if ([localDelegate respondsToSelector:@selector(downloadManagerProgress:)]) {
        [localDelegate downloadManagerProgress:progress * 100];
    }
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didResumeAtOffset:(int64_t)fileOffset expectedTotalBytes:(int64_t)expectedTotalBytes {
	//NSLog(@"%@ - %lld - %lld", downloadTask, fileOffset, expectedTotalBytes);
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location
{
	NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse*)downloadTask.response;
    __block void (^completion)(int, NSURL *, NSError *) = nil;
    __block NSInteger status = httpResponse.statusCode;
    __block NSURL *movedURL = nil;
    __block NSError *dError = nil;
    if (dispatch_get_specific(kMPDownloadManagerStateQueueKey)) {
        self.httpStatusCode = status;
        if (httpResponse.statusCode >= 200 && httpResponse.statusCode <= 304)
        {
            NSString *fileName = downloadTask.response.suggestedFilename;
            NSString *destinationPath = [self->downloadDestination stringByAppendingPathComponent:fileName];
            NSError *error = nil;
            NSURL *dest = [self moveDownloadAtPath:location.path toPath:destinationPath isFileDelete:YES error:&error];
            self.downloadedFile = dest;
            if (error) { self.downloadError = error; }
        }
        else
        {
            self.downloadError = [NSError errorWithDomain:@"gov.llnl.mp" code:httpResponse.statusCode userInfo:@{NSLocalizedDescriptionKey:@"Error downloading file."}];
        }
        movedURL = self.downloadedFile;
        dError = self.downloadError;
        completion = self.completionHandler;
    } else {
        dispatch_sync(self.stateQueue, ^{
            self.httpStatusCode = status;
            if (httpResponse.statusCode >= 200 && httpResponse.statusCode <= 304)
            {
                NSString *fileName = downloadTask.response.suggestedFilename;
                NSString *destinationPath = [self->downloadDestination stringByAppendingPathComponent:fileName];
                NSError *error = nil;
                NSURL *dest = [self moveDownloadAtPath:location.path toPath:destinationPath isFileDelete:YES error:&error];
                self.downloadedFile = dest;
                if (error) { self.downloadError = error; }
            }
            else
            {
                self.downloadError = [NSError errorWithDomain:@"gov.llnl.mp" code:httpResponse.statusCode userInfo:@{NSLocalizedDescriptionKey:@"Error downloading file."}];
            }
            movedURL = self.downloadedFile;
            dError = self.downloadError;
            completion = self.completionHandler;
        });
    }
    if (completion) completion((int)status, movedURL, dError);
    [self reset];
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler
{

}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler
{
    // accept self-signed SSL certificates
    BOOL allowSelfSigned = self.allowSelfSignedCert;
    SecTrustRef serverTrust = challenge.protectionSpace.serverTrust;
    SecTrustResultType result;
    SecTrustEvaluate(serverTrust, &result);
    
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust])
    {
        NSURLCredential *credential = nil;
        
        if (result == kSecTrustResultProceed || result == kSecTrustResultUnspecified) {
            credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
        } else if (result == kSecTrustResultConfirm || result == kSecTrustResultRecoverableTrustFailure) {
            if (allowSelfSigned) {
                credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
            } else {
                
            }
        }
        completionHandler(NSURLSessionAuthChallengeUseCredential,credential);
    } else {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
    }
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data
{
	
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    __block void (^completion)(int, NSURL *, NSError *) = nil;
    __block NSInteger status = 0;
    __block NSURL *fileURL = nil;
    __block NSError *dError = error;
    if (dispatch_get_specific(kMPDownloadManagerStateQueueKey)) {
        if (error) {
            self.downloadError = error;
        }
        completion = self.completionHandler;
        status = self.httpStatusCode;
        fileURL = self.downloadedFile;
    } else {
        dispatch_sync(self.stateQueue, ^{
            if (error) {
                self.downloadError = error;
            }
            completion = self.completionHandler;
            status = self.httpStatusCode;
            fileURL = self.downloadedFile;
        });
    }
    if (completion) completion((int)status, fileURL, dError);
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

