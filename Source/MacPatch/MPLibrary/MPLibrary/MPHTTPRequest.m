//
//  MPHTTPRequest.m
//  MPAgent
//
//  Created by Charles Heizer on 9/15/17.
//  Copyright © 2017 LLNL. All rights reserved.
//

#import "MPHTTPRequest.h"
#import "MacPatch.h"
#import "MPWSResult.h"
#import "STHTTPRequest.h"
#import <CommonCrypto/CommonHMAC.h>
#import "MPDownloadManager.h"

#undef  ql_component
#define ql_component lcl_cMPHTTPRequest

@interface MPHTTPRequest ()
{
    NSFileManager   *fm;
    MPSettings      *settings;
}

@property (nonatomic)         BOOL      allowSelfSignedCert;
@property (nonatomic, strong) NSArray   *serverArray;
@property (nonatomic)         NSInteger requestCount;
@property (nonatomic, strong) NSString  *clientKey;

@property (nonatomic, weak, readwrite) NSError *error;

@property (nonatomic, retain) NSMutableData *dataToDownload;
@property (nonatomic) float downloadSize;

@end

@implementation MPHTTPRequest
{
	struct {
		unsigned int downloadProgress:1;
	} delegateRespondsTo;
}

@synthesize delegate;
@synthesize serverArray;
@synthesize allowSelfSignedCert;
@synthesize clientKey;
@synthesize error;
@synthesize requestTimeout;
@synthesize resourceTimeout;

- (id)init
{
    self = [super init];
    if (self)
    {
        fm       = [NSFileManager defaultManager];
        settings = [MPSettings sharedInstance];
        
        self.requestCount = -1;
        self.allowSelfSignedCert = NO;
		self.requestTimeout = 10;
		self.resourceTimeout = 60;
        
        [self populateServerArray];
        [self setClientKey:@"NA"];
    }
    
    return self;
}

- (id)initWithAgentPlist
{
    self = [super init];
    if (self)
    {
        fm = [NSFileManager defaultManager];
        
        self.requestCount = -1;
        self.allowSelfSignedCert = NO;
		self.requestTimeout = 10;
		self.resourceTimeout = 60;
        
        [self populateServerArrayUsingAgentPlist];
        [self setClientKey:@"NA"];
    }
    return self;
}

- (void)setDelegate:(id )aDelegate
{
	if (delegate != aDelegate) {
		delegate = aDelegate;
		delegateRespondsTo.downloadProgress = [delegate respondsToSelector:@selector(downloadProgress:)];
	}
}

- (void)populateServerArray
{
    if (!settings.servers || settings.servers.count <= 0)
    {
        [self populateServerArrayUsingAgentPlist];
    }
    else
    {
        self.serverArray = [settings.servers copy];
    }
}

- (void)populateServerArrayUsingAgentPlist
{
    NSMutableArray *_servers = [NSMutableArray new];
    NSDictionary *agentData = [NSDictionary dictionaryWithContentsOfFile:MP_AGENT_DEPL_PLIST];
    
    Server *server1 = [[Server  alloc] init];
    server1.host = agentData[@"MPServerAddress"];
    server1.port = [agentData[@"MPServerPort"] integerValue];
    server1.usessl = [agentData[@"MPServerSSL"] integerValue];
    server1.allowSelfSigned = [agentData[@"MPServerAllowSelfSigned"] integerValue];
    server1.isMaster = 1;
    server1.isProxy = 0;
    [_servers addObject:server1];
    
    if (agentData[@"MPProxyEnabled"])
    {
        if ([agentData[@"MPProxyEnabled"] integerValue] == 1)
        {
            Server *server2 = [[Server  alloc] init];
            server2.host = agentData[@"MPProxyServerAddress"];
            server2.port = [agentData[@"MPProxyServerPort"] integerValue];
            server2.usessl = [agentData[@"MPServerSSL"] integerValue];
            server2.allowSelfSigned = [agentData[@"MPServerAllowSelfSigned"] integerValue];
            server2.isMaster = 0;
            server2.isProxy = 1;
            [_servers addObject:server2];
        }
    }
    self.serverArray = _servers;
}

- (NSString *)createTempDownloadDir:(NSString *)urlPath
{
    NSString *tempFilePath;
    NSString *appName = [[NSProcessInfo processInfo] processName];
    NSString *tempDirectoryTemplate = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.XXXXXX",appName]];
    
    const char *tempDirectoryTemplateCString = [tempDirectoryTemplate fileSystemRepresentation];
    char *tempDirectoryNameCString = (char *)malloc(strlen(tempDirectoryTemplateCString) + 1);
    strcpy(tempDirectoryNameCString, tempDirectoryTemplateCString);
    char *result = mkdtemp(tempDirectoryNameCString);
    if (!result)
    {
        free(tempDirectoryNameCString);
        // handle directory creation failure
        qlerror(@"Error, trying to create tmp directory.");
        return [@"/private/tmp" stringByAppendingPathComponent:appName];
    }
    
    NSString *tempDirectoryPath = [fm stringWithFileSystemRepresentation:tempDirectoryNameCString length:strlen(result)];
    free(tempDirectoryNameCString);
    
    tempFilePath = [tempDirectoryPath stringByAppendingPathComponent:[urlPath lastPathComponent]];
    return tempFilePath;
}

#pragma mark - Public ASyncronus Methdos

- (void)runASyncGET:(NSString *)urlPath completion:(void (^)(MPWSResult *result, NSError *error))completion
{
    
    if (self.requestCount == -1) {
        self.requestCount++;
    } else {
        if (self.requestCount >= (self.serverArray.count - 1)) {
            NSDictionary *userInfo = @{NSLocalizedDescriptionKey: @"Error, could not complete request, failed all servers."};
            NSError *err = [NSError errorWithDomain:@"gov.llnl.mphttprequest" code:1001 userInfo:userInfo];
            completion(nil, err);
            return;
        } else {
            self.requestCount++;
        }
    }
    
    self.allowSelfSignedCert = NO;
    Server *server = [self.serverArray objectAtIndex:self.requestCount];
    if (server.allowSelfSigned == 1)
        self.allowSelfSignedCert = YES;
    
    NSString *url = [NSString stringWithFormat:@"%@://%@:%d%@",server.usessl ? @"https":@"http", server.host, (int)server.port, urlPath];
    qldebug(@"[runASyncGET]URL: %@",url);
    
    __block STHTTPRequest *r = [STHTTPRequest requestWithURLString:url];
    r.allowSelfSignedCert = server.allowSelfSigned;
    
    NSString *ts = [self generateTimeStampForSignature];
    NSString *sg = [self signWSRequest:urlPath timeStamp:ts key:[self readClientKey]];
    [r setHeaderWithName:@"X-API-TS" value:ts];
    [r setHeaderWithName:@"X-API-Signature" value:sg];
    [r setHeaderWithName:@"X-Agent-ID" value:@"MacPatch"];
    
    
    __weak STHTTPRequest *wr = r;
    __block __typeof(self) weakSelf = self;
    
    r.completionDataBlock = ^(NSDictionary *headers, NSData *data)
    {
        __strong STHTTPRequest *sr = wr;
        if(sr == nil) return;
        
        if (sr.responseStatus >= 200 && sr.responseStatus <= 299) {
            completion([[MPWSResult alloc] initWithJSONData:data], nil);
        } else {
            [weakSelf runASyncGET:urlPath completion:(void (^)(MPWSResult *result, NSError *error))completion];
        }
    };
    // Error block
    r.errorBlock = ^(NSError *error)
    {
        [weakSelf runASyncGET:urlPath completion:(void (^)(MPWSResult *result, NSError *error))completion];
    };
    
    [r startAsynchronous];
}

- (void)runASyncPOST:(NSString *)urlPath body:(NSDictionary *)body completion:(void (^)(MPWSResult *result, NSError *error))completion
{
    
    if (self.requestCount == -1) {
        self.requestCount++;
    } else {
        if (self.requestCount >= (self.serverArray.count - 1)) {
            NSDictionary *userInfo = @{NSLocalizedDescriptionKey: @"Error, could not complete request, failed all servers."};
            NSError *err = [NSError errorWithDomain:@"gov.llnl.mphttprequest" code:1001 userInfo:userInfo];
            completion(nil, err);
            return;
        } else {
            self.requestCount++;
        }
    }
    
    self.allowSelfSignedCert = NO;
    Server *server = [self.serverArray objectAtIndex:self.requestCount];
    if (server.allowSelfSigned == 1)
        self.allowSelfSignedCert = YES;
    
    NSString *url = [NSString stringWithFormat:@"%@://%@:%d%@",server.usessl ? @"https":@"http", server.host, (int)server.port, urlPath];
    qldebug(@"[runASyncPOST]URL: %@",url);
    
    __block STHTTPRequest *r = [STHTTPRequest requestWithURLString:url];
    r.allowSelfSignedCert = server.allowSelfSigned;
    r.HTTPMethod = @"POST";
    [r setHeaderWithName:@"content-type" value:@"application/json; charset=utf-8"];
    [r setHeaderWithName:@"Accept" value:@"application/json"];
    [r setHeaderWithName:@"X-Agent-ID" value:@"MacPatch"];
    
    NSError *jerror = nil;
    // Convert body to JSON Data
    NSData  *jsonData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jerror];
    if (!jerror) {
        r.rawPOSTData = jsonData;
    }
    
    NSString *bodyDataStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    NSString *ts = [self generateTimeStampForSignature];
    NSString *sg = [self signWSRequest:bodyDataStr timeStamp:ts key:[self readClientKey]];
    [r setHeaderWithName:@"X-API-TS" value:ts];
    [r setHeaderWithName:@"X-API-Signature" value:sg];
    
    __weak STHTTPRequest *wr = r;
    __block __typeof(self) weakSelf = self;
    
    r.completionDataBlock = ^(NSDictionary *headers, NSData *data)
    {
        __strong STHTTPRequest *sr = wr;
        if(sr == nil) return;
        
        if (sr.responseStatus >= 200 && sr.responseStatus <= 299) {
            completion([[MPWSResult alloc] initWithJSONData:data], nil);
        } else {
            [weakSelf runASyncPOST:urlPath body:body completion:(void (^)(MPWSResult *result, NSError *error))completion];
        }
    };
    // Error block
    r.errorBlock = ^(NSError *error)
    {
        [weakSelf runASyncPOST:urlPath body:body completion:(void (^)(MPWSResult *result, NSError *error))completion];
    };
    
    [r startAsynchronous];
}

- (void)runDownloadRequest:(NSString *)urlPath downloadDirectory:(NSString *)dlDir
                  progress:(NSProgressIndicator *)progressBar progressPercent:(id)progressPercent
                completion:(void (^)(NSString *fileName, NSString *filePath, NSError *error))completion
{
    // Create Download Directory if it does not exist
    if (![fm fileExistsAtPath:dlDir]) {
        [fm createDirectoryAtPath:dlDir withIntermediateDirectories:YES attributes:NULL error:NULL];
    }
    
    // Set File name and File path
    __block NSString *flName = [urlPath lastPathComponent];
    __block NSString *flPath = [dlDir stringByAppendingPathComponent:flName];
    
    if (self.requestCount == -1)
    {
        self.requestCount++;
    } else {
        if (self.requestCount >= (self.serverArray.count - 1))
        {
            NSDictionary *userInfo = @{NSLocalizedDescriptionKey: @"Error, could not download file, failed all servers."};
            NSError *err = [NSError errorWithDomain:@"gov.llnl.mphttprequest" code:1001 userInfo:userInfo];
            completion(nil, nil, err);
            return;
        } else {
            self.requestCount++;
        }
    }
    
    // Create URL
    self.allowSelfSignedCert = NO;
    Server *server = [self.serverArray objectAtIndex:self.requestCount];
    if (server.allowSelfSigned == 1)
        self.allowSelfSignedCert = YES;
    NSString *url = [NSString stringWithFormat:@"%@://%@:%d%@",server.usessl ? @"https":@"http", server.host, (int)server.port, urlPath];
    qlinfo(@"Download URL: %@",url);
    
    __block STHTTPRequest *r = [STHTTPRequest requestWithURLString:url];
    r.timeoutSeconds = 20;
    r.allowSelfSignedCert = server.allowSelfSigned;
    [r setHeaderWithName:@"X-Agent-ID" value:@"MacPatch"];
    
    __weak STHTTPRequest *wr = r;
    __block __typeof(self) weakSelf = self;
    
    // Create if does not exist, if exists then delete and create
    if (![fm fileExistsAtPath:flPath])
    {
        [fm createFileAtPath:flPath contents:nil attributes:nil];
    } else {
        [fm removeItemAtPath:flPath error:NULL];
        [fm createFileAtPath:flPath contents:nil attributes:nil];
    }
    
    r.downloadProgressBlock = ^(NSData *dataJustReceived, int64_t totalBytesReceived, int64_t totalBytesExpectedToReceive)
    {
        // Calculate Download Percentage
        // Return as NSProgressIndicator and NSTextField
        float progress = ((float)totalBytesReceived) / totalBytesExpectedToReceive;
        double percentComplete = progress*100.0;
        
        qlinfo(@"Downloading file %d",(int)percentComplete);
        
        if (progressPercent) {
            [progressPercent setStringValue:[NSString stringWithFormat:@"%d",(int)percentComplete]];
        }
        if (progressBar) {
            [progressBar setDoubleValue:percentComplete];
        }
        
        // Write Streamed Data to file
        NSFileHandle *file1 = [NSFileHandle fileHandleForUpdatingAtPath:flPath];
        [file1 seekToEndOfFile];
        [file1 writeData:dataJustReceived];
        [file1 closeFile];
    };
    
    r.completionDataBlock = ^(NSDictionary *headers, NSData *data)
    {
        __strong STHTTPRequest *sr = wr;
        if(sr == nil) return;
        completion(flName, flPath,  nil);
    };
    // Error block
    r.errorBlock = ^(NSError *err)
    {
        qlerror(@"File download error %@", err.localizedDescription);
        [weakSelf runDownloadRequest:urlPath downloadDirectory:(NSString *)dlDir
                            progress:progressBar progressPercent:progressPercent
                          completion:(void (^)(NSString *fileName, NSString *filePath, NSError *error))completion];
    };
    
    qlinfo(@"startAsynchronous");
    [r startAsynchronous];
}

#pragma mark - Public Syncronus Methdos
- (MPWSResult *)runSyncGET:(NSString *)urlPath
{
    return [self runSyncGET:urlPath body:nil];
}

- (MPWSResult *)runSyncGET:(NSString *)urlPath body:(NSDictionary *)body
{
    MPWSResult *wsResult = nil;
    NSString *url;
    
    for (Server *server in self.serverArray)
    {
        self.allowSelfSignedCert = NO;
        if (server.allowSelfSigned == 1)
            self.allowSelfSignedCert = YES;
        
        url = [NSString stringWithFormat:@"%@://%@:%d%@",server.usessl ? @"https":@"http", server.host, (int)server.port, urlPath];
        qlinfo(@"URL: %@",url);
        wsResult = [self syncronusGETWithURL:url body:body];
        if ((int)wsResult.statusCode == 200 || (int)wsResult.statusCode == 201) {
            qldebug(@"WSResult: %@",wsResult.toDictionary);
            break;
        }
    }
    
    return wsResult;
}

- (MPWSResult *)runSyncPOST:(NSString *)urlPath body:(NSDictionary *)body
{
    MPWSResult *wsResult = nil;
    NSString *url;
    for (Server *server in self.serverArray)
    {
        self.allowSelfSignedCert = NO;
        if (server.allowSelfSigned == 1)
            self.allowSelfSignedCert = YES;
        
        qldebug(@"[runSyncPOST][server]: %@",server.toDictionary);
        url = [NSString stringWithFormat:@"%@://%@:%d%@",server.usessl ? @"https":@"http", server.host, (int)server.port, urlPath];
        qldebug(@"[runSyncPOST] URL: %@",url);
        wsResult = [self syncronusPOSTWithURL:url body:body];
        if ((int)wsResult.statusCode == 200 || (int)wsResult.statusCode == 201) {
            qldebug(@"WSResult: %@",wsResult.toDictionary);
            break;
        }
    }
    
    return wsResult;
}


- (NSString *)runSyncFileDownload:(NSString *)urlPath downloadDirectory:(NSString *)dlDir error:(NSError * __autoreleasing *)err
{
    qlinfo(@"[runSyncFileDownload][urlPath], %@", urlPath);
    
    // Create Download Directory if it does not exist
    if (![fm fileExistsAtPath:dlDir]) {
        [fm createDirectoryAtPath:dlDir withIntermediateDirectories:YES attributes:NULL error:NULL];
    }
    
    // Set File name and File path
    __block NSString *flName = [urlPath lastPathComponent];
    __block NSString *flPath = [dlDir stringByAppendingPathComponent:flName];
    
    // If downloaded file exists, remove it first
    if ([fm fileExistsAtPath:flPath]) {
        [fm removeItemAtPath:flPath error:NULL];
    }
    
    // requestCount is the server index of the servers array
    // this gets incremented on failed attempts
    if (self.requestCount == -1)
	{
        self.requestCount++;
    }
	else
	{
        if (self.requestCount >= (self.serverArray.count - 1))
		{
            NSDictionary *userInfo = @{NSLocalizedDescriptionKey: @"Error, could not download file, failed all servers."};
            NSError *srverr = [NSError errorWithDomain:@"gov.llnl.mphttprequest" code:1001 userInfo:userInfo];
            if (err != NULL) *err = srverr;
            return nil;
        }
		else
		{
            self.requestCount++;
        }
    }
	
    Server *server = [self.serverArray objectAtIndex:self.requestCount];
	self.allowSelfSignedCert = (server.allowSelfSigned == 1) ? YES : NO;
	
    NSString *url = [NSString stringWithFormat:@"%@://%@:%d%@",server.usessl ? @"https":@"http", server.host, (int)server.port, urlPath];
    qlinfo(@"URL: %@",url);
    
    __block __typeof(self) weakSelf = self;
    
    dispatch_semaphore_t    sem;
    __block NSString        *dlFilePath = [dlDir stringByAppendingPathComponent:[urlPath lastPathComponent]];
    __block NSURLResponse   *responsePtr;
    __block NSError         *urlErr = nil;
    
    sem = dispatch_semaphore_create(0);
    
    NSURLSessionDownloadTask *downloadTask;
    NSURLSessionConfiguration *sessionConfiguration = [NSURLSessionConfiguration defaultSessionConfiguration];
	sessionConfiguration.timeoutIntervalForRequest = 10;
	sessionConfiguration.timeoutIntervalForResource = 120.0;
	
    NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfiguration];
    
    downloadTask = [session downloadTaskWithURL:[NSURL URLWithString:url] completionHandler:^(NSURL *location, NSURLResponse *response, NSError *dlerr)
	{
		NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *) response;
		qlinfo(@"HTTP Status code: %ld", (long)[httpResponse statusCode]);
		if (dlerr || [httpResponse statusCode] == 404)
		{
			urlErr = dlerr;
			qlerror(@"File download error %@", self->error.localizedDescription);
			[weakSelf runSyncFileDownload:urlPath downloadDirectory:dlDir error:err];
		}
		else
		{
			if (responsePtr != NULL) {
				responsePtr = response;
			}

			qlinfo(@"dlFilePath, %@", dlFilePath);
			qlinfo(@"location, %@", location.path);
			
			NSFileManager *fileManager = [NSFileManager defaultManager];
			NSError *cperror;
			BOOL fileOKToMove = YES;
			if ([fileManager fileExistsAtPath:dlFilePath]) {
				cperror = nil;
				[fileManager removeItemAtPath:dlFilePath error:&cperror];
				if (cperror) {
					fileOKToMove = NO;
					qlerror(@"Error removing old downloaded file.");
					qlerror(@"%@",cperror.localizedDescription);
				}
			}
			
			//moving the file from temp location to app's own directory
			if (fileOKToMove)
			{
				cperror = nil;
				BOOL fileCopied = [fileManager moveItemAtPath:[location path] toPath:dlFilePath error:&cperror];
				
				if (cperror) {
					qlinfo(@"cperror, %@", cperror.localizedDescription);
				}
				
				NSLog(fileCopied ? @"Yes" : @"No");
			}
		}

		dispatch_semaphore_signal(sem);
   }];
    
    [downloadTask resume];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    return dlFilePath;
}

- (NSString *)runSyncFileDownloadAlt:(NSString *)urlPath downloadDirectory:(NSString *)dlDir error:(NSError * __autoreleasing *)err
{
	qlinfo(@"[runSyncFileDownloadAlt][urlPath], %@", urlPath);
	[self->delegate downloadProgress:@"Configuring download for %@",[urlPath lastPathComponent]];
	// Create Download Directory if it does not exist
	if (![fm fileExistsAtPath:dlDir]) {
		[fm createDirectoryAtPath:dlDir withIntermediateDirectories:YES attributes:NULL error:NULL];
	}
	
	// Set File name and File path
	__block NSString *flName = [urlPath lastPathComponent];
	__block NSString *flPath = [dlDir stringByAppendingPathComponent:flName];
	
	// If downloaded file exists, remove it first
	if ([fm fileExistsAtPath:flPath]) {
		[fm removeItemAtPath:flPath error:NULL];
	}
	
	// requestCount is the server index of the servers array
	// this gets incremented on failed attempts
	if (self.requestCount == -1)
	{
		self.requestCount++;
	}
	else
	{
		if (self.requestCount >= (self.serverArray.count - 1))
		{
			NSDictionary *userInfo = @{NSLocalizedDescriptionKey: @"Error, could not download file, failed all servers."};
			NSError *srverr = [NSError errorWithDomain:@"gov.llnl.mphttprequest" code:1001 userInfo:userInfo];
			if (err != NULL) *err = srverr;
			return nil;
		}
		else
		{
			self.requestCount++;
		}
	}
	
	Server *server = [self.serverArray objectAtIndex:self.requestCount];
	self.allowSelfSignedCert = (server.allowSelfSigned == 1) ? YES : NO;
	
	NSString *url = [NSString stringWithFormat:@"%@://%@:%d%@",server.usessl ? @"https":@"http", server.host, (int)server.port, urlPath];
	qlinfo(@"URL: %@",url);
	
	//__block __typeof(self) weakSelf = self;
	__block BOOL didFail = NO;
	dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
	MPDownloadManager *dm = [MPDownloadManager sharedManager];
	//MPDownloadManager *dm = [[MPDownloadManager alloc] init];
	dm.downloadUrl = url;
	dm.downloadDestination = dlDir;
	
	dm.progressHandler = ^(double progressPercent, double sizeDownloaded, double sizeComplete)
	{
		dispatch_async(dispatch_get_main_queue(), ^{
			NSString *progStr = [NSString stringWithFormat:@"%i\uFF05 Downloaded",(int)progressPercent];
			//qldebug(@"%@",progStr);
			if ((int)progressPercent % 5 == 0) qlinfo(@"%@",progStr);
			[self->delegate downloadProgress:progStr];
		});
	};
	dm.completionHandler = ^(int httpStatusCode, NSURL *downloadedFile, NSError *downloadError)
	{
		if (downloadError) {
			qlerror(@"%@",downloadError.localizedDescription);
			didFail = YES;
			dispatch_semaphore_signal(semaphore);
		}
		
		qlinfo(@"dm.completionHandler[httpStatusCode]: %d",httpStatusCode);
		if (httpStatusCode >= 200 && httpStatusCode <= 304) {
			didFail = NO;
		} else {
			didFail = YES;
		}
		dispatch_semaphore_signal(semaphore);
	};
	
	[dm beginDownload];
	dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
	if (didFail) {
		[self runSyncFileDownloadAlt:urlPath downloadDirectory:dlDir error:err];
	}
	
	
	return @"OK";
}

// Used to get small images from MP servers
- (NSData *)dataForURLPath:(NSString *)aURLPath
{
	NSData *result = nil;
	NSString *url;
	for (Server *server in self.serverArray)
	{
		self.allowSelfSignedCert = NO;
		if (server.allowSelfSigned == 1)
			self.allowSelfSignedCert = YES;
		
		url = [NSString stringWithFormat:@"%@://%@:%d%@",server.usessl ? @"https":@"http", server.host, (int)server.port, aURLPath];
		qlinfo(@"URL: %@",url);
		//
		NSError *dataErr = nil;
		result = [NSData dataWithContentsOfURL:[NSURL URLWithString:url] options:NSDataReadingMappedIfSafe error:&dataErr];
		if (!dataErr) {
			break;
		}
	}
	
	return result;
}

#pragma mark - Private Methdos
- (MPWSResult *)syncronusGETWithURL:(NSString *)aURL body:(NSDictionary *)body
{
    __block MPWSResult *res = nil;
    
    // Result
    __block NSInteger statusCode = 9999;
    NSError *_error = nil;
    
    // Convert body to JSON Data
    NSData  *jsonData;
    if (body) {
        jsonData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&_error];
        if (_error) {
            qlerror(@"%@",_error.localizedDescription);
            error = _error;
            return res;
        }
    }
    
    // Create URLRequest
    NSURL *url = [NSURL URLWithString:aURL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    [request setValue:@"MacPatch" forHTTPHeaderField:@"X-Agent-ID"];
    
    NSString *sg;
    NSString *ts = [self generateTimeStampForSignature];
    
    // If Get Request with out a body pass nil for the dictionary
    if (body != nil) {
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
        [request setHTTPBody:jsonData];
        
        NSString *bodyDataStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        sg = [self signWSRequest:bodyDataStr timeStamp:ts key:[self readClientKey]];
    } else {
        sg = [self signWSRequest:[url path] timeStamp:ts key:[self readClientKey]];
    }
    
    [request setValue:[self generateTimeStampForSignature] forHTTPHeaderField:@"X-API-TS"];
    [request setValue:sg forHTTPHeaderField:@"X-API-Signature"];
    
    // Create session for request
    NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
    sessionConfig.allowsCellularAccess = YES;
    sessionConfig.timeoutIntervalForRequest = self.requestTimeout;
    sessionConfig.timeoutIntervalForResource = self.resourceTimeout;
    sessionConfig.HTTPMaximumConnectionsPerHost = 1;
    
    __block NSError *sesErr = nil;
    __block NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig delegate:self delegateQueue:nil];
    
    // Create semaphore, to wait for block to end
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    // Make Request Task
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *_error)
                                  {
                                      if (!_error)
                                      {
                                          NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
                                          statusCode = httpResponse.statusCode;
                                          res = [[MPWSResult alloc] initWithJSONData:data];
                                          res.statusCode = statusCode;
                                      }
                                      else
                                      {
                                          qlerror(@"Error: %@", _error.localizedDescription);
                                          sesErr = _error;
                                      }
                                      
                                      dispatch_semaphore_signal(semaphore);
                                  }];
    // Run Task
    [task resume];
    
    // Wait for semaphore signal
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    if (sesErr) {
        error = sesErr;
    }
    
    return res;
}

- (MPWSResult *)syncronusPOSTWithURL:(NSString *)aURL body:(NSDictionary *)body
{
    __block MPWSResult *res = nil;
    
    // Result
    __block NSInteger statusCode = 9999;
    NSError *jerror = nil;
    NSData  *jsonData;
    
    // Create URLRequest
    NSURL *url = [NSURL URLWithString:aURL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"MacPatch" forHTTPHeaderField:@"X-Agent-ID"];
    
    // Generate Signture
    NSString *sg;
    NSString *ts = [self generateTimeStampForSignature];
    
    // If Request with out a body pass nil for the dictionary
    if (body != nil)
    {
        // Convert body to JSON Data
        jsonData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jerror];
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
        if (!jerror)
        {
            [request setHTTPBody:jsonData];
            NSString *bodyDataStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            sg = [self signWSRequest:bodyDataStr timeStamp:ts key:[self readClientKey]];
        }
    } else {
        sg = [self signWSRequest:[url path] timeStamp:ts key:[self readClientKey]];
    }
    
    [request setValue:[self generateTimeStampForSignature] forHTTPHeaderField:@"X-API-TS"];
    [request setValue:sg forHTTPHeaderField:@"X-API-Signature"];
    
    // Create session for request
    NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
    sessionConfig.allowsCellularAccess = YES;
    sessionConfig.timeoutIntervalForRequest = self.requestTimeout;
    sessionConfig.timeoutIntervalForResource = self.resourceTimeout;
    sessionConfig.HTTPMaximumConnectionsPerHost = 1;
    
    __block NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig
                                                                  delegate:self
                                                             delegateQueue:nil];
    // Create semaphore, to wait for block to end
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    // Make Request Task
    NSURLSessionDataTask *task;
    task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *err)
    {
        if (!err)
        {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            statusCode = httpResponse.statusCode;
            res = [[MPWSResult alloc] initWithJSONData:data];
            res.statusCode = statusCode;
        }
        else
        {
            qlerror(@"Error: %@", err.localizedDescription);
        }

        dispatch_semaphore_signal(semaphore);
    }];
    
    // Run Task
    [task resume];
    // Wait for semaphore signal
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    
    return res;
}

- (NSString *)generateTimeStampForSignature
{
    NSDateFormatter *format = [[NSDateFormatter alloc] init];
    [format setTimeZone:[NSTimeZone timeZoneWithName:@"UTC"]];
    [format setDateFormat:@"yyyy-MM-dd HH:mm:00"];
    NSDate *now = [NSDate date];
    NSString *nsstr = [format stringFromDate:now];
    return nsstr;
}

- (NSString *)signWSRequest:(NSString *)aData timeStamp:(NSString *)aTimeStamp key:(NSString *)aKey
{
    qldebug(@"Key for Signature: (%@)",[aKey substringFromIndex:MAX((int)[aKey length]-4, 0)]);
    qldebug(@"Data for Signature: (%@)",aData);
    qldebug(@"Time Stamp for Signature: (%@)",aTimeStamp);
    
    NSString *aStrToSign = [NSString stringWithFormat:@"%@-%@",aData,aTimeStamp];
    
    qltrace(@"String to Sign: (%@)",aStrToSign);
    
    const char *cKey  = [aKey cStringUsingEncoding:NSUTF8StringEncoding];
    const char *cData = [aStrToSign cStringUsingEncoding:NSUTF8StringEncoding];
    
    if (!cData || !cKey) {
        qlerror(@"Data or key to sign is null.");
        return @"";
    }
    
    unsigned char cHMAC[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, cKey, strlen(cKey), cData, strlen(cData), cHMAC);
    
    NSData *resData = [[NSData alloc] initWithBytes:cHMAC length:sizeof(cHMAC)];
    //NSString *resStr = [[NSString alloc] initWithData:resData encoding:NSUTF8StringEncoding];
    
    NSString *result = [resData description];
    result = [result stringByReplacingOccurrencesOfString:@" " withString:@""];
    result = [result stringByReplacingOccurrencesOfString:@"<" withString:@""];
    result = [result stringByReplacingOccurrencesOfString:@">" withString:@""];
    
    qldebug(@"Signature for request: %@",result);
    return result;
}

- (NSString *)readClientKey
{
	/* CEH
    if ([self.clientKey isEqualToString:@"NA"]) {
        [self setClientKey:[self getClientKeyFromKeychain]];
        return self.clientKey;
    } else {
        return self.clientKey;
    }
    */
    return @"NA";
}

- (NSString *)getClientKeyFromKeychain
{
	/* CEH
    NSError *err = nil;
    MPSimpleKeychain *skc = [[MPSimpleKeychain alloc] initWithKeychainFile:MP_KEYCHAIN_FILE];
    MPKeyItem *keyItem = [skc retrieveKeyItemForService:kMPClientService error:&err];
    if (err) {
        logit(lcl_vWarning,@"getClientKey: %@",err.localizedDescription);
        return @"NA";
    }
    return keyItem.secret;
	 */
	return @"BOB";
}

#pragma mark - NSURLSessionDelegate

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler
{
    // accept self-signed SSL certificates
    SecTrustRef serverTrust = challenge.protectionSpace.serverTrust;
    SecTrustResultType result;
    SecTrustEvaluate(serverTrust, &result);
    
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust])
    {
        NSURLCredential *credential = nil;
        
        if (result == kSecTrustResultProceed || result == kSecTrustResultUnspecified) {
            credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
        } else if (result == kSecTrustResultConfirm || result == kSecTrustResultRecoverableTrustFailure) {
            if (self.allowSelfSignedCert) {
                credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
            } else {
                
            }
        }
        completionHandler(NSURLSessionAuthChallengeUseCredential,credential);
    } else {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
    }
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler
{
	completionHandler(NSURLSessionResponseAllow);
	_downloadSize=[response expectedContentLength];
	_dataToDownload=[[NSMutableData alloc]init];
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data
{
	[_dataToDownload appendData:data];
	float progress = [ _dataToDownload length ]/_downloadSize;
	
	if([delegate respondsToSelector:@selector(downloadProgress:)])
	{
		NSString *progStr = [NSString stringWithFormat:@"%i\uFF05 Downloaded",(int)progress];
		[delegate downloadProgress:progStr];
	}
}

-(void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
	qlerror(@"completed; error: %@", error);
}


@end
