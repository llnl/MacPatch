//
//  XPCWorker.m
//  gov.llnl.mp.worker
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

#import "XPCWorker.h"
#import "MPHelperProtocol.h"
#import "AHCodesignVerifier.h"
#include <libproc.h>
//#import "MPAgentController.h"

#import "MPPatching.h"

#import "DBModels.h"
#import "DBMigration.h"
#import "MPClientDB.h"

#undef  ql_component
#define ql_component lcl_cMPHelper

NSString *const MPXPCErrorDomain = @"gov.llnl.mp.helper";

@interface NSFileHandle (MPNSFileHandleAdditions)
- (NSData *)availableDataOrError:(NSException **)returnError;
@end

@implementation NSFileHandle (MPNSFileHandleAdditions)
- (NSData *)availableDataOrError:(NSException **)returnError
{
    for(;;)
    {
        @try
        {
            return [self availableData];
        }
        @catch (NSException *e)
        {
            if ([[e name] isEqualToString:NSFileHandleOperationException]) {
                if ([[e reason] isEqualToString:@"*** -[NSConcreteFileHandle availableData]: Interrupted system call"]) {
                    continue;
                }
                if (returnError) {
                    *returnError = e;
                }
                return nil;
            }
            @throw;
        }
    }
}
@end

@interface XPCWorker () <NSXPCListenerDelegate, MPHelperProtocol, MPHTTPRequestDelegate>
{
    NSFileManager *fm;
}

@property (nonatomic, strong, readwrite) NSURL          *SW_DATA_DIR;

@property (atomic, strong, readwrite)   NSXPCListener   *listener;
@property (atomic, assign, readwrite)   int             selfPID;
@property (atomic, weak, readwrite)     NSXPCConnection *xpcConnection;

// PID
- (int)getPidNumber;
- (NSString *)pathForPid:(int)aPid;


// ASUS
- (NSString *)getSizeFromDescription:(NSString *)aDescription;
- (NSString *)getRecommendedFromDescription:(NSString *)aDescription;

// Patching
- (NSArray *)scanForAppleUpdates:(NSError **)error;

// Private
- (NSData *)encodeResult:(NSData *)dataToEncode error:(NSError **)error;
@end

@implementation XPCWorker

@synthesize SW_DATA_DIR;

- (id)init
{
    self = [super init];
    if (self != nil) {
        // Set up our XPC listener to handle requests on our Mach service.
        self->_listener = [[NSXPCListener alloc] initWithMachServiceName:kHelperServiceName];
        self->_listener.delegate = self;
        self->_selfPID = [self getPidNumber];
		self->SW_DATA_DIR = [self swDataDirURL];
        [self configDataDir];
        fm = [NSFileManager defaultManager];
		
    }
    return self;
}

- (void)run
{
    qlinfo(@"XPC listener is ready for processing requests");
    // Tell the XPC listener to start processing requests.
    [self.listener resume];
    
    // Run the run loop forever.
    [[NSRunLoop currentRunLoop] run];
}

- (void)configDataDir
{
    // Set Data Directory

    // Create the base sw dir
    if ([fm fileExistsAtPath:[SW_DATA_DIR path]] == NO) {
        NSError *err = nil;
        NSDictionary *attributes = [NSDictionary dictionaryWithObject:[NSNumber numberWithShort:0777] forKey:NSFilePosixPermissions];
        [fm createDirectoryAtPath:[SW_DATA_DIR path] withIntermediateDirectories:YES attributes:attributes error:&err];
        if (err) {
            logit(lcl_vError,@"%@",[err description]);
        }
    }
    
    // Create the sw dir
    if ([fm fileExistsAtPath:[[SW_DATA_DIR URLByAppendingPathComponent:@"sw"] path]] == NO) {
        NSError *err = nil;
        NSDictionary *attributes = [NSDictionary dictionaryWithObject:[NSNumber numberWithShort:0777] forKey:NSFilePosixPermissions];
        [fm createDirectoryAtPath:[[SW_DATA_DIR URLByAppendingPathComponent:@"sw"] path] withIntermediateDirectories:YES attributes:attributes error:&err];
        if (err) {
            logit(lcl_vError,@"%@",[err description]);
        }
        [[SW_DATA_DIR URLByAppendingPathComponent:@"sw"] setResourceValue:[NSNumber numberWithBool:YES] forKey:NSURLIsHiddenKey error:NULL];
    }
}

#pragma mark - XPC Setup & Connection

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection
// Called by our XPC listener when a new connection comes in.  We configure the connection
// with our protocol and ourselves as the main object.
{
    qlinfo(@"Listener recieved new connection.");
    //BOOL valid = [self newConnectionIsTrusted:newConnection];
	
	BOOL valid = YES;
    if (valid)
	{
        logit(lcl_vInfo,@"Listener, new connection is trusted and valid");
        assert(listener == self.listener);
        assert(newConnection != nil);
		
		newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(MPHelperProtocol)];
		newConnection.exportedObject = self;
		
		
		self.xpcConnection = newConnection;
		newConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(MPHelperProgress)];
		
		[newConnection resume];
        return YES;
    }
    
    logit(lcl_vError,@"Listener failed to trust new connection.");
    return NO;
}

- (BOOL)newConnectionIsTrusted:(NSXPCConnection *)newConnection
{
    BOOL success = NO;
    NSError *err = nil;
    
    int mePid = [self getPidNumber];
    NSString *mePidPath = [self pathForPid:mePid];
    logit(lcl_vDebug,@"self.pid %d, self.path %@",mePid,mePidPath);
    if (![AHCodesignVerifier codeSignOfItemAtPathIsValid:mePidPath error:&err])
    {
        logit(lcl_vError,@"The codesigning signature of one %@ is not valid.",mePidPath.lastPathComponent);
        logit(lcl_vError,@"%@",err.localizedDescription);
        return success;
    }
    
    pid_t rmtPid = newConnection.processIdentifier;
    NSString *remotePidPath = [self pathForPid:rmtPid];
    logit(lcl_vDebug,@"remote.pid %d, remote.path %@",rmtPid,remotePidPath);
    err = nil;
    if (![AHCodesignVerifier codeSignOfItemAtPathIsValid:remotePidPath error:&err])
    {
        logit(lcl_vError,@"The codesigning signature of one %@ is not valid.",mePidPath.lastPathComponent);
        return success;
    }
    
    err = nil;
    success = [AHCodesignVerifier codesignOfItemAtPath:mePidPath isSameAsItemAtPath:remotePidPath error:&err];
    if (err) {
        logit(lcl_vError,@"The codesigning signatures did not match.");
        logit(lcl_vError,@"%@",err.localizedDescription);
    }
    
    return success;
}

# pragma mark - PID methods

- (int)getPidNumber
{
    NSProcessInfo *processInfo = [NSProcessInfo processInfo];
    int processID = [processInfo processIdentifier];
    return processID;
}

- (NSString *)pathForPid:(int)aPid
{
    int ret;
    char pathbuf[PROC_PIDPATHINFO_MAXSIZE];
    
    pid_t pid = aPid;
    ret = proc_pidpath (pid, pathbuf, sizeof(pathbuf));
    if ( ret <= 0 ) {
        logit(lcl_vError,@"PID %d: proc_pidpath ()", pid);
        logit(lcl_vError,@"%s", strerror(errno));
    } else {
        logit(lcl_vDebug,@"proc %d: %s", pid, pathbuf);
    }
    
    return [NSString stringWithUTF8String:pathbuf];
}

#pragma mark - MPWorkerProtocol implementation

- (void)getVersionWithReply:(void(^)(NSString *verData))reply
{
	reply(@"1");
}

- (void)getTestWithReply:(void(^)(NSString *aString))reply
{
    // We specifically don't check for authorization here.  Everyone is always allowed to get
    // the version of the helper tool.
	
	qlinfo(@"scanForInstalledConfigProfiles");
	MPConfigProfiles *p = [[MPConfigProfiles alloc] init];
	NSArray *cp = [p readProfileStoreReturnAsConfigProfile];
	NSString *str = [NSString stringWithFormat:@"Profiles Found %lu",(unsigned long)cp.count];
	
    logit(lcl_vDebug,@"getTestWithReply");
    reply(str);
}

- (void)getProfilesWithReply:(void(^)(NSString *aString, NSData *aData))reply
{
	// We specifically don't check for authorization here.  Everyone is always allowed to get
	// the version of the helper tool.
	
	qlinfo(@"scanForInstalledConfigProfiles");
	MPConfigProfiles *p = [[MPConfigProfiles alloc] init];
	NSArray *cp = [p readProfileStoreReturnAsConfigProfile];
	NSData *data = [NSKeyedArchiver archivedDataWithRootObject:cp];
	NSString *str = [NSString stringWithFormat:@"Profiles Found %lu",(unsigned long)cp.count];
	
	logit(lcl_vDebug,@"getProfilesWithReply");
	reply(str,data);
}

#pragma mark • ASUS

// ASUS

// Delegate Method
- (void)appleScanProgress:(NSString *)data
{
	qlinfo(@"appleScanProgress: %@",[data trim]);
	//[self postPatchStatus:[data trim]];
	[self postStatus:[data trim]];
}

#pragma mark • ASUS Helpers

- (NSString *)getSizeFromDescription:(NSString *)aDescription
{
    NSArray *tmpArr1 = [aDescription componentsSeparatedByString:@","];
    NSArray *tmpArr2 = [[[tmpArr1 objectAtIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsSeparatedByString:@" "];
    return [[tmpArr2 objectAtIndex:0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSString *)getRecommendedFromDescription:(NSString *)aDescription
{
    NSRange textRange;
    textRange =[aDescription rangeOfString:@"recommended"];
    
    if(textRange.location != NSNotFound) {
        return @"Y";
    } else {
        return @"N";
    }
    
    return @"N";
}

#pragma mark • Patching

- (void)scanForPatchesUsingFilter:(MPPatchContentType)patchType withReply:(void(^)(NSError *error, NSData *patches, NSData *patchGroupData))reply
{
	NSError			*error = nil;
	NSDictionary 	*patches;
	NSArray 		*requiredPatches = [NSArray array];
	
	// Get Patch Group Patches
	NSError *wsErr = nil;
	MPRESTfull *mprest = [[MPRESTfull alloc] init];
	NSDictionary *patchGroupPatches = [mprest getApprovedPatchesForClient:&wsErr];
	if (wsErr) {
		qlerror(@"Error: %@",wsErr.localizedDescription);
	}
	[self postStatus:@"Scan host for patches..."];
	
	MPPatching *mpPatching = [MPPatching new];
	mpPatching.delegate = self;
	requiredPatches = [mpPatching scanForPatchesUsingTypeFilter:patchType forceRun:NO];
	
	// Create Patch Dict
	patches = @{@"apple":@[], @"custom": @[], @"required": requiredPatches};
	error = nil;
	NSData *_patchesData = [NSKeyedArchiver archivedDataWithRootObject:patches];
	NSData *_patchGroupPatches = [NSKeyedArchiver archivedDataWithRootObject:patchGroupPatches];
	
	[_patchesData writeToFile:@"/var/tmp/patches.plist" atomically:NO];
	[_patchGroupPatches writeToFile:@"/var/tmp/patchGroupPatches.plist" atomically:NO];
	
	reply(error, _patchesData, _patchGroupPatches);
}

- (void)installPatch:(NSDictionary *)patch withReply:(nullable void(^)(NSError * _Nullable error, NSInteger resultCode))reply
{
	NSInteger result = 0;
	qlinfo(@"Install Patch: %@",patch[@"patch"]);
	qldebug(@"Patch: %@",patch);
	
	MPPatching *patching = [MPPatching new];
	[self postPatchStatus:@"Begin %@ install", patch[@"patch"]];
	NSDictionary *patchResult = [patching installPatchUsingTypeFilter:patch typeFilter:kAllPatches];
	
	if (patchResult[@"patchInstallErrors"]) {
		if ([patchResult[@"patchInstallErrors"] integerValue] >= 1)
		{
			qlerror(@"Error installing %@",patch[@"patch"]);
			result = 1;
		}
	} else {
		result = 9999;
	}
	
	qltrace(@"result = %ld",(long)result);
	[self postPatchStatus:@"%@ install complete", patch[@"patch"]];
	reply(nil,result);
}

- (void)installPatch:(NSDictionary *)patch userInstallRebootPatch:(int)installRebootPatch withReply:(nullable void(^)(NSError * _Nullable error, NSInteger resultCode))reply
{
	NSInteger result = 0;
	qlinfo(@"Install Patch: %@",patch[@"patch"]);
	qldebug(@"Patch: %@",patch);
	
	MPPatching *patching = [MPPatching new];
	[self postPatchStatus:@"Begin %@ install", patch[@"patch"]];
	if (installRebootPatch == 1) {
		[patching setInstallRebootPatchesWhileLoggedIn:YES];
	}
	NSDictionary *patchResult = [patching installPatchUsingTypeFilter:patch typeFilter:kAllPatches];
	qltrace(@"patchResult: %@",patchResult);
	if (patchResult[@"patchInstallErrors"]) {
		if ([patchResult[@"patchInstallErrors"] integerValue] >= 1)
		{
			qlerror(@"Error installing %@",patch[@"patch"]);
			result = 1;
		} else {
			// No Errors detected
			if (patchResult[@"patchesRequireHalt"]) {
				// Patch Requires a halt/shutdown ... this is for Apple Patches with firmware
				if ([patchResult[@"patchInstallErrors"] intValue] >= 1) {
					result = 1000;
				}
			}
		}
	} else {
		result = 9999;
	}
	
	qltrace(@"result = %ld",(long)result);
	[self postPatchStatus:@"%@ install complete", patch[@"patch"]];
	reply(nil,result);
}

- (void)installPatches:(NSArray *)patches withReply:(nullable void(^)(NSError * _Nullable error, NSInteger resultCode))reply
{
	int patchCount = 0;
	double patchProgress = 0.0;
	NSInteger result = 0;
	MPPatching *patching = [MPPatching new];
	
	[self postPatchStatus:@"Installing all patches ..."];
	for (NSDictionary *patch in patches)
	{
		qlinfo(@"Install Patch: %@",patch[@"patch"]);
		qldebug(@"Patch: %@",patch);
		
		[self postPatchAllStatus:@"Begin %@ install...", patch[@"patch"]];
		NSDictionary *patchResult = [patching installPatchUsingTypeFilter:patch typeFilter:kAllPatches];
		
		if (patchResult[@"patchInstallErrors"])
		{
			if ([patchResult[@"patchInstallErrors"] integerValue] >= 1)
			{
				qlerror(@"Error installing %@",patch[@"patch"]);
				result = result + 1;
			} else {
				[self postPatchInstallCompletion:patch[@"patch_id"]];
			}
		} else {
			[self postPatchInstallCompletion:patch[@"patch_id"]];
		}
		
		patchCount = patchCount + 1;
		patchProgress = patchCount / patches.count;
		[self postPatchAllProgress:patchCount];
	}

	qltrace(@"result = %ld",(long)result);
	[self postPatchStatus:@"%d install(s) completed.", patchCount];
	reply(nil,result);
}

// Private
- (BOOL)postDataToWS:(NSString *)urlPath data:(NSDictionary *)data
{
	MPHTTPRequest *req;
	MPWSResult *result;
	
	req = [[MPHTTPRequest alloc] init];
	result = [req runSyncPOST:urlPath body:data];
	
	if (result.statusCode >= 200 && result.statusCode <= 299) {
		logit(lcl_vInfo,@"[MPAgentExecController][postDataToWS]: Data post to web service (%@), returned true.", urlPath);
		//logit(lcl_vDebug,@"Data post to web service (%@), returned true.", urlPath);
		logit(lcl_vDebug,@"Data Result: %@",result.result);
	} else {
		logit(lcl_vError,@"Data post to web service (%@), returned false.", urlPath);
		logit(lcl_vDebug,@"%@",result.toDictionary);
		return NO;
	}
	
	return YES;
}

- (NSDictionary *)patchesForPatchGroup:(NSError **)error
{
    //NSError *err = nil;
	//MPWebServices *mpws = [[MPWebServices alloc] init];
	//NSDictionary *a = [mpws getPatchGroupContent:&err];
	//return a;
	return [NSDictionary dictionary];
}

- (NSArray *)scanForAppleUpdates:(NSError **)error
{
	/*
	 1. Get Scan List
	 2. Scan for patches
	 3. Post patches needed
	 */
	NSError *wsErr = nil;
	MPRESTfull *mprest = [[MPRESTfull alloc] init];
	NSDictionary *patchGroupPatches = [mprest getApprovedPatchesForClient:&wsErr];
	if (wsErr) {
		qlerror(@"Error: %@",wsErr.localizedDescription);
	}
	qltrace(@"patchGroupPatches: %@",patchGroupPatches);
	
	
	MPASUSCatalogs *m = [[MPASUSCatalogs alloc] init];
	[m checkAndSetCatalogURL];
	
	NSArray *patches = [NSArray array];
	MPAsus *asus = [[MPAsus alloc] init];
	asus.delegate = self;
	
	patches = [asus scanForAppleUpdates];
	return patches;
}

- (NSArray *)scanForAppleUpdatesAlt:(NSError **)error
{
    NSError *err = nil;
    qlinfo(@"Scanning for Apple software updates.");
	[self postPatchStatus:@"Scanning for Apple software updates."];
    
    NSData *result;
    NSArray *appleUpdates = nil;
    
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath: ASUS_BIN_PATH];
    [task setArguments: [NSArray arrayWithObjects: @"-l", nil]];
    
    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput: pipe];
    [task setStandardError: pipe];
    
    NSFileHandle *file = [pipe fileHandleForReading];
    
    [task launch];
    qlinfo(@"Starting Apple software update scan.");
    [task waitUntilExit];
    
    int status = [task terminationStatus];
    if (status == 0) {
        qlinfo(@"Apple software update scan was completed.");
		[self postPatchStatus:@"Apple software update scan was completed."];
        
        NSData *data = [file readDataToEndOfFile];
        NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        
        qlinfo(@"Apple software update full scan results\n%@",string);
        
        if (!([string rangeOfString:@"No new"].location == NSNotFound)) {
            qlinfo(@"No new updates.");
        } else {
            // We have updates so we need to parse the results
            NSArray *strArr = [NSArray arrayWithArray:[string componentsSeparatedByString:@"\n"]];
            
            NSMutableArray *tmpAppleUpdates = [NSMutableArray new];
            NSString *tmpStr;
            NSMutableDictionary *tmpDict;
            
            for (int i=0; i<[strArr count]; i++) {
                // Ignore empty lines
                if ([[strArr objectAtIndex:i] length] != 0) {
                    
                    //Clear the tmpDict object before populating it
                    if (!([[strArr objectAtIndex:i] rangeOfString:@"Software Update Tool"].location == NSNotFound)) {
                        continue;
                    }
                    if (!([[strArr objectAtIndex:i] rangeOfString:@"Copyright"].location == NSNotFound)) {
                        continue;
                    }
                    
                    // Strip the White Space and any New line data
                    tmpStr = [[strArr objectAtIndex:i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    
                    // If the object/string starts with *,!,- then allow it
                    if ([[tmpStr substringWithRange:NSMakeRange(0,1)] isEqual:@"*"] || [[tmpStr substringWithRange:NSMakeRange(0,1)] isEqual:@"!"] || [[tmpStr substringWithRange:NSMakeRange(0,1)] isEqual:@"-"]) {
                        tmpDict = [[NSMutableDictionary alloc] init];
                        qlinfo(@"Apple Update: %@",[tmpStr substringWithRange:NSMakeRange(2,([tmpStr length]-2))]);
                        [tmpDict setObject:[tmpStr substringWithRange:NSMakeRange(2,([tmpStr length]-2))] forKey:@"patch"];
                        [tmpDict setObject:@"Apple" forKey:@"type"];
                        [tmpDict setObject:[[[tmpStr substringWithRange:NSMakeRange(2,([tmpStr length]-2))] componentsSeparatedByString:@"-"] lastObject] forKey:@"version"];
                        [tmpDict setObject:[[strArr objectAtIndex:(i+1)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] forKey:@"description"];
                        [tmpDict setObject:[self getSizeFromDescription:[tmpDict objectForKey:@"description"]] forKey:@"size"];
                        [tmpDict setObject:[self getRecommendedFromDescription:[tmpDict objectForKey:@"description"]] forKey:@"recommended"];
                        if ([[[strArr objectAtIndex:(i+1)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] containsString:@"[restart]" ignoringCase:YES] == TRUE) {
                            [tmpDict setObject:@"Y" forKey:@"restart"];
                        } else {
                            [tmpDict setObject:@"N" forKey:@"restart"];
                        }
                        
                        [tmpAppleUpdates addObject:tmpDict];
                    } // if is an update
                } // if / empty lines
            } // for loop
            
            appleUpdates = [NSArray arrayWithArray:tmpAppleUpdates];
            logit(lcl_vDebug,@"Apple Updates Found, %@",appleUpdates);
            
            err = nil;
            result = [self encodeResult:[NSKeyedArchiver archivedDataWithRootObject:appleUpdates] error:&err];
            if (err) {
                logit(lcl_vDebug,@"%@",err.localizedDescription);
            }
        }
    } else {
        NSString *errStr = [NSString stringWithFormat:@"Error: softwareupdate exit code = %d",status];
        logit(lcl_vError,@"%@",errStr);
        NSDictionary *errDetail = @{NSLocalizedDescriptionKey:errStr};
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"gov.llnl.mp.worker" code:101 userInfo:errDetail];
        }
    }
	
    return nil;
}

- (void)scanAndPatchSoftwareItem:(NSDictionary *)aSWDict withReply:(void(^)(NSError *error, NSInteger result))reply
{
    NSError *err = nil;
    @try {
		/*
        MPScanAndPatch *ma = [[MPScanAndPatch alloc] initForBundleUpdate];
        [ma scanAndUpdateCustomWithPatchBundleID:[aSWDict valueForKeyPath:@"Software.patch_bundle_id"]];
        res = [ma errorCode];
        reply(err, res);
		 */
		reply(NULL,0);
    } @catch (NSException *exception) {
        
        NSMutableDictionary * info = [NSMutableDictionary dictionary];
        [info setValue:exception.name forKey:@"ExceptionName"];
        [info setValue:exception.reason forKey:@"ExceptionReason"];
        [info setValue:exception.callStackReturnAddresses forKey:@"ExceptionCallStackReturnAddresses"];
        [info setValue:exception.callStackSymbols forKey:@"ExceptionCallStackSymbols"];
        [info setValue:exception.userInfo forKey:@"ExceptionUserInfo"];
        
        err = [[NSError alloc] initWithDomain:NSCocoaErrorDomain code:1 userInfo:info];
        reply(err,1);
    }

    reply(err,1);
}

- (void)setPatchOnLogoutWithReply:(void(^)(BOOL result))reply
{
	BOOL res = YES;
	NSError *err = nil;
	NSString *_atFile = @"/private/tmp/.MPAuthRun";
	NSString *_rbText = @"reboot";
	// Mac OS X 10.9 Support, now using /private/tmp/.MPAuthRun
	[_rbText writeToFile:_atFile atomically:YES encoding:NSUTF8StringEncoding error:&err];
	if (err)
	{
		qlerror(@"Error setting patch on logout file.");
		qlerror(@"%@",err.localizedDescription);
		res = NO;
	}
	else
	{
		NSDictionary *_fileAttr = @{@"NSFilePosixPermissions":[NSNumber numberWithUnsignedLong:0777]};
		[fm setAttributes:_fileAttr ofItemAtPath:_atFile error:NULL];
	}
	reply(res);
}

- (void)setStateOnPausePatching:(MPPatchingPausedState)state withReply:(void(^)(BOOL result))reply
{
	BOOL res = YES;
	NSError *err = nil;
	NSString *_file = @"/private/var/db/.MPPatchState.plist";
	NSDictionary *data;
	if (state == kPatchingPausedOn) {
		data = @{@"pausePatching":[NSNumber numberWithBool:YES]};
	} else {
		data = @{@"pausePatching":[NSNumber numberWithBool:NO]};
	}

	if (![data writeToFile:_file atomically:NO])
	{
		qlerror(@"Error setting paused patching state to file.");
		res = NO;
	}
	else
	{
		NSDictionary *_fileAttr = @{@"NSFilePosixPermissions":[NSNumber numberWithUnsignedLong:0777]};
		[fm setAttributes:_fileAttr ofItemAtPath:_file error:NULL];
	}
	reply(res);
}

#pragma mark Patching Delegate methods
- (void)patchingProgress:(MPPatching *)mpPatching progress:(NSString *)progressStr
{
	[self postStatus:progressStr];
}


#pragma mark • Software
- (void)installSoftware:(NSDictionary *)swItem withReply:(void(^)(NSError *error, NSInteger resultCode, NSData *installData))reply
{
	qlinfo(@"Start install of %@",swItem[@"name"]);
	qlinfo(@"swItem: %@",swItem); // Change to debug later
	
	NSError *err = nil;
	NSString *errStr;
	NSInteger result = 99; // Default result
	NSData *installResultData = [NSData data];
	
	NSString *pkgType = [swItem valueForKeyPath:@"Software.sw_type"];
	
	MPFileUtils *fu;
	NSString *fHash = nil;
	MPScript *mpScript;
	MPCrypto *mpCrypto = [[MPCrypto alloc] init];
	
	if (!SW_DATA_DIR) {
		SW_DATA_DIR = [self swDataDirURL];
	}
	NSString *dlSoftwareFileName = [[swItem valueForKeyPath:@"Software.sw_url"] lastPathComponent];
	NSString *dlSoftwareFile = [NSString pathWithComponents:@[[SW_DATA_DIR path],@"sw",swItem[@"id"],dlSoftwareFileName]];
	
	// -----------------------------------------
	// Create Download URL
	// -----------------------------------------
	//NSString *_url = [NSString stringWithFormat:@"/mp-content%@",[swItem valueForKeyPath:@"Software.sw_url"]];
	//qldebug(@"Download software from: %@",[swItem valueForKeyPath:@"Software.sw_url"]);
	
	// -----------------------------------------
	// Download Software
	// -----------------------------------------
	//if ([self hasCanceledInstall:swItem]) return 99;
	//if ([self downloadSoftwareAndMoveTo:_url destination:swLoc] != 0) {
	//	return 1;
	//}
	[self downloadSoftware:[swItem copy] toDestination:[dlSoftwareFile stringByDeletingLastPathComponent]];
	
	
	if ([pkgType isEqualToString:@"SCRIPTZIP" ignoringCase:YES])
	{
		qlinfo(@"Software Task is of type %@.",pkgType);
		// ------------------------------------------------
		// Check File Hash
		// ------------------------------------------------
		[self postStatus:@"Checking file hash..."];
		fHash = [mpCrypto md5HashForFile:dlSoftwareFile];
		if (![fHash isEqualToString:[swItem valueForKeyPath:@"Software.sw_hash"] ignoringCase:YES])
		{
			errStr = [NSString stringWithFormat:@"Error unable to verify software hash for file %@.",dlSoftwareFileName];
			qlerror(@"%@", errStr);
			err = [NSError errorWithDomain:MPXPCErrorDomain code:MPFileHashCheckError userInfo:@{NSLocalizedDescriptionKey:errStr}];
			reply(err,1,installResultData);
			return;
		}
		
		// ------------------------------------------------
		// Unzip Software
		// ------------------------------------------------
		[self postStatus:[NSString stringWithFormat:@"Unzipping file %@.",dlSoftwareFileName]];
		qlinfo(@"Unzipping file %@.",dlSoftwareFile);
		fu = [MPFileUtils new];
		BOOL res = [fu unzipItemAtPath:dlSoftwareFile targetPath:[dlSoftwareFile stringByDeletingLastPathComponent] error:&err];
		if (!res || err) {
			if (err) {
				errStr = [NSString stringWithFormat:@"Error unzipping file %@. %@",dlSoftwareFile,[err description]];
				qlerror(@"%@", errStr);
			} else {
				errStr = [NSString stringWithFormat:@"Error unzipping file %@.",dlSoftwareFile];
				qlerror(@"%@", errStr);
			}
			err = [NSError errorWithDomain:MPXPCErrorDomain code:MPFileUnZipError userInfo:@{NSLocalizedDescriptionKey:errStr}];
			reply(err,1,installResultData);
			return;
		}
		
		// ------------------------------------------------
		// Run Pre Install Script
		// ------------------------------------------------
		[self postStatus:@"Running pre-install script..."];
		if (![self runSWInstallScript:[swItem valueForKeyPath:@"Software.sw_pre_install"] type:0]) {
			err = [NSError errorWithDomain:MPXPCErrorDomain code:MPPreInstallScriptError userInfo:@{NSLocalizedDescriptionKey:@"Error running pre-insatll script."}];
			reply(err,1,installResultData);
			return;
		}
		
		// ------------------------------------------------
		// Run Download Script
		// ------------------------------------------------
		[self postStatus:@"Running script..."];
		err = nil;
		mpScript = [[MPScript alloc] init];
		if (![mpScript runScriptsFromDirectory:[dlSoftwareFile stringByDeletingLastPathComponent] error:&err]) {
			result = 1;
			if (err) {
				qlerror(@"%@", err.localizedDescription);
			}
			reply(err,1,installResultData);
			return;
		} else {
			result = 0;
		}
		
		// ------------------------------------------------
		// Run Post Install Script, if copy was good
		// ------------------------------------------------
		if (result == 0)
		{
			[self postStatus:@"Running post-install script..."];
			if (![self runSWInstallScript:[swItem valueForKeyPath:@"Software.sw_post_install"] type:0]) {
				err = [NSError errorWithDomain:MPXPCErrorDomain code:MPPostInstallScriptError userInfo:@{NSLocalizedDescriptionKey:@"Error running post-insatll script."}];
			}
		}
	}
	else if ([pkgType isEqualToString:@"PACKAGEZIP" ignoringCase:YES])
	{
		qlinfo(@"Software Task is of type %@.",pkgType);
		// ------------------------------------------------
		// Check File Hash
		// ------------------------------------------------
		[self postStatus:@"Checking file hash..."];
		fHash = [mpCrypto md5HashForFile:dlSoftwareFile];
		if (![fHash isEqualToString:[swItem valueForKeyPath:@"Software.sw_hash"] ignoringCase:YES])
		{
			errStr = [NSString stringWithFormat:@"Error unable to verify software hash for file %@.",dlSoftwareFileName];
			qlerror(@"%@", errStr);
			err = [NSError errorWithDomain:MPXPCErrorDomain code:MPFileHashCheckError userInfo:@{NSLocalizedDescriptionKey:errStr}];
			reply(err,1,installResultData);
			return;
		}
		
		// ------------------------------------------------
		// Unzip Software
		// ------------------------------------------------
		[self postStatus:[NSString stringWithFormat:@"Unzipping file %@.",dlSoftwareFileName]];
		qlinfo(@"Unzipping file %@.",dlSoftwareFile);
		fu = [MPFileUtils new];
		BOOL res = [fu unzipItemAtPath:dlSoftwareFile targetPath:[dlSoftwareFile stringByDeletingLastPathComponent] error:&err];
		if (!res || err) {
			if (err) {
				errStr = [NSString stringWithFormat:@"Error unzipping file %@. %@",dlSoftwareFile,[err description]];
				qlerror(@"%@", errStr);
			} else {
				errStr = [NSString stringWithFormat:@"Error unzipping file %@.",dlSoftwareFile];
				qlerror(@"%@", errStr);
			}
			err = [NSError errorWithDomain:MPXPCErrorDomain code:MPFileUnZipError userInfo:@{NSLocalizedDescriptionKey:errStr}];
			reply(err,1,installResultData);
			return;
		}
		
		// ------------------------------------------------
		// Run Pre Install Script
		// ------------------------------------------------
		[self postStatus:@"Running pre-install script..."];
		if (![self runSWInstallScript:[swItem valueForKeyPath:@"Software.sw_pre_install"] type:0]) {
			err = [NSError errorWithDomain:MPXPCErrorDomain code:MPPreInstallScriptError userInfo:@{NSLocalizedDescriptionKey:@"Error running pre-insatll script."}];
			reply(err,1,installResultData);
			return;
		}
		
		// ------------------------------------------------
		// Install PKG
		// ------------------------------------------------
		[self postStatus:@"Running pre-install script..."];
		result = [self installPkgFromZIP:[dlSoftwareFile stringByDeletingLastPathComponent] environment:swItem[@"pkgEnv"]];
		
		// ------------------------------------------------
		// Run Post Install Script, if copy was good
		// ------------------------------------------------
		if (result == 0)
		{
			[self postStatus:@"Running post-install script..."];
			if (![self runSWInstallScript:[swItem valueForKeyPath:@"Software.sw_post_install"] type:0]) {
				err = [NSError errorWithDomain:MPXPCErrorDomain code:MPPostInstallScriptError userInfo:@{NSLocalizedDescriptionKey:@"Error running post-insatll script."}];
			}
		}
	}
	else if ([pkgType isEqualToString:@"APPZIP" ignoringCase:YES])
	{
		qlinfo(@"Software Task is of type %@.",pkgType);
		// ------------------------------------------------
		// Check File Hash
		// ------------------------------------------------
		[self postStatus:@"Checking file hash..."];
		fHash = [mpCrypto md5HashForFile:dlSoftwareFile];
		if (![fHash isEqualToString:[swItem valueForKeyPath:@"Software.sw_hash"] ignoringCase:YES])
		{
			errStr = [NSString stringWithFormat:@"Error unable to verify software hash for file %@.",dlSoftwareFileName];
			qlerror(@"%@", errStr);
			err = [NSError errorWithDomain:MPXPCErrorDomain code:MPFileHashCheckError userInfo:@{NSLocalizedDescriptionKey:errStr}];
			reply(err,1,installResultData);
			return;
		}
		
		// ------------------------------------------------
		// Unzip Software
		// ------------------------------------------------
		[self postStatus:[NSString stringWithFormat:@"Unzipping file %@.",dlSoftwareFileName]];
		qlinfo(@"Unzipping file %@.",dlSoftwareFile);
		fu = [MPFileUtils new];
		BOOL res = [fu unzipItemAtPath:dlSoftwareFile targetPath:[dlSoftwareFile stringByDeletingLastPathComponent] error:&err];
		if (!res || err) {
			if (err) {
				errStr = [NSString stringWithFormat:@"Error unzipping file %@. %@",dlSoftwareFile,[err description]];
				qlerror(@"%@", errStr);
			} else {
				errStr = [NSString stringWithFormat:@"Error unzipping file %@.",dlSoftwareFile];
				qlerror(@"%@", errStr);
			}
			err = [NSError errorWithDomain:MPXPCErrorDomain code:MPFileUnZipError userInfo:@{NSLocalizedDescriptionKey:errStr}];
			reply(err,1,installResultData);
			return;
		}
		
		// ------------------------------------------------
		// Run Pre Install Script
		// ------------------------------------------------
		[self postStatus:@"Running pre-install script..."];
		if (![self runSWInstallScript:[swItem valueForKeyPath:@"Software.sw_pre_install"] type:0]) {
			err = [NSError errorWithDomain:MPXPCErrorDomain code:MPPreInstallScriptError userInfo:@{NSLocalizedDescriptionKey:@"Error running pre-insatll script."}];
			reply(err,1,installResultData);
			return;
		}
		
		// ------------------------------------------------
		// Copy App To Applications
		// ------------------------------------------------
		NSString *swUnzipDir = NULL;
		NSString *swUnzipDirBase = [[SW_DATA_DIR path] stringByAppendingPathComponent:@"sw"];
		swUnzipDir = [swUnzipDirBase stringByAppendingPathComponent:swItem[@"id"]];
		[self postStatus:[NSString stringWithFormat:@"Installing %@ to Applications.",[swUnzipDir lastPathComponent]]];
		result = [self copyAppFrom:swUnzipDir action:kMPMoveFile error:NULL];
		
		// ------------------------------------------------
		// Run Post Install Script, if copy was good
		// ------------------------------------------------
		if (result == 0)
		{
			[self postStatus:@"Running post-install script..."];
			if (![self runSWInstallScript:[swItem valueForKeyPath:@"Software.sw_post_install"] type:0]) {
				err = [NSError errorWithDomain:MPXPCErrorDomain code:MPPostInstallScriptError userInfo:@{NSLocalizedDescriptionKey:@"Error running post-insatll script."}];
			}
		}
	}
	else if ([pkgType isEqualToString:@"PACKAGEDMG" ignoringCase:YES])
	{
		qlinfo(@"Software Task is of type %@.",pkgType);
		// ------------------------------------------------
		// Check File Hash
		// ------------------------------------------------
		fHash = [mpCrypto md5HashForFile:dlSoftwareFile];
		if (![fHash isEqualToString:[swItem valueForKeyPath:@"Software.sw_hash"] ignoringCase:YES])
		{
			errStr = [NSString stringWithFormat:@"Error unable to verify software hash for file %@.",dlSoftwareFileName];
			qlerror(@"%@", errStr);
			err = [NSError errorWithDomain:MPXPCErrorDomain code:MPFileHashCheckError userInfo:@{NSLocalizedDescriptionKey:errStr}];
			reply(err,1,installResultData);
		}

		// ------------------------------------------------
		// Mount DMG
		// ------------------------------------------------
		int m = -1;
		m = [self mountDMG:dlSoftwareFile packageID:swItem[@"id"]];
		if (m != 0) {
			err = [NSError errorWithDomain:MPXPCErrorDomain code:MPMountDMGError userInfo:@{NSLocalizedDescriptionKey:@"Error mounting dmg."}];
			reply(err,1,installResultData);
		}
		
		// ------------------------------------------------
		// Run Pre Install Script
		// ------------------------------------------------
		[self postStatus:@"Running pre-install script..."];
		if (![self runSWInstallScript:[swItem valueForKeyPath:@"Software.sw_pre_install"] type:0]) {
			err = [NSError errorWithDomain:MPXPCErrorDomain code:MPPreInstallScriptError userInfo:@{NSLocalizedDescriptionKey:@"Error running pre-insatll script."}];
			reply(err,1,installResultData);
		}
		
		// ------------------------------------------------
		// Install PKG
		// ------------------------------------------------
		[self postStatus:@"Installing %@",dlSoftwareFileName];
		result = [self installPkgFromDMG:swItem[@"id"] environment:[swItem valueForKeyPath:@"Software.sw_env_var"]];

		// ------------------------------------------------
		// Run Post Install Script
		// ------------------------------------------------
		if (result == 0) {
			[self postStatus:@"Running post-install script..."];
			if (![self runSWInstallScript:[swItem valueForKeyPath:@"Software.sw_post_install"] type:0]) {
				err = [NSError errorWithDomain:MPXPCErrorDomain code:MPPostInstallScriptError userInfo:@{NSLocalizedDescriptionKey:@"Error running post-insatll script."}];
			}
		}
	}
	else if ([pkgType isEqualToString:@"APPDMG" ignoringCase:YES])
	{
		qlinfo(@"Software Task is of type %@.",pkgType);
		// ------------------------------------------------
		// Check File Hash
		// ------------------------------------------------
		fHash = [mpCrypto md5HashForFile:dlSoftwareFile];
		if (![fHash isEqualToString:[swItem valueForKeyPath:@"Software.sw_hash"] ignoringCase:YES])
		{
			errStr = [NSString stringWithFormat:@"Error unable to verify software hash for file %@.",dlSoftwareFileName];
			qlerror(@"%@", errStr);
			err = [NSError errorWithDomain:MPXPCErrorDomain code:MPFileHashCheckError userInfo:@{NSLocalizedDescriptionKey:errStr}];
			reply(err,1,installResultData);
		}
		
		// ------------------------------------------------
		// Mount DMG
		// ------------------------------------------------
		int m = -1;
		m = [self mountDMG:dlSoftwareFile packageID:swItem[@"id"]];
		if (m != 0) {
			err = [NSError errorWithDomain:MPXPCErrorDomain code:MPMountDMGError userInfo:@{NSLocalizedDescriptionKey:@"Error mounting dmg."}];
			reply(err,1,installResultData);
		}
		
		// ------------------------------------------------
		// Run Pre Install Script
		// ------------------------------------------------
		[self postStatus:@"Running pre-install script..."];
		if (![self runSWInstallScript:[swItem valueForKeyPath:@"Software.sw_pre_install"] type:0]) {
			err = [NSError errorWithDomain:MPXPCErrorDomain code:MPPreInstallScriptError userInfo:@{NSLocalizedDescriptionKey:@"Error running pre-insatll script."}];
			reply(err,1,installResultData);
		}
		
		// ------------------------------------------------
		// Copy App To Applications
		// ------------------------------------------------
		[self postStatus:@"Installing %@",dlSoftwareFileName];
		result = [self copyAppFromDMG:swItem[@"id"]];
		
		// ------------------------------------------------
		// Run Post Install Script
		// ------------------------------------------------
		if (result == 0) {
			[self postStatus:@"Running post-install script..."];
			if (![self runSWInstallScript:[swItem valueForKeyPath:@"Software.sw_post_install"] type:0]) {
				err = [NSError errorWithDomain:MPXPCErrorDomain code:MPPostInstallScriptError userInfo:@{NSLocalizedDescriptionKey:@"Error running post-insatll script."}];
			}
		}
	}
	else
	{
		qlinfo(@"Install Type Not Supported");
		// Install Type Not Supported
		result = 2;
	}
	
	
	if (result == 0)
	{
		if ([[swItem valueForKeyPath:@"Software.auto_patch"] intValue] == 1) {
			err = nil;
			// Install Pathes If Enabled
			[self postStatus:@"Patching %@",swItem[@"name"]];
			MPPatching *p = [MPPatching new];
			NSArray *foundPatches = [p scanForPatchUsingBundleID:[swItem valueForKeyPath:@"Software.patch_bundle_id"]];
			if (foundPatches)
			{
				if (foundPatches.count >= 1)
				{
					[p installPatchesUsingTypeFilter:foundPatches typeFilter:kCustomPatches];
				}
			}
		}
	}
	
	reply(err,result,installResultData);
}

- (BOOL)downloadSoftware:(NSDictionary *)swTask toDestination:(NSString *)toPath
{
	NSString *_url = [NSString stringWithFormat:@"/mp-content%@",[swTask valueForKeyPath:@"Software.sw_url"]];
	
	NSError *dlErr = nil;
	MPHTTPRequest *req = [[MPHTTPRequest alloc] init];
	req.delegate = self;
	NSString *dlPath = [req runSyncFileDownloadAlt:_url downloadDirectory:toPath error:&dlErr];
	qldebug(@"Downloaded software to %@",dlPath);
	return YES;
}

// Run Software Scripts
- (void)runScriptFromString:(NSString *)script withReply:(void(^)(NSError * error, NSInteger result))reply
{
    NSError  *err = nil;
    MPScript *mps = nil;
    int res = 0;
    mps = [[MPScript alloc] init];
    if ([mps runScript:script]) {
        res = 0;
    } else {
        res = 1;
    }
    
    mps = nil;
    reply(err,res);
}

- (void)runScriptFromFile:(NSString *)script withReply:(void(^)(NSError * error, NSInteger result))reply
{
    NSError  *err = nil;
    NSString *scriptText = nil;
    MPScript *mps = nil;
    int res = 0;
    scriptText = [NSString stringWithContentsOfFile:script encoding:NSUTF8StringEncoding error:&err];
    if (err) {
        logit(lcl_vError,@"Error reading script string: %@",[err description]);
        logit(lcl_vError,@"%@",[err description]);
        reply(err,3);
        return;
    }
    
    mps = [[MPScript alloc] init];
    if ([mps runScript:scriptText]) {
        res = 0;
    } else {
        res = 1;
    }
    
    mps = nil;
    reply(err,res);
}

- (void)runScriptFromDirectory:(NSString *)scriptDir withReply:(void(^)(NSError *error, NSInteger result))reply
{
    int result = 0;
    NSArray *dirContents = [fm contentsOfDirectoryAtPath:scriptDir error:nil];
    NSPredicate *fltr = [NSPredicate predicateWithFormat:@"(SELF like [cd] '*.sh') OR (SELF like [cd] '*.rb') OR (SELF like [cd] '*.py')"];
    NSArray *onlyScripts = [dirContents filteredArrayUsingPredicate:fltr];
    
    NSError *err = nil;
    NSString *scriptText = nil;
    MPScript *mps = nil;
    for (NSString *scpt in onlyScripts)
    {
        err = nil;
        scriptText = [NSString stringWithContentsOfFile:[scriptDir stringByAppendingPathComponent:scpt] encoding:NSUTF8StringEncoding error:&err];
        if (err) {
            logit(lcl_vError,@"Error reading script string: %@",[err description]);
            logit(lcl_vError,@"%@",[err description]);
            result = 3;
            break;
        }
        mps = [[MPScript alloc] init];
        //[self postDataToClient:[NSString stringWithFormat:@"Running script %@",scpt] type:kMPProcessStatus];
        if ([mps runScript:scriptText]) {
            result = 0;
        } else {
            result = 1;
            break;
        }
        mps = nil;
    }
    
    reply(err,result);
}

// Run Software Package Install
- (void)installPackageFromZIP:(NSString *)pkgID environment:(NSString *)env withReply:(void(^)(NSError *error, NSInteger result))reply
{
    int result = 0;
    NSString *mountPoint = NULL;
    mountPoint = [NSString pathWithComponents:@[[SW_DATA_DIR path],@"sw",pkgID]];
    
    NSArray     *dirContents = [fm contentsOfDirectoryAtPath:mountPoint error:nil];
    NSPredicate *fltr        = [NSPredicate predicateWithFormat:@"(SELF like [cd] '*.pkg') OR (SELF like [cd] '*.mpkg')"];
    NSArray     *onlyPkgs    = [dirContents filteredArrayUsingPredicate:fltr];
    
    NSArray *installArgs;
    NSString *pkgPath;
    for (NSString *pkg in onlyPkgs)
    {
        pkgPath = [NSString pathWithComponents:@[[SW_DATA_DIR path],@"sw",pkgID, pkg]];
        installArgs = @[@"-verboseR", @"-pkg", pkgPath, @"-target", @"/"];
        
        if ([self runTask:INSTALLER_BIN_PATH binArgs:installArgs environment:env] != 0) {
            result++;
        }
        
        pkgPath = nil;
    }
    
    reply(nil,result);
}

// Copy Application To Applications Directory
- (void)copyAppFromDirToApplications:(NSString *)aDir action:(int)action withReply:(void(^)(NSError *error, NSInteger result))reply
{
    int result = 0;
    NSArray     *dirContents = [fm contentsOfDirectoryAtPath:aDir error:nil];
    NSPredicate *fltr        = [NSPredicate predicateWithFormat:@"self ENDSWITH '.app'"];
    NSArray     *onlyApps    = [dirContents filteredArrayUsingPredicate:fltr];
    NSError     *err         = nil;
    
    for (NSString *app in onlyApps)
    {
        if ([fm fileExistsAtPath:[@"/Applications"  stringByAppendingPathComponent:app]]) {
            qlinfo(@"Found, %@. Now remove it.",[@"/Applications" stringByAppendingPathComponent:app]);
            [fm removeItemAtPath:[@"/Applications" stringByAppendingPathComponent:app] error:&err];
            if (err) {
                logit(lcl_vError,@"%@",[err description]);
                result = 3;
                break;
            }
        }
        
        err = nil;
        if (action == 0) {
            [fm copyItemAtPath:[aDir stringByAppendingPathComponent:app] toPath:[@"/Applications" stringByAppendingPathComponent:app] error:&err];
        } else if (action == 1) {
            [fm moveItemAtPath:[aDir stringByAppendingPathComponent:app] toPath:[@"/Applications" stringByAppendingPathComponent:app] error:&err];
        } else {
            [fm copyItemAtPath:[aDir stringByAppendingPathComponent:app] toPath:[@"/Applications" stringByAppendingPathComponent:app] error:&err];
        }
        
        if (err) {
            logit(lcl_vError,@"%@",[err description]);
            result = 2;
            break;
        }
        
        err = nil;
        [self changeOwnershipOfApp:[@"/Applications" stringByAppendingPathComponent:app] owner:@"root" group:@"admin" error:&err];
        if (err) {
            logit(lcl_vError,@"%@",[err description]);
            result = 3;
            break;
        }
    }
    
    reply(err, result);
}

// Install PKG from DMG
- (void)installPkgFromDMG:(NSString *)dmgPath packageID:(NSString *)packageID environment:(NSString *)aEnv withReply:(void(^)(NSError *error, NSInteger result))reply
{
    if ([self mountDMG:dmgPath packageID:packageID] != 0) {
        // Need a NSError reason
        reply(nil, 1);
        return;
    }
    
    int result = 0;
    NSString *mountPoint = [NSString pathWithComponents:@[[SW_DATA_DIR path], @"dmg", packageID]];
    
    NSArray     *dirContents = [fm contentsOfDirectoryAtPath:mountPoint error:nil];
    NSPredicate *fltr        = [NSPredicate predicateWithFormat:@"(SELF like [cd] '*.pkg') OR (SELF like [cd] '*.mpkg')"];
    NSArray     *onlyPkgs    = [dirContents filteredArrayUsingPredicate:fltr];
    
    int pkgInstallResult = -1;
    NSArray *installArgs;
    for (NSString *pkg in onlyPkgs)
    {
        //[self postDataToClient:[NSString stringWithFormat:@"Begin installing %@",pkg] type:kMPProcessStatus];
        installArgs = @[@"-verboseR", @"-pkg", [mountPoint stringByAppendingPathComponent:pkg], @"-target", @"/"];
        pkgInstallResult = [self runTask:INSTALLER_BIN_PATH binArgs:installArgs environment:aEnv];
        if (pkgInstallResult != 0) {
            result++;
        }
    }
    
    [self unmountDMG:dmgPath packageID:packageID];
    reply(nil, result);
}

// Uninstall Software Task using task ID
- (void)uninstallSoftware:(NSString *_Nonnull)swTaskID withReply:(nullable void(^)(NSInteger resultCode))reply
{
	qlinfo(@"uninstallSoftware[taskID]: %@",swTaskID);
	@try
	{
		MPClientDB *db = [MPClientDB new];
		InstalledSoftware *_swTask = [db getSoftwareTaskUsingID:swTaskID];
		
		if (!_swTask) {
			qlerror(@"Software task id (%@) could not be found. Uninstall will not occure.",swTaskID);
			reply(1);
			return;
		}
		
		// Check for uninstall script data
		if ([[_swTask.uninstall trim] length] <= 3) {
			qlinfo(@"Task has no uninstall script.");
			reply(0);
			return;
		}
		
		// Verify uninstall script is base 64 encoded.
		NSString *uninstallScript = nil;
		if ([_swTask.uninstall isBase64String]) {
			uninstallScript = [_swTask.uninstall decodeBase64AsString];
		} else {
			qlerror(@"Uninstall script was not encoded, or encoding could not be detected. No uninstall will occure.");
			reply(1);
			return;
		}
		
		// If has decoded script, run uninstall
		if (uninstallScript)
		{
			qlinfo(@"Running uninstall script.");
			MPScript *mps = [[MPScript alloc] init];
			BOOL result = [mps runScript:uninstallScript];
			qlinfo(@"Uninstall script was %@.", result ? @"Sucessful": @"Unsucessful");
			if (result) {
				reply(0);
			} else {
				reply(1);
			}
		} else {
			qlinfo(@"No uninstall script to run.");
			reply(0);
		}
		return;
	} @catch (NSException *exception) {
		qlerror(@"%@",exception);
		reply(1);
		return;
	}
}

- (InstalledSoftware *)getSWTaskUsingTaskID:(NSString *)swTaskID
{
	InstalledSoftware *_swTask = nil;
	MPClientDB *cdb = [MPClientDB new];
	_swTask = [cdb getSoftwareTaskUsingID:swTaskID];
	return _swTask;
}

#pragma mark • MacPatch Client Database

- (void)createAndUpdateDatabase:(void(^)(BOOL result))reply
{
	MPClientDB *cdb = [MPClientDB new];
	cdb = nil;
	reply(YES);
}

- (void)recordSoftwareInstallAdd:(NSDictionary*)swTask withReply:(void(^)(NSInteger result))reply
{
	MPClientDB *cdb = [MPClientDB new];
	BOOL result = [cdb recordSoftwareInstall:swTask];
	if (result)
	{
		reply(0);
	} else {
		reply(1);
	}
}

- (void)recordPatchInstall:(NSDictionary *)patch withReply:(void(^)(NSInteger result))reply
{
	MPClientDB *cdb = [MPClientDB new];
	BOOL result = [cdb recordPatchInstall:patch];
	if (result)
	{
		reply(0);
	} else {
		reply(1);
	}
}

- (void)retrieveInstalledSoftwareTasksWithReply:(void(^)(NSData *result))reply
{
	NSArray *tasks = [NSArray array];
	MPClientDB *cdb = [MPClientDB new];
	tasks = [cdb retrieveInstalledSoftwareTasks];
	NSData *data = [NSKeyedArchiver archivedDataWithRootObject:tasks];
	reply(data);
}

- (void)recordSoftwareInstallRemove:(NSString *)swTaskName taskID:(NSString *)swTaskID withReply:(void(^)(BOOL result))reply
{
	MPClientDB *cdb = [MPClientDB new];
	BOOL result = [cdb recordSoftwareUninstall:swTaskName taskID:swTaskID];
	reply(result);
}

- (void)recordHistoryWithType:(DBHistoryType)hstType name:(NSString *)aName
						 uuid:(NSString *)aUUID
					   action:(DBHistoryAction)aAction
					   result:(NSInteger)code
					 errorMsg:(NSString * _Nullable)aErrMsg
					withReply:(void(^)(BOOL result))reply
{
	MPClientDB *cdb = [MPClientDB new];
	BOOL result = [cdb recordHistory:hstType name:aName uuid:aUUID action:aAction result:code errorMsg:aErrMsg];
	reply(result);
}

// Patching
// Add required patch to database table to manage state.
- (void)addRequiredPatch:(NSData *)patch withReply:(void(^)(BOOL result))reply
{
	NSDictionary *_patch = [NSKeyedUnarchiver unarchiveObjectWithData:patch];
	MPClientDB *cdb = [MPClientDB new];
	BOOL result = [cdb addRequiredPatch:_patch];
	reply(result);
}

- (void)clearRequiredPatchesWithReply:(void(^)(BOOL result))reply
{
	MPClientDB *cdb = [MPClientDB new];
	BOOL result = [cdb clearRequiredPatches];
	[cdb clearRequiredPatches];
	reply(result);
}

// Patching
// After patch has been installed the record is removed from database table of required patches.
- (void)removeRequiredPatch:(NSString *)type patchID:(NSString *)patchID patch:(NSString *)patch withReply:(void(^)(BOOL result))reply
{
	MPClientDB *cdb = [MPClientDB new];
	BOOL result = [cdb removeRequiredPatch:type patchID:patchID patch:patch];
	reply(result);
}

#pragma mark • Agent Protocol

// Software
// Post Status Text
- (void)postStatus:(NSString *)status,...
{
	@try {
		va_list args;
		va_start(args, status);
		NSString *statusStr = [[NSString alloc] initWithFormat:status arguments:args];
		va_end(args);
		
		qltrace(@"postStatus[XPCWorker]: %@",statusStr);
		[[self.xpcConnection remoteObjectProxy] postStatus:statusStr type:kMPProcessStatus];
	}
	@catch (NSException *exception) {
		qlerror(@"%@",exception);
	}
}

// Post Progress for a progress bar
- (void)postProgress:(double)data
{
	@try
	{
		if ((int)data % 5 == 0)
		{
			qlinfo(@"Progress: %3d",(int)data);
		}
		
		[[self.xpcConnection remoteObjectProxy] postStatus:[NSString stringWithFormat:@"%lf", data] type:kMPProcessProgress];
	}
	@catch (NSException *exception) {
		qlerror(@"%@",exception);
	}
}

// Patching
// Post Status Text
- (void)postPatchStatus:(NSString *)status,...
{
	@try {
		va_list args;
		va_start(args, status);
		NSString *statusStr = [[NSString alloc] initWithFormat:status arguments:args];
		va_end(args);
		
		qltrace(@"postPatchStatus[XPCWorker]: %@",statusStr);
		[[self.xpcConnection remoteObjectProxy] postStatus:statusStr type:kMPPatchProcessStatus];
	}
	@catch (NSException *exception) {
		qlerror(@"%@",exception);
	}
}

// Post Status Text
- (void)postPatchAllStatus:(NSString *)status,...
{
	qlinfo(@"Calling postPatchAllStatus");
	@try {
		va_list args;
		va_start(args, status);
		NSString *statusStr = [[NSString alloc] initWithFormat:status arguments:args];
		va_end(args);
		
		qltrace(@"postPatchStatus[XPCWorker]: %@",statusStr);
		[[self.xpcConnection remoteObjectProxy] postStatus:statusStr type:kMPPatchAllProcessStatus];
	}
	@catch (NSException *exception) {
		qlerror(@"%@",exception);
	}
}

// Post Progress for a progress bar
- (void)postPatchProgress:(double)data
{
	@try {
		if ((int)data % 5 == 0)
		{
			qlinfo(@"Progress: %3d",(int)data);
		}
		[[self.xpcConnection remoteObjectProxy] postStatus:[NSString stringWithFormat:@"%lf", data] type:kMPPatchProcessProgress];
	}
	@catch (NSException *exception) {
		qlerror(@"%@",exception);
	}
	//qlinfo(@"Progress: %lf",data);
}

// Post Progress for a progress bar, for patch all
- (void)postPatchAllProgress:(double)data
{
	@try {
		qlinfo(@"Patch All Progress: %3d",(int)data);
		[[self.xpcConnection remoteObjectProxy] postStatus:[NSString stringWithFormat:@"%lf", data] type:kMPPatchAllProcessProgress];
	}
	@catch (NSException *exception) {
		qlerror(@"%@",exception);
	}
}

- (void)postPatchInstallCompletion:(NSString *)patchID
{
	qlinfo(@"postPatchInstallCompletion for %@",patchID);
	@try {
		[[self.xpcConnection remoteObjectProxy] postPatchInstallStatus:patchID type:kMPPatchAllInstallComplete];
	}
	@catch (NSException *exception) {
		qlerror(@"%@",exception);
	}
}
#pragma mark • Misc

- (void)unzip:(NSString *)aFile withReply:(void(^)(NSError *error, NSInteger result))reply
{
    int res = 0;
	MPFileUtils *fu = [MPFileUtils new];
    NSError *err = nil;
    res = [fu unzip:aFile error:&err];
    reply(err,res);
}


#pragma mark • Client Checkin

- (void)runCheckInWithReply:(void(^)(NSError *error, NSDictionary *result))reply
{
	// Collect Agent Checkin Data
	MPClientInfo *ci = [[MPClientInfo alloc] init];
	NSDictionary *agentData = [ci agentData];
	if (!agentData)
	{
		logit(lcl_vError,@"Agent data is nil, can not post client checkin data.");
		return;
	}
	
	// Post Client Checkin Data to WS
	NSError *error = nil;
	NSDictionary *revsDict;
	MPRESTfull *rest = [[MPRESTfull alloc] init];
	revsDict = [rest postClientCheckinData:agentData error:&error];
	if (error) {
		logit(lcl_vError,@"Running client check in had an error.");
		logit(lcl_vError,@"%@", error.localizedDescription);
	}
	else
	{
		[self updateGroupSettings:revsDict];
	}
	
	logit(lcl_vInfo,@"Running client check in completed.");
	reply(error,revsDict);
}

- (void)updateGroupSettings:(NSDictionary *)settingRevisions
{
	// Query for Revisions
	// Call MPSettings to update if nessasary
	logit(lcl_vInfo,@"Check and Update Agent Settings.");
	logit(lcl_vDebug,@"Setting Revisions from server: %@", settingRevisions);
	MPSettings *set = [MPSettings sharedInstance];
	[set compareAndUpdateSettings:settingRevisions];
	return;
}


// Helpers

- (int)runTask:(NSString *)aBinPath binArgs:(NSArray *)aBinArgs environment:(NSString *)env
{
    NSString		*tmpStr;
    NSMutableData	*data;
    NSData			*dataChunk = nil;
    NSException		*error = nil;
    
    
    //[self setTaskIsRunning:YES];
    //[self setTaskTimedOut:NO];
    
    int taskResult = -1;
    
    swTask = [[NSTask alloc] init];
    NSPipe *aPipe = [NSPipe pipe];
    
    [swTask setStandardOutput:aPipe];
    [swTask setStandardError:aPipe];
    
    // Parse the Environment variables for the install
    NSDictionary *defaultEnvironment = [[NSProcessInfo processInfo] environment];
    NSMutableDictionary *environment = [[NSMutableDictionary alloc] initWithDictionary:defaultEnvironment];
    [environment setObject:@"YES" forKey:@"NSUnbufferedIO"];
    [environment setObject:@"1" forKey:@"COMMAND_LINE_INSTALL"];
    
    if ([env isEqualToString:@"NA"] == NO && [[env trim] length] > 0)
    {
        NSArray *l_envArray;
        NSArray *l_envItems;
        l_envArray = [env componentsSeparatedByString:@","];
        for (id item in l_envArray) {
            l_envItems = nil;
            l_envItems = [item componentsSeparatedByString:@"="];
            if ([l_envItems count] == 2) {
                logit(lcl_vDebug,@"Setting env variable(%@=%@).",[l_envItems objectAtIndex:0],[l_envItems objectAtIndex:1]);
                [environment setObject:[l_envItems objectAtIndex:1] forKey:[l_envItems objectAtIndex:0]];
            } else {
                logit(lcl_vError,@"Unable to set env variable. Variable not well formed %@",item);
            }
        }
    }
    
    [swTask setEnvironment:environment];
    logit(lcl_vDebug,@"[task][environment]: %@",environment);
    [swTask setLaunchPath:aBinPath];
    logit(lcl_vDebug,@"[task][setLaunchPath]: %@",aBinPath);
    [swTask setArguments:aBinArgs];
    logit(lcl_vDebug,@"[task][setArguments]: %@",aBinArgs);
    
    // Launch The NSTask
    @try {
        [swTask launch];
        // If timeout is set start it ...
        if (swTaskTimeoutValue != 0) {
            [NSThread detachNewThreadSelector:@selector(taskTimeoutThread) toTarget:self withObject:nil];
        }
    }
    @catch (NSException *e)
    {
        logit(lcl_vError,@"Install returned error. %@\n%@",[e reason],[e userInfo]);
        taskResult = 1;
        goto done;
    }
    
    data = [[NSMutableData alloc] init];
    dataChunk = nil;
    error = nil;
    
    while(swTaskTimedOut == NO && ((dataChunk = [[aPipe fileHandleForReading] availableDataOrError:&error]) && [dataChunk length] && error == nil))
    {
        // If the data is not null, then post the data back to the client and log it locally
        tmpStr = [[NSString alloc] initWithData:dataChunk encoding:NSUTF8StringEncoding];
        if ([[tmpStr trim] length] != 0)
        {
            if ([tmpStr containsString:@"PackageKit: Missing bundle path"] == NO) {
                qlinfo(@"%@",tmpStr);
                //[self postDataToClient:tmpStr type:kMPInstallStatus];
            } else {
                qlinfo(@"%@",tmpStr);
            }
        }
        
        [data appendData:dataChunk];
        tmpStr = nil;
    }
    
    [[aPipe fileHandleForReading] closeFile];
    
    if (swTaskTimedOut == YES) {
        logit(lcl_vError,@"Task was terminated due to timeout.");
        [NSThread sleepForTimeInterval:5.0];
        [swTask terminate];
        taskResult = 1;
        goto done;
    }
    
    if([data length] && error == nil)
    {
        if ([swTask isRunning])
        {
            for (int i = 0; i < 30; i++)
            {
                if ([swTask isRunning]) {
                    [NSThread sleepForTimeInterval:1.0];
                } else {
                    break;
                }
            }
            // Task should be complete
            qlinfo(@"Terminate Software Task.");
            [swTask terminate];
        }
        
        int status = [swTask terminationStatus];
        qlinfo(@"swTask terminationStatus: %d",status);
        if (status == 0) {
            taskResult = 0;
        } else {
            taskResult = 1;
        }
    } else {
        logit(lcl_vError,@"Install returned error. Code:[%d]",[swTask terminationStatus]);
        taskResult = 1;
    }
    
done:
    
    if(swTaskTimer) {
        [swTaskTimer invalidate];
    }

    self->swTaskIsRunning = NO;
    return taskResult;
}

- (void)taskTimeoutThread
{
    @autoreleasepool {
        
        [swTaskTimer invalidate];
        
        qlinfo(@"Timeout is set to %d",swTaskTimeoutValue);
        NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:swTaskTimeoutValue
                                                          target:self
                                                        selector:@selector(taskTimeout:)
                                                        userInfo:nil
                                                         repeats:NO];
        
        self->swTaskTimer = timer;
        while (swTaskTimedOut == NO && [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]]);
        
    }
    
}

- (void)taskTimeout:(NSNotification *)aNotification
{
    qlinfo(@"Task timedout, killing task.");
    [swTaskTimer invalidate];
    swTaskTimedOut = YES;
    [swTask terminate];
}

- (void)changeOwnershipOfApp:(NSString *)aApp owner:(NSString *)aOwner group:(NSString *)aGroup error:(NSError **)err
{
    NSDictionary *permDict = @{NSFileOwnerAccountName:aOwner,NSFileGroupOwnerAccountName:aGroup};
    NSError *error = nil;
    [fm setAttributes:permDict ofItemAtPath:aApp error:&error];
    if (error) {
        if (err != NULL) *err = error;
        qlerror(@"Error settings permission %@",[error description]);
        return;
    }
    
    error = nil;
    NSArray *aContents = [fm subpathsOfDirectoryAtPath:aApp error:&error];
    if (error) {
        if (err != NULL) *err = error;
        qlerror(@"Error subpaths of Directory %@.\n%@",aApp,[error description]);
        return;
    }
    if (!aContents) {
        qlerror(@"No contents found for %@",aApp);
        return;
    }
    
    for (NSString *i in aContents)
    {
        error = nil;
        [[NSFileManager defaultManager] setAttributes:permDict ofItemAtPath:[aApp stringByAppendingPathComponent:i] error:&error];
        if (error) {
            if (err != NULL) *err = error;
            qlerror(@"Error settings permission %@",[error description]);
        }
    }
}

- (int)installPkgFromZIP:(NSString *)pkgPathDir environment:(NSString *)aEnv
{
	int result = 0;

	NSArray *dirContents = [fm contentsOfDirectoryAtPath:pkgPathDir error:nil];
	NSPredicate *fltr = [NSPredicate predicateWithFormat:@"(SELF like [cd] '*.pkg') OR (SELF like [cd] '*.mpkg')"];
	NSArray *onlyPkgs = [dirContents filteredArrayUsingPredicate:fltr];
	
	int pkgInstallResult = -1;
	NSArray *installArgs;
	for (NSString *pkg in onlyPkgs)
	{
		qlinfo(@"Installing %@",pkg);
		NSString *pkgPath = [pkgPathDir stringByAppendingPathComponent:pkg];
		installArgs = @[@"-verboseR", @"-pkg", pkgPath, @"-target", @"/"];
		pkgInstallResult = [self runTask:INSTALLER_BIN_PATH binArgs:installArgs environment:aEnv];
		if (pkgInstallResult != 0) {
			result++;
		}
	}
	
	return result;
}

- (int)mountDMG:(NSString *)dmgPath packageID:(NSString *)pkgID
{
    qlinfo(@"Mounting DMG %@",dmgPath);
    NSString *mountPoint = [NSString pathWithComponents:@[[SW_DATA_DIR path], @"dmg", pkgID]];
    logit(lcl_vDebug,@"[mountDMG] mountPoint: %@",mountPoint);
    
    NSError *err = nil;
    if ([fm fileExistsAtPath:mountPoint]) {
        [self unmountDMG:dmgPath packageID:pkgID]; // Unmount incase it's already mounted
    }
    [fm createDirectoryAtPath:mountPoint withIntermediateDirectories:YES attributes:nil error:&err];
    if (err) {
        logit(lcl_vError,@"%@",err.localizedDescription);
        return 1;
    }
    
    // Check if DMG exists
    if ([fm fileExistsAtPath:dmgPath] == NO) {
        logit(lcl_vError,@"File \"%@\" does not exist.",dmgPath);
        return 1;
    }
    
    NSArray *args = @[@"attach", @"-mountpoint", mountPoint, dmgPath, @"-nobrowse"];
    NSTask  *aTask = [[NSTask alloc] init];
    NSPipe  *pipe = [NSPipe pipe];
    
    [aTask setLaunchPath:@"/usr/bin/hdiutil"];
    [aTask setArguments:args];
    [aTask setStandardInput:pipe];
    [aTask setStandardOutput:[NSFileHandle fileHandleWithNullDevice]];
    [aTask setStandardError:[NSFileHandle fileHandleWithStandardError]];
    [aTask launch];
    [aTask waitUntilExit];
    
    int result = [aTask terminationStatus];
    if (result == 0) {
        qlinfo(@"DMG Mounted %@", mountPoint);
    }
    
    return result;
}

- (int)unmountDMG:(NSString *)dmgPath packageID:(NSString *)pkgID
{
    NSString *mountPoint = [NSString pathWithComponents:@[[SW_DATA_DIR path], @"dmg", pkgID]];
    qlinfo(@"Un-Mounting DMG %@",mountPoint);
    
    NSArray       *args  = @[@"detach", mountPoint, @"-force"];
    NSTask        *aTask = [[NSTask alloc] init];
    NSPipe        *pipe  = [NSPipe pipe];
    
    [aTask setLaunchPath:@"/usr/bin/hdiutil"];
    [aTask setArguments:args];
    [aTask setStandardInput:pipe];
    [aTask setStandardOutput:[NSFileHandle fileHandleWithNullDevice]];
    [aTask setStandardError:[NSFileHandle fileHandleWithStandardError]];
    [aTask launch];
    [aTask waitUntilExit];
    
    int result = [aTask terminationStatus];
    if (result == 0) {
        qlinfo(@"DMG Un-Mounted %@",dmgPath);
    }
    
    return result;
}

- (int)installPkgFromDMG:(NSString *)pkgID environment:(NSString *)aEnv
{
	int result = 0;
	NSString *mountPoint = NULL;
	NSString *mountPointBase = [[SW_DATA_DIR path] stringByAppendingPathComponent:@"dmg"];
	mountPoint = [mountPointBase stringByAppendingPathComponent:pkgID];
	
	NSArray *dirContents = [fm contentsOfDirectoryAtPath:mountPoint error:nil];
	NSPredicate *fltr = [NSPredicate predicateWithFormat:@"(SELF like [cd] '*.pkg') OR (SELF like [cd] '*.mpkg')"];
	NSArray *onlyPkgs = [dirContents filteredArrayUsingPredicate:fltr];
	
	int pkgInstallResult = -1;
	NSArray *installArgs;
	for (NSString *pkg in onlyPkgs)
	{
		qlinfo(@"Begin installing %@",pkg);
		installArgs = [NSArray arrayWithObjects:@"-verboseR", @"-pkg", [mountPoint stringByAppendingPathComponent:pkg], @"-target", @"/", nil];
		pkgInstallResult = [self runTask:INSTALLER_BIN_PATH binArgs:installArgs environment:aEnv];
		if (pkgInstallResult != 0) {
			result++;
		}
	}
	
	[self unmountDMG:mountPoint packageID:pkgID];
	return result;
}

- (int)copyAppFromDMG:(NSString *)pkgID
{
	int result = 0;
	NSString *mountPoint = NULL;
	NSString *mountPointBase = [[SW_DATA_DIR path] stringByAppendingPathComponent:@"dmg"];
	mountPoint = [mountPointBase stringByAppendingPathComponent:pkgID];
	
	result = [self copyAppFrom:mountPoint action:kMPCopyFile error:NULL];
	
	[self unmountDMG:mountPoint packageID:pkgID];
	return result;
}
#pragma mark • OS Profiles
- (void)scanForInstalledConfigProfiles:(void(^)(NSArray *profiles))reply
{
	qlinfo(@"scanForInstalledConfigProfiles");
	MPConfigProfiles *p = [[MPConfigProfiles alloc] init];
	NSArray *cp = [p readProfileStoreReturnAsConfigProfile];
	qlinfo(@"Profiles Found %lu",(unsigned long)cp.count);
	reply(cp);
}

- (void)getInstalledConfigProfilesWithReply:(void(^)(NSString *aString, NSData *aProfilesData))reply
{
	qlinfo(@"getInstalledConfigProfilesWithReply");
	MPConfigProfiles *p = [[MPConfigProfiles alloc] init];
	NSArray *cp = [p readProfileStoreReturnAsConfigProfile];
	NSData *data = [NSKeyedArchiver archivedDataWithRootObject:cp];
	qlinfo(@"Profiles Found %lu",(unsigned long)cp.count);
	reply(@"Hello",data);
}

#pragma mark - Private

- (NSData *)encodeResult:(NSData *)dataToEncode error:(NSError **)error
{
	/*
    NSError *_error = nil;
	
    MPHost *mh = [MPHost defaultManager];
    NSString *mhID = [mh genHostID];
    NSData *result = [RNEncryptor encryptData:dataToEncode
                                 withSettings:kRNCryptorAES256Settings
                                     password:mhID
                                        error:&_error];
    if (error != NULL) *error =_error;
    return result;
	 */
	return nil;
}

- (NSURL *)swDataDirURL
{
	NSURL *appSupportDir = [[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSSystemDomainMask] objectAtIndex:0];
	NSURL *appSupportMPDir = [appSupportDir URLByAppendingPathComponent:@"MacPatch/SW_Data"];
	[self configDataDir];
	return appSupportMPDir;
}

/**
 Method will run a script using MPScript.
 
 aScript (NSString) is a Base64 encoded string.
 
 aScriptType (int) is for the logging it's
 	values: 0 = pre and 1 = post
 */
-(BOOL)runSWInstallScript:(NSString *)aScript type:(int)aScriptType
{
	NSString *_script;
	MPScript *mps = [[MPScript alloc] init];
	if (!aScript) return YES;
	if ([aScript isEqualToString:@""]) return YES;
	
	NSString *_scriptType = (aScriptType == 0) ? @"pre" : @"post";
	
	@try
	{
		_script = [aScript decodeBase64AsString];
		if (![mps runScript:_script]) {
			logit(lcl_vError,@"Error running %@ install script. No install will occure.", _scriptType);
			return NO;
		} else {
			return YES;
		}
	}
	@catch (NSException *exception) {
		logit(lcl_vError,@"Exception Error running %@ install script. No install will occure.", _scriptType);
		logit(lcl_vError,@"%@",exception);
		return NO;
	}
	
	qlerror(@"Reached end of runSWInstallScript, should not happen.");
	return NO;
}

/**
 Copy application from a directory to the Applications directory
 
 action is MPFileMoveAction kMPFileCopy or kMPFileMove
 
 Method also calls changeOwnershipOfItem
 */
- (int)copyAppFrom:(NSString *)aDir action:(MPFileMoveAction)action error:(NSError **)error
{
	int result = 0;
	NSArray *dirContents = [fm contentsOfDirectoryAtPath:aDir error:nil];
	NSPredicate *fltr = [NSPredicate predicateWithFormat:@"self ENDSWITH '.app'"];
	NSArray *onlyApps = [dirContents filteredArrayUsingPredicate:fltr];
	
	NSError *err = nil;
	for (NSString *app in onlyApps)
	{
		if ([fm fileExistsAtPath:[@"/Applications"  stringByAppendingPathComponent:app]])
		{
			logit(lcl_vInfo,@"Found, %@. Now remove it.",[@"/Applications" stringByAppendingPathComponent:app]);
			[fm removeItemAtPath:[@"/Applications" stringByAppendingPathComponent:app] error:&err];
			if (err) {
				if (error != NULL) *error = err;
				result = 3;
				break;
			}
		}
		err = nil;
		if (action == kMPCopyFile) {
			[fm copyItemAtPath:[aDir stringByAppendingPathComponent:app] toPath:[@"/Applications" stringByAppendingPathComponent:app] error:&err];
		} else if (action == kMPMoveFile) {
			[fm moveItemAtPath:[aDir stringByAppendingPathComponent:app] toPath:[@"/Applications" stringByAppendingPathComponent:app] error:&err];
		} else {
			[fm copyItemAtPath:[aDir stringByAppendingPathComponent:app] toPath:[@"/Applications" stringByAppendingPathComponent:app] error:&err];
		}
		
		if (err)
		{
			if (error != NULL) *error = err;
			result = 2;
			break;
		}
		
		[self changeOwnershipOfItem:[@"/Applications" stringByAppendingPathComponent:app] owner:@"root" group:@"admin"];
	}
	
	return result;
}

/**
 Method will change the ownership of a item at a given path, owner and group are strings
 */
- (void)changeOwnershipOfItem:(NSString *)aApp owner:(NSString *)aOwner group:(NSString *)aGroup
{
	NSDictionary *permDict = [NSDictionary dictionaryWithObjectsAndKeys:
							  aOwner,NSFileOwnerAccountName,
							  aGroup,NSFileGroupOwnerAccountName,nil];
	
	NSError *error = nil;
	[fm setAttributes:permDict ofItemAtPath:aApp error:&error];
	if(error)
	{
		qlerror(@"Error settings permission %@",[error description]);
		return;
	}
	
	error = nil;
	NSArray *aContents = [fm subpathsOfDirectoryAtPath:aApp error:&error];
	if(error)
	{
		qlerror(@"Error subpaths of Directory %@.\n%@",aApp,[error description]);
		return;
	}
	if (!aContents)
	{
		qlerror(@"No contents found for %@",aApp);
		return;
	}
	
	for (NSString *i in aContents)
	{
		error = nil;
		[[NSFileManager defaultManager] setAttributes:permDict ofItemAtPath:[aApp stringByAppendingPathComponent:i] error:&error];
		if(error){
			qlerror(@"Error settings permission %@",[error description]);
		}
	}
}

#pragma mark - Delegate Methods

- (void)downloadProgress:(NSString *)progressStr
{
	[self postStatus:progressStr];
}

@end
