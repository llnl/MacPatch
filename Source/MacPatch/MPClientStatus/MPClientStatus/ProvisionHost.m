//
//  ProvisionHost.m
//  MPClientStatus
//
//  Created by Charles Heizer on 2/10/21.
//  Copyright © 2021 LLNL. All rights reserved.
//

#import "ProvisionHost.h"
#import "MacPatch.h"
#import "MPStatusProtocol.h"

@interface ProvisionHost()
{
    NSFileManager *fm;
    MPSettings *settings;
}

- (NSDictionary *)getProvisionData;

// Helper
// XPC Connection
@property (atomic, strong, readwrite) NSXPCConnection *workerConnection;

- (void)connectToHelperTool;
- (void)connectAndExecuteCommandBlock:(void(^)(NSError *))commandBlock;

- (NSDictionary *)getSoftwareTaskForID:(NSString *)swTaskID;
- (NSDictionary *)getDataFromWS:(NSString *)urlPath;

@end

@implementation ProvisionHost

- (id)init
{
    self = [super init];
    if (self)
    {
        fm = [NSFileManager defaultManager];
        settings = [MPSettings sharedInstance];
        
        [self connectAndExecuteCommandBlock:^(NSError * connectError) {
            if (connectError != nil) {
                qlerror(@"workerConnection[connectError][ProvisionHost][init]: %@",connectError.localizedDescription);
            } else {
                [[self.workerConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
                    qlerror(@"workerConnection[proxyError][ProvisionHost][init]: %@",proxyError.localizedDescription);
                }] createDirectory:MP_PROVISION_DIR withReply:^(NSError *error) {
                    if (error) {
                        qlerror(@"%@",error.localizedDescription);
                    } else {
                        qldebug(@"MP_PROVISION_DIR created");
                    }
                }];
            }
        }];
    }
    return self;
}

- (int)provisionHost
{
    int res = 0;
    
    [self writeToKeyInProvisionFile:@"startDT" data:[MPDate dateTimeStamp]];
    [self writeToKeyInProvisionFile:@"stage" data:@"getData"];
    [self writeToKeyInProvisionFile:@"completed" data:@{@"completed":[NSNumber numberWithBool:NO]} type:@"bool"];
    
    // Get Data
    NSDictionary *provisionData = [self getProvisionData];
    if (!provisionData) {
        qlerror(@"Provisioning data from web service is nil. Now exiting.");
        res = 1;
        [self writeToKeyInProvisionFile:@"endDT" data:[MPDate dateTimeStamp]];
        [self writeToKeyInProvisionFile:@"completed" data:@{@"completed":[NSNumber numberWithBool:YES]} type:@"bool"];
        [self writeToKeyInProvisionFile:@"failed" data:@{@"failed":[NSNumber numberWithBool:NO]} type:@"bool"];
        return res;
    } else {
        // Write Provision Data to File
        /*
        NSError *err = nil;
        NSData *_data = [NSKeyedArchiver archivedDataWithRootObject:provisionData requiringSecureCoding:NO error:&err];
        if (err) {
            NSLog(@"%@",err.localizedDescription);
        }
         */
        //[self writeToKeyInProvisionFile:@"data" data:_data];
        NSMutableDictionary *_provisionData = [NSMutableDictionary dictionaryWithDictionary:provisionData];
        if (_provisionData[@"scriptsPre"]) {
            if ([_provisionData[@"scriptsPre"] count] >= 1) {
                NSData *scriptsPreData = [NSKeyedArchiver archivedDataWithRootObject:_provisionData[@"scriptsPre"]];
                [_provisionData setObject:scriptsPreData forKey:@"scriptsPre"];
            }
        }
        if (_provisionData[@"scriptsPost"]) {
            if ([_provisionData[@"scriptsPost"] count] >= 1) {
                NSData *scriptsPostData = [NSKeyedArchiver archivedDataWithRootObject:_provisionData[@"scriptsPost"]];
                [_provisionData setObject:scriptsPostData forKey:@"scriptsPost"];
            }
        }
        if (_provisionData[@"scriptsFinish"]) {
            if ([_provisionData[@"scriptsFinish"] count] >= 1) {
                NSData *scriptsFinData = [NSKeyedArchiver archivedDataWithRootObject:_provisionData[@"scriptsFinish"]];
                [_provisionData setObject:scriptsFinData forKey:@"scriptsFinish"];
            }
        }

        [self writeToKeyInProvisionFile:@"data" data:_provisionData];
        
    }
    
    // Run Pre Scripts
    [self writeToKeyInProvisionFile:@"stage" data:@"preScripts"];
    NSArray *_pre = provisionData[@"scriptsPre"];
    if (_pre) {
        if (_pre.count >= 1) {
            for (NSDictionary *s in _pre)
            {
                qlinfo(@"Pre Script: %@",s[@"name"]);
                @try {
                    [_delegate provisionProgress:@"Running Pre-install Script(s)..."];
                    [self runScript:s[@"script"]];
                    qlinfo(@"Pre Script: %@",s[@"name"]);
                } @catch (NSException *exception) {
                    qlerror(@"[PreScript]: %@",exception);
                }
                
            }
        } else {
            qlinfo(@"No, pre scripts to run.");
        }
    }
    
    // Run Software Tasks
    [self writeToKeyInProvisionFile:@"stage" data:@"Software"];
    NSArray *_sw = provisionData[@"tasks"];
    if (_sw) {
        if (_sw.count >= 1) {
            for (NSDictionary *s in _sw)
            {
                qlinfo(@"Install Software Task: %@",s[@"name"]);
                [_delegate provisionProgress:[NSString stringWithFormat:@"Install %@",s[@"name"]]];
                @try {
                    int res = [self installSoftwareProvisonTask:s];
                    if (res != 0) {
                        [self writeToKeyInProvisionFile:@"status" data:[NSString stringWithFormat:@"Software: Failed to install %@ (%@)",s[@"name"],s[@"tuuid"]]];
                    }
                } @catch (NSException *exception) {
                    qlerror(@"[Software]: %@",exception);
                }
                
            }
        } else {
            qlinfo(@"No, software tasks to run.");
        }
    }
    
    // Run Post Scripts
    [self writeToKeyInProvisionFile:@"stage" data:@"postScripts"];
    NSArray *_post = provisionData[@"scriptsPost"];
    if (_post) {
        if (_post.count >= 1) {
            for (NSDictionary *s in _post)
            {
                qldebug(@"Post Script: %@",s[@"name"]);
                @try {
                    [_delegate provisionProgress:[NSString stringWithFormat:@"Running Post-install Script: %@",s[@"name"]]];
                    [self runScript:s[@"script"]];
                } @catch (NSException *exception) {
                    qlerror(@"[PostScript]: %@",exception);
                }
                
            }
        } else {
            qlinfo(@"No, post scripts to run.");
        }
    }
    
    
    return res;
}

#pragma mark Private

- (NSDictionary *)getProvisionData
{
    // Call Web Service for all data to povision
    NSDictionary *result = nil;
    NSError *err = nil;
    MPRESTfull *mprest = [[MPRESTfull alloc] init];
    NSDictionary *data = [mprest getProvisioningDataForHost:settings.ccuid error:&err];
    if (err) {
        qlerror(@"%@",err);
        return result;
    } else {
        qlinfo(@"%@",data);
        result = [data copy];
    }
    
    return result;
}

// Helper
- (void)writeToKeyInProvisionFile:(NSString *)key data:(id)data
{
    return [self writeToKeyInProvisionFile:key data:data type:@"NA"];
}

- (void)writeToKeyInProvisionFile:(NSString *)key data:(id)data type:(NSString *)type
{
    qlinfo(@"[writeToKeyInProvisionFile]: %@ = %@",key,data);
    NSString *_type;
    NSData *myData = [NSKeyedArchiver archivedDataWithRootObject:data];
    
    NSString *_class = NSStringFromClass([data class]);
    if ([_class containsString:@"String"]) {
        _type = @"string";
        myData = [NSKeyedArchiver archivedDataWithRootObject:data];
    } else if ([_class containsString:@"Dictionary"]) {
        _type = @"dict";
        myData = [NSKeyedArchiver archivedDataWithRootObject:data];
    } else if ([_class containsString:@"Array"]) {
        _type = @"array";
        myData = [NSKeyedArchiver archivedDataWithRootObject:data];
    } else {
        if ([type isEqualToString:@"bool"]) {
            _type = @"bool";
            myData = [NSKeyedArchiver archivedDataWithRootObject:data];
        } else {
            qlerror(@"Type (%@) not known for key (%@), data will not be written.",[data class],key);
            return;
        }
    }
    
    [self connectAndExecuteCommandBlock:^(NSError * connectError) {
        if (connectError != nil) {
            qlerror(@"workerConnection[connectError]: %@",connectError.localizedDescription);;
        } else {
            [[self.workerConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
                qlerror(@"workerConnection[proxyError]: %@",proxyError.localizedDescription);
            }] postProvisioningData:key dataForKey:myData dataType:_type withReply:^(NSError *error) {
                if (error) {
                    qlerror(@"Error posting data to key %@",key);
                    qlerror(@"Data %@",data);
                }
            }];
        }
    }];
}

// Helper
- (int)runScript:(NSString *)script
{
    qlinfo(@"Begin running script");
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block NSInteger res = 99;
    [self connectAndExecuteCommandBlock:^(NSError * connectError) {
        if (connectError != nil) {
            qlerror(@"workerConnection[connectError]: %@",connectError.localizedDescription);
            dispatch_semaphore_signal(sem);
        } else {
            [[self.workerConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
                qlerror(@"workerConnection[proxyError]: %@",proxyError.localizedDescription);
                dispatch_semaphore_signal(sem);
            }] runScriptFromString:script withReply:^(NSError *error, NSInteger result) {
                res = result;  
                if (error) {
                    qlerror(@"Error running script.");
                    qlerror(@"%@",error.localizedDescription);
                }
                qlinfo(@"End running script");
                dispatch_semaphore_signal(sem);
            }];
        }
    }];
    
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    qlinfo(@"Script result: %d",(int)res);
    return (int)res;
}

// Helper
- (int)installSoftwareProvisonTask:(NSDictionary *)swTask
{
    qlinfo(@"Begin running required software install.");
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSDictionary *swDict = [self getSoftwareTaskForID:swTask[@"tuuid"]];
    __block NSInteger res = 99;
    [self connectAndExecuteCommandBlock:^(NSError * connectError) {
        if (connectError != nil) {
            qlerror(@"workerConnection[connectError]: %@",connectError.localizedDescription);
            dispatch_semaphore_signal(sem);
        } else {
            [[self.workerConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
                qlerror(@"workerConnection[proxyError]: %@",proxyError.localizedDescription);
                dispatch_semaphore_signal(sem);
            }] installSoftware:swDict timeOut:900 withReply:^(NSError *error, NSInteger resultCode, NSData *installData ) {
                res = resultCode;
                if (error) {
                    qlerror(@"Error installing %@.",swTask[@"name"]);
                    qlerror(@"%@",error);
                }
                qlinfo(@"End running required software install.");
                dispatch_semaphore_signal(sem);
            }];
        }
    }];
    
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    qlinfo(@"Required software result: %d",(int)res);
    return (int)res;
}

/*
 Provision Steps
 
 1) Call MP with -L for Provisioning
 2) MPAgent installs scripts and software
    - Write Status file to /Library/LLNL/.MPProvision.plist
 
    {
        startDT: startDateTime
        endDT: endDateTime
        stage: [getData, preScripts, Software, postScripts, userInfoCollection, userSwInstall, patch]
        status: [
            logData
        ]
        userInfoData: {
            assetNum: 1
            machineName:
            oun:
            fileVault
        }
        data: {
            tasks: []
            preScripts: []
            postScripts: []
        }
        completed: bool
        failed: bool
    }
 
 
 */

#pragma mark - Helper

- (void)connectToHelperTool
// Ensures that we're connected to our helper tool.
{
    if (self.workerConnection == nil) {
        self.workerConnection = [[NSXPCConnection alloc] initWithMachServiceName:kHelperServiceName options:NSXPCConnectionPrivileged];
        self.workerConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(MPStatusProtocol)];
        
        // Register Progress Messeges From Helper
        self.workerConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(MPStatusProtocol)];
        self.workerConnection.exportedObject = self;
        
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
        // We can ignore the retain cycle warning because a) the retain taken by the
        // invalidation handler block is released by us setting it to nil when the block
        // actually runs, and b) the retain taken by the block passed to -addOperationWithBlock:
        // will be released when that operation completes and the operation itself is deallocated
        // (notably self does not have a reference to the NSBlockOperation).
        self.workerConnection.invalidationHandler = ^{
            // If the connection gets invalidated then, on the main thread, nil out our
            // reference to it.  This ensures that we attempt to rebuild it the next time around.
            self.workerConnection.invalidationHandler = nil;
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                self.workerConnection = nil;
            }];
        };
#pragma clang diagnostic pop
        [self.workerConnection resume];
    }
}

- (void)connectAndExecuteCommandBlock:(void(^)(NSError *))commandBlock
// Connects to the helper tool and then executes the supplied command block on the
// main thread, passing it an error indicating if the connection was successful.
{
    // Ensure that there's a helper tool connection in place.
    self.workerConnection = nil;
    [self connectToHelperTool];
    
    commandBlock(nil);
}

#pragma mark - MPHelperProgress protocol

- (void)postStatus:(NSString *)status type:(MPPostDataType)type
{
    qldebug(@"[ProvisionHost][postStatus]: %@",status);
    if (type == kMPProcessStatus) {
        dispatch_async(dispatch_get_main_queue(), ^{
            //self->_progressStatus.stringValue = status;
        });
        //[self postSWStatus:status];
    }
}

#pragma mark - Notifications

- (void)postStopHasError:(BOOL)arg1 errorString:(NSString *)arg2
{
    qldebug(@"[ProvisionHost][postStopHasError]: %@",arg2);
    qldebug(@"postStopHasError called %@",arg2);
    /*
    NSError *err = nil;
    if (arg1) {
        //err = [NSError errorWithDomain:@"gov.llnl.sw.oper" code:1001 userInfo:@{NSLocalizedDescriptionKey:arg2}];
        //[[NSNotificationCenter defaultCenter] postNotificationName:cellStopNote object:nil userInfo:@{@"error":err}];
    } else {
        //[[NSNotificationCenter defaultCenter] postNotificationName:cellStopNote object:nil userInfo:@{}];
    }
     */
}

#pragma mark - Private

- (NSDictionary *)getSoftwareTaskForID:(NSString *)swTaskID
{
    NSDictionary *task = nil;
    NSDictionary *data = nil;
    
    NSString *urlPath = [NSString stringWithFormat:@"/api/v4/sw/provision/task/%@/%@", swTaskID, settings.ccuid];
    data = [self getDataFromWS:urlPath];
    if (data[@"data"])
    {
        task = data[@"data"];
    }
    
    return task;
}

- (NSDictionary *)getDataFromWS:(NSString *)urlPath
{
    NSDictionary *result = nil;
    MPHTTPRequest *req;
    MPWSResult *wsresult;
    
    req = [[MPHTTPRequest alloc] init];
    wsresult = [req runSyncGET:urlPath];
    
    if (wsresult.statusCode >= 200 && wsresult.statusCode <= 299) {
        qldebug(@"Get Data from web service (%@) returned true.",urlPath);
        qldebug(@"Data Result: %@",wsresult.result);
        result = wsresult.result;
    } else {
        qlerror(@"Get Data from web service (%@), returned false.", urlPath);
        qldebug(@"%@",wsresult.toDictionary);
    }
    
    return result;
}
@end
