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
#import "MPDownloadManager.h"
static const void *kMPHTTPRequestStateQueueKey = &kMPHTTPRequestStateQueueKey;
#import <CommonCrypto/CommonHMAC.h>

#undef  ql_component
#define ql_component lcl_cMPHTTPRequest

@interface MPHTTPRequest ()
{
    NSFileManager   *fm;
    MPSettings      *settings;
}

@property (nonatomic, strong) dispatch_queue_t stateQueue;
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
        {
            dispatch_queue_t q = dispatch_queue_create("gov.llnl.mphttprequest.state", DISPATCH_QUEUE_SERIAL);
            dispatch_queue_set_specific(q, kMPHTTPRequestStateQueueKey, (void *)kMPHTTPRequestStateQueueKey, NULL);
            self.stateQueue = q;
        }
        
        fm       = [NSFileManager defaultManager];
        settings = [MPSettings sharedInstance];

        if (dispatch_get_specific(kMPHTTPRequestStateQueueKey)) {
            self.requestCount = -1;
            self.allowSelfSignedCert = NO;
        } else {
            dispatch_sync(self.stateQueue, ^{
                self.requestCount = -1;
                self.allowSelfSignedCert = NO;
            });
        }

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
        {
            dispatch_queue_t q = dispatch_queue_create("gov.llnl.mphttprequest.state", DISPATCH_QUEUE_SERIAL);
            dispatch_queue_set_specific(q, kMPHTTPRequestStateQueueKey, (void *)kMPHTTPRequestStateQueueKey, NULL);
            self.stateQueue = q;
        }

        fm = [NSFileManager defaultManager];

        if (dispatch_get_specific(kMPHTTPRequestStateQueueKey)) {
            self.requestCount = -1;
            self.allowSelfSignedCert = NO;
        } else {
            dispatch_sync(self.stateQueue, ^{
                self.requestCount = -1;
                self.allowSelfSignedCert = NO;
            });
        }

		self.requestTimeout = 10;
		self.resourceTimeout = 60;
        
        [self populateServerArrayUsingAgentPlist];
        [self setClientKey:@"NA"];
    }
    return self;
}

- (void)setDelegate:(id )aDelegate
{
    if (dispatch_get_specific(kMPHTTPRequestStateQueueKey)) {
        if (delegate != aDelegate) {
            delegate = aDelegate;
            delegateRespondsTo.downloadProgress = [delegate respondsToSelector:@selector(downloadProgress:)];
        }
    } else {
        dispatch_sync(self.stateQueue, ^{
            if (delegate != aDelegate) {
                delegate = aDelegate;
                delegateRespondsTo.downloadProgress = [delegate respondsToSelector:@selector(downloadProgress:)];
            }
        });
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
		// [settings refresh]; // Removed per instructions

        NSArray *serversSnapshot = [settings.servers copy];
        if (dispatch_get_specific(kMPHTTPRequestStateQueueKey)) {
            self.serverArray = serversSnapshot;
            self.requestCount = -1;
        } else {
            dispatch_sync(self.stateQueue, ^{
                self.serverArray = serversSnapshot;
                self.requestCount = -1;
            });
        }
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
    if (dispatch_get_specific(kMPHTTPRequestStateQueueKey)) {
        self.serverArray = _servers;
        self.requestCount = -1;
    } else {
        dispatch_sync(self.stateQueue, ^{
            self.serverArray = _servers;
            self.requestCount = -1;
        });
    }
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
    __block NSInteger index = -1;
    __block NSArray *servers = nil;
    if (dispatch_get_specific(kMPHTTPRequestStateQueueKey)) {
        if (self.requestCount == -1) {
            self.requestCount = 0;
        } else {
            self.requestCount++;
        }
        index = self.requestCount;
        servers = [self.serverArray copy];
    } else {
        dispatch_sync(self.stateQueue, ^{
            if (self.requestCount == -1) {
                self.requestCount = 0;
            } else {
                self.requestCount++;
            }
            index = self.requestCount;
            servers = [self.serverArray copy];
        });
    }
    if (index < 0 || index >= (NSInteger)servers.count) {
        NSDictionary *userInfo = @{NSLocalizedDescriptionKey: @"Error, could not complete request, failed all servers."};
        NSError *err = [NSError errorWithDomain:@"gov.llnl.mphttprequest" code:1001 userInfo:userInfo];
        completion(nil, err);
        return;
    }
    
    Server *server = [servers objectAtIndex:index];
    
    __block BOOL allowSelfSigned = NO;
    if (dispatch_get_specific(kMPHTTPRequestStateQueueKey)) {
        self.allowSelfSignedCert = (server.allowSelfSigned == 1);
        allowSelfSigned = self.allowSelfSignedCert;
    } else {
        dispatch_sync(self.stateQueue, ^{
            self.allowSelfSignedCert = (server.allowSelfSigned == 1);
            allowSelfSigned = self.allowSelfSignedCert;
        });
    }
    
    NSString *url = [NSString stringWithFormat:@"%@://%@:%d%@",server.usessl ? @"https":@"http", server.host, (int)server.port, urlPath];
    qldebug(@"[runASyncGET]URL: %@",url);
    
    __block STHTTPRequest *r = [STHTTPRequest requestWithURLString:url];
    r.allowSelfSignedCert = allowSelfSigned;
    
    NSString *ts = [self generateTimeStampForSignature];
    NSString *sg = [self signWSRequest:urlPath timeStamp:ts key:[self readClientKey]];
    [r setHeaderWithName:@"X-API-TS" value:ts];
    [r setHeaderWithName:@"X-API-Signature" value:sg];
    [r setHeaderWithName:@"X-Agent-ID" value:@"MacPatch"];
	[r setHeaderWithName:@"X-Agent-VER" value:settings.clientVer];
    [r setHeaderWithName:@"User-Agent" value:[NSString stringWithFormat:@"MacPatch/%@ (%@)", settings.clientVer, [[NSProcessInfo processInfo] processName]]];
    
    
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
    __block NSInteger index = -1;
    __block NSArray *servers = nil;
    if (dispatch_get_specific(kMPHTTPRequestStateQueueKey)) {
        if (self.requestCount == -1) {
            self.requestCount = 0;
        } else {
            self.requestCount++;
        }
        index = self.requestCount;
        servers = [self.serverArray copy];
    } else {
        dispatch_sync(self.stateQueue, ^{
            if (self.requestCount == -1) {
                self.requestCount = 0;
            } else {
                self.requestCount++;
            }
            index = self.requestCount;
            servers = [self.serverArray copy];
        });
    }
    if (index < 0 || index >= (NSInteger)servers.count) {
        NSDictionary *userInfo = @{NSLocalizedDescriptionKey: @"Error, could not complete request, failed all servers."};
        NSError *err = [NSError errorWithDomain:@"gov.llnl.mphttprequest" code:1001 userInfo:userInfo];
        completion(nil, err);
        return;
    }
    
    Server *server = [servers objectAtIndex:index];
    
    __block BOOL allowSelfSigned = NO;
    if (dispatch_get_specific(kMPHTTPRequestStateQueueKey)) {
        self.allowSelfSignedCert = (server.allowSelfSigned == 1);
        allowSelfSigned = self.allowSelfSignedCert;
    } else {
        dispatch_sync(self.stateQueue, ^{
            self.allowSelfSignedCert = (server.allowSelfSigned == 1);
            allowSelfSigned = self.allowSelfSignedCert;
        });
    }
    
    NSString *url = [NSString stringWithFormat:@"%@://%@:%d%@",server.usessl ? @"https":@"http", server.host, (int)server.port, urlPath];
    qldebug(@"[runASyncPOST]URL: %@",url);
    
    __block STHTTPRequest *r = [STHTTPRequest requestWithURLString:url];
    r.allowSelfSignedCert = allowSelfSigned;
    r.HTTPMethod = @"POST";
    [r setHeaderWithName:@"content-type" value:@"application/json; charset=utf-8"];
    [r setHeaderWithName:@"Accept" value:@"application/json"];
    [r setHeaderWithName:@"X-Agent-ID" value:@"MacPatch"];
	[r setHeaderWithName:@"X-Agent-VER" value:settings.clientVer];
    [r setHeaderWithName:@"User-Agent" value:[NSString stringWithFormat:@"MacPatch/%@ (%@)", settings.clientVer, [[NSProcessInfo processInfo] processName]]];
    
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

#pragma mark - Public Syncronus Methdos
- (MPWSResult *)runSyncGET:(NSString *)urlPath
{
    return [self runSyncGET:urlPath body:nil];
}

- (MPWSResult *)runSyncGET:(NSString *)urlPath body:(NSDictionary *)body
{
    MPWSResult *wsResult = nil;
    NSString *url;

    __block NSArray *servers = nil;
    if (dispatch_get_specific(kMPHTTPRequestStateQueueKey)) {
        servers = [self.serverArray copy];
    } else {
        dispatch_sync(self.stateQueue, ^{
            servers = [self.serverArray copy];
        });
    }
    
    for (Server *server in servers)
    {
        BOOL allowSelfSigned = (server.allowSelfSigned == 1);

        url = [NSString stringWithFormat:@"%@://%@:%d%@",server.usessl ? @"https":@"http", server.host, (int)server.port, urlPath];
        qlinfo(@"URL: %@",url);
        wsResult = [self syncronusGETWithURL:url body:body];
		if ((int)wsResult.statusCode >= 200 && (int)wsResult.statusCode <= 210) {
            //qldebug(@"WSResult: %@",wsResult.toDictionary);
            break;
        }
    }
    
    return wsResult;
}

- (MPWSResult *)runSyncPOST:(NSString *)urlPath body:(NSDictionary *)body
{
    MPWSResult *wsResult = nil;
    NSString *url;

    __block NSArray *servers = nil;
    if (dispatch_get_specific(kMPHTTPRequestStateQueueKey)) {
        servers = [self.serverArray copy];
    } else {
        dispatch_sync(self.stateQueue, ^{
            servers = [self.serverArray copy];
        });
    }
    
    for (Server *server in servers)
    {
        BOOL allowSelfSigned = (server.allowSelfSigned == 1);
        
        qldebug(@"[runSyncPOST][server]: %@",server.toDictionary);
        url = [NSString stringWithFormat:@"%@://%@:%d%@",server.usessl ? @"https":@"http", server.host, (int)server.port, urlPath];
        qldebug(@"[runSyncPOST] URL: %@",url);
        wsResult = [self syncronusPOSTWithURL:url body:body];
		qldebug(@"[runSyncPOST][result]: %d",(int)wsResult.statusCode);
        if ((int)wsResult.statusCode >= 200 && (int)wsResult.statusCode <= 210) {
            //qldebug(@"WSResult: %@",wsResult.toDictionary);
            break;
        }
    }
    
    return wsResult;
}

- (NSString *)runSyncFileDownload:(NSString *)urlPath downloadDirectory:(NSString *)dlDir error:(NSError * __autoreleasing *)err
{
    return [self runSyncFileDownload:urlPath downloadDirectory:dlDir fromCloudServer:FALSE error:err];
}


- (NSString *)runSyncFileDownload:(NSString *)urlPath downloadDirectory:(NSString *)dlDir fromCloudServer:(BOOL)fromCloud error:(NSError * __autoreleasing *)err
{
	int srvErrs = 0;
	NSError *dlerror = nil;
	NSString *url;
	NSString *dlFilePath = [dlDir stringByAppendingPathComponent:[urlPath lastPathComponent]];
	NSString *res;
    
    if (fromCloud) {
        qldebug(@"[runSyncFileDownload][fromCloud] dlFilePath: %@",dlFilePath);
        qlinfo(@"[runSyncFileDownload][fromCloud] URL: %@",urlPath);
        dlerror = nil;
        // Set allowSelfSignedCert to NO for cloud downloads
        if (dispatch_get_specific(kMPHTTPRequestStateQueueKey)) {
            self.allowSelfSignedCert = NO;
        } else {
            dispatch_sync(self.stateQueue, ^{
                self.allowSelfSignedCert = NO;
            });
        }
        res = [self runSyncFileDownloadFromServer:urlPath downloadDirectory:dlDir error:&dlerror];
        qldebug(@"[runSyncFileDownloadFromServer] result: %@",res);
        if (dlerror) {
            qlerror(@"%@",dlerror.localizedDescription);
            srvErrs++;
        }
    } else {
        __block NSArray *servers = nil;
        if (dispatch_get_specific(kMPHTTPRequestStateQueueKey)) {
            servers = [self.serverArray copy];
        } else {
            dispatch_sync(self.stateQueue, ^{
                servers = [self.serverArray copy];
            });
        }

        for (Server *s in servers)
        {
            BOOL allowSelfSigned = (s.allowSelfSigned == 1);
            // Set allowSelfSignedCert on the state queue for thread safety
            if (dispatch_get_specific(kMPHTTPRequestStateQueueKey)) {
                self.allowSelfSignedCert = allowSelfSigned;
            } else {
                dispatch_sync(self.stateQueue, ^{
                    self.allowSelfSignedCert = allowSelfSigned;
                });
            }
            
            url = [NSString stringWithFormat:@"%@://%@:%d%@",s.usessl ? @"https":@"http", s.host, (int)s.port, urlPath];
            qlinfo(@"URL: %@",url);
            dlerror = nil;
            res = [self runSyncFileDownloadFromServer:url downloadDirectory:dlDir error:&dlerror];
            qldebug(@"[runSyncFileDownloadFromServer] result: %@",res);
            if (dlerror) {
                qlerror(@"%@",dlerror.localizedDescription);
                srvErrs++;
                continue;
            } else {
                srvErrs = 0;
                break;
            }
        }
    }

	if (srvErrs > 0) {
		dlFilePath = @"ERR";
		NSDictionary *userInfo = @{NSLocalizedDescriptionKey: @"Error, could not download file, failed all servers."};
		NSError *sError = [NSError errorWithDomain:@"gov.llnl.mphttprequest" code:1001 userInfo:userInfo];
		if (err != NULL) *err = sError;
	}
	return dlFilePath;
}

- (NSString *)runSyncFileDownloadFromServer:(NSString *)urlPath downloadDirectory:(NSString *)dlDir error:(NSError * __autoreleasing *)err
{
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
	
	// Safely get allowSelfSignedCert value
	__block BOOL allowSelfSigned = NO;
	if (dispatch_get_specific(kMPHTTPRequestStateQueueKey)) {
		allowSelfSigned = self.allowSelfSignedCert;
	} else {
		dispatch_sync(self.stateQueue, ^{
			allowSelfSigned = self.allowSelfSignedCert;
		});
	}
	
	__block NSString *curPercent = @"";
	__block NSString *dlFile = @"ERR";
	dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
	MPDownloadManager *dm = [MPDownloadManager sharedManager];
    dm.allowSelfSignedCert = allowSelfSigned;
	dm.downloadUrl = urlPath;
	dm.downloadDestination = dlDir;
	
	dm.progressHandler = ^(double progressPercent, double sizeDownloaded, double sizeComplete)
	{
		dispatch_async(dispatch_get_main_queue(), ^{
			NSString *progStr = [NSString stringWithFormat:@"%i\uFF05 Downloaded",(int)progressPercent];
			if ((int)progressPercent % 5 == 0) {
				if (![curPercent isEqualToString:[NSString stringWithFormat:@"%i",(int)progressPercent]]) {
					qlinfo(@"%@",progStr);
					curPercent = [NSString stringWithFormat:@"%i",(int)progressPercent];
				}
			}
			[self->delegate downloadProgress:progStr];
		});
	};
	dm.completionHandler = ^(int httpStatusCode, NSURL *downloadedFile, NSError *downloadError)
	{
		if (downloadError)
		{
			qlerror(@"Error %d. File download error %@", httpStatusCode, downloadError.localizedDescription);
			if (err != NULL) *err = downloadError;
			dispatch_semaphore_signal(semaphore);
		}
		else
		{
			qlinfo(@"dm.completionHandler[httpStatusCode]: %d",httpStatusCode);
			if (httpStatusCode >= 200 && httpStatusCode <= 304) {
				dlFile = [downloadedFile path];
			} else {
				NSString *errStr = [NSString stringWithFormat:@"Error, status code %d",httpStatusCode];
				if (err != NULL) *err = [NSError errorWithDomain:@"gov.llnl.mphttprequest" code:1001 userInfo:@{NSLocalizedDescriptionKey:errStr}];
			}
		}
		dispatch_semaphore_signal(semaphore);
	};
	
	[dm beginDownload];
	dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
	
	return dlFile;
}

- (NSString *)runSyncFileDownloadAltOrig:(NSString *)urlPath downloadDirectory:(NSString *)dlDir error:(NSError * __autoreleasing *)err
{
	qlinfo(@"[runSyncFileDownloadAlt][urlPath], %@", urlPath);
	[self postStatusToDelegate:@"Configuring download for %@",urlPath.lastPathComponent];
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
	__block NSInteger index = -1;
	__block NSArray *servers = nil;
	if (dispatch_get_specific(kMPHTTPRequestStateQueueKey)) {
		if (self.requestCount == -1) {
			self.requestCount = 0;
		} else {
			self.requestCount++;
		}
		index = self.requestCount;
		servers = [self.serverArray copy];
	} else {
		dispatch_sync(self.stateQueue, ^{
			if (self.requestCount == -1) {
				self.requestCount = 0;
			} else {
				self.requestCount++;
			}
			index = self.requestCount;
			servers = [self.serverArray copy];
		});
	}

	if (index >= (NSInteger)servers.count)
	{
		NSDictionary *userInfo = @{NSLocalizedDescriptionKey: @"Error, could not download file, failed all servers."};
		NSError *srverr = [NSError errorWithDomain:@"gov.llnl.mphttprequest" code:1001 userInfo:userInfo];
		if (err != NULL) *err = srverr;
		return nil;
	}

	Server *server = [servers objectAtIndex:index];
	BOOL allowSelfSigned = (server.allowSelfSigned == 1);

	NSString *url = [NSString stringWithFormat:@"%@://%@:%d%@",server.usessl ? @"https":@"http", server.host, (int)server.port, urlPath];
	qlinfo(@"URL: %@",url);
	
	__block NSString *dlFile = @"ERR";
	__block BOOL didFail = NO;
	dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
	MPDownloadManager *dm = [MPDownloadManager sharedManager];
    dm.allowSelfSignedCert = allowSelfSigned;
	dm.downloadUrl = url;
	dm.downloadDestination = dlDir;
	
	dm.progressHandler = ^(double progressPercent, double sizeDownloaded, double sizeComplete)
	{
		dispatch_async(dispatch_get_main_queue(), ^{
			NSString *progStr = [NSString stringWithFormat:@"%i\uFF05 Downloaded",(int)progressPercent];
			if ((int)progressPercent % 5 == 0) qlinfo(@"%@",progStr);
			[self->delegate downloadProgress:progStr];
		});
	};
	dm.completionHandler = ^(int httpStatusCode, NSURL *downloadedFile, NSError *downloadError)
	{
		if (downloadError)
		{
			qlerror(@"Error %d. File download error %@", httpStatusCode, downloadError.localizedDescription);
			didFail = YES;
			dispatch_semaphore_signal(semaphore);
		}
		else
		{
			qlinfo(@"dm.completionHandler[httpStatusCode]: %d",httpStatusCode);
			if (httpStatusCode >= 200 && httpStatusCode <= 304) {
				didFail = NO;
				dlFile = [downloadedFile path];
			} else {
				didFail = YES;
			}
		}
		dispatch_semaphore_signal(semaphore);
	};
	
	[dm beginDownload];
	dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
	if (didFail) {
		[self runSyncFileDownloadAltOrig:urlPath downloadDirectory:dlDir error:err];
	}

	return dlFile;
}

// Used to get small images from MP servers
- (NSData *)dataForURLPath:(NSString *)aURLPath
{
	NSData *result = nil;
	NSString *url;
    
	__block NSArray *servers = nil;
    if (dispatch_get_specific(kMPHTTPRequestStateQueueKey)) {
        servers = [self.serverArray copy];
    } else {
        dispatch_sync(self.stateQueue, ^{
            servers = [self.serverArray copy];
        });
    }
    
	for (Server *server in servers)
	{
		BOOL allowSelfSigned = (server.allowSelfSigned == 1);

		url = [NSString stringWithFormat:@"%@://%@:%d%@",server.usessl ? @"https":@"http", server.host, (int)server.port, aURLPath];
		qlinfo(@"URL: %@",url);
		//
		NSError *dataErr = nil;
		result = [NSData dataWithContentsOfURL:[NSURL URLWithString:url] options:NSDataReadingMappedIfSafe error:&dataErr];
		if (!dataErr) {
			break;
		} else {
			qlerror(@"[dataForURLPath] Err\n%@",dataErr.localizedDescription);
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
	[request setValue:settings.clientVer forHTTPHeaderField:@"X-Agent-VER"];
    
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
    
    // Invalidate session to prevent memory leak
    [session finishTasksAndInvalidate];
    
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
	qldebug(@"Post data to URL: %@",aURL);
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"MacPatch" forHTTPHeaderField:@"X-Agent-ID"];
	[request setValue:settings.clientVer forHTTPHeaderField:@"X-Agent-VER"];
    
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
    
    // Invalidate session to prevent memory leak
    [session finishTasksAndInvalidate];
    
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
            // Safely read allowSelfSignedCert
            __block BOOL allowSelfSigned = NO;
            if (dispatch_get_specific(kMPHTTPRequestStateQueueKey)) {
                allowSelfSigned = self.allowSelfSignedCert;
            } else {
                dispatch_sync(self.stateQueue, ^{
                    allowSelfSigned = self.allowSelfSignedCert;
                });
            }
            
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

- (void)postStatusToDelegate:(NSString *)str, ...
{
	va_list va;
	va_start(va, str);
	NSString *string = [[NSString alloc] initWithFormat:str arguments:va];
	va_end(va);

	__block id localDelegate = nil;
    if (dispatch_get_specific(kMPHTTPRequestStateQueueKey)) {
        localDelegate = self->delegate;
    } else {
        dispatch_sync(self.stateQueue, ^{
            localDelegate = self->delegate;
        });
    }
	[localDelegate downloadProgress:string];
}
@end

