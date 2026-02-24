//
//  XPCStatus.m
//  gov.llnl.mp.status.ui
//
/*
 Copyright (c) 2026, Lawrence Livermore National Security, LLC.
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

#import "XPCStatus.h"
#import "MPStatusProtocol.h"
#include <libproc.h>
#import "MPClientDB.h"
#import "MPPatching.h"
#import "AHCodesignVerifier.h"

#undef  ql_component
#define ql_component lcl_cMPStatusUI

@interface XPCStatus () <NSXPCListenerDelegate, MPStatusProtocol, MPHTTPRequestDelegate, MPPatchingDelegate>
{
    NSFileManager *fm;
}

@property (nonatomic, strong, readwrite) NSURL          *SW_DATA_DIR;

@property (atomic, assign, readwrite)   int             selfPID;
@property (atomic, strong, readwrite)   NSXPCListener   *listener;
@property (atomic, weak, readwrite)     NSXPCConnection *xpcConnection;

// PID
- (int)getPidNumber;
- (NSString *)pathForPid:(int)aPid;

@end

@implementation XPCStatus

@synthesize SW_DATA_DIR;

- (id)init
{
    self = [super init];
    if (self != nil) {
        // Set up our XPC listener to handle requests on our Mach service.
        self->_listener = [[NSXPCListener alloc] initWithMachServiceName:kMPStatusUIMachName];
        self->_listener.delegate = self;
        self->_selfPID = [self getPidNumber];
        self->SW_DATA_DIR = [self swDataDirURL];
        self->swTaskTimeoutValue = 1200; // 15min timeout to install an item
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
    BOOL valid = YES;
    if (valid)
    {
        assert(listener == self.listener);
        assert(newConnection != nil);
        
        newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(MPStatusProtocol)];
        newConnection.exportedObject = self;
        
        
        self.xpcConnection = newConnection;
        newConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(MPStatusProtocol)];
        
        [newConnection resume];
        return YES;
    }
    
    qlerror(@"Listener failed to trust new connection.");
    return NO;
}

- (BOOL)newConnectionIsTrusted:(NSXPCConnection *)newConnection
{
    BOOL success = NO;
    NSError *err = nil;
    return YES;
    /*
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
     */
}

#pragma mark - Tests

- (void)getVersionWithReply:(void(^)(NSString *verData))reply
{
    logit(lcl_vInfo,@"getVersionWithReply");
    reply(@"1");
}

- (void)getTestWithReply:(void(^)(NSString *aString))reply
{
    // We specifically don't check for authorization here.  Everyone is always allowed to get
    // the version of the helper tool.
    qlinfo(@"getTestWithReply");
    reply(@"Test Reply");
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

#pragma mark • FileVault

- (void)runAuthRestartWithReply:(void(^)(NSError *error, NSInteger result))reply
{
    NSInteger result = 1;
    NSDictionary *authData = nil;
    NSError *err = nil;
    MPSimpleKeychain *kc = [[MPSimpleKeychain alloc] initWithKeychainFile:MP_AUTHSTATUS_KEYCHAIN];
    MPPassItem *pi = [kc retrievePassItemForService:MP_AUTHSTATUS_ITEM error:&err];
    if (!err) {
        authData = [pi toDictionary];
    } else {
        qlerror(@"Error getting saved FileVault auth data.");
        reply(err,result);
    }
    
    NSString *script = [NSString stringWithFormat:@"#!/bin/bash \n"
    "/usr/bin/fdesetup authrestart -delayminutes 0 -verbose -inputplist <<EOF \n"
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?> \n"
    "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\"> \n"
    "<plist version=\"1.0\"> \n"
    "<dict> \n"
    "    <key>Username</key> \n"
    "    <string>%@</string> \n"
    "    <key>Password</key> \n"
    "    <string>%@</string> \n"
    "</dict></plist>\n"
    "EOF",authData[@"userName"],authData[@"userPass"]];
    
    NSError *fileErr = nil;
    [script writeToFile:@"/private/var/tmp/authScript" atomically:NO encoding:NSUTF8StringEncoding error:&fileErr];
    if (fileErr) {
        qlerror(@"Error writing file to /private/var/tmp/authScript : %@", fileErr);
    }
    
    MPScript *mps = [MPScript new];
    BOOL res = [mps runScript:script];
    if (!res) {
        qlerror(@"bypassFileVaultForRestart script failed to run.");
    } else {
        result = 0;
    }
    // Keep for debugging
    BOOL keepScript = NO;
    if (!keepScript)
    {
        if ([fm fileExistsAtPath:@"/private/var/tmp/authScript"]) {
            err = nil;
            [fm removeItemAtPath:@"/private/var/tmp/authScript" error:&err];
            if (err) {
                qlerror(@"Error removing authScript");
            }
        }
    }

    // Quick Sleep before the reboot
    [NSThread sleepForTimeInterval:1.0];
    reply(err,result);
}

- (void)fvAuthrestartAccountIsValid:(void(^)(NSError *error, BOOL result))reply
{
    NSError *err = nil;
    BOOL isValid = NO;
    MPFileCheck *fu = [MPFileCheck new];
    if ([fu fExists:MP_AUTHSTATUS_FILE])
    {
        NSMutableDictionary *d = [NSMutableDictionary dictionaryWithContentsOfFile:MP_AUTHSTATUS_FILE];
        if ([d[@"enabled"] boolValue])
        {
            if ([d[@"useRecovery"] boolValue])
            {
                qldebug(@"Checking if recovery key is valid.");
                MPSimpleKeychain *kc = [[MPSimpleKeychain alloc] initWithKeychainFile:MP_AUTHSTATUS_KEYCHAIN];
                MPPassItem *pi = [kc retrievePassItemForService:MP_AUTHSTATUS_ITEM error:&err];
                if (!err)
                {
                    isValid = [self recoveryKeyIsValid:pi.userPass];
                    qldebug(@"Is FV Recovery Key Valid: %@",isValid ? @"Yes":@"No");
                    
                    if (!isValid) {
                        [d setObject:[NSNumber numberWithBool:YES] forKey:@"keyOutOfSync"];
                        [d writeToFile:MP_AUTHSTATUS_FILE atomically:NO];
                    }
                } else {
                    qlerror(@"Could not retrievePassItemForService for recovery key.");
                    qlerror(@"%@",err.localizedDescription);
                }
            } else {
                qldebug(@"Checking if auth creds are valid.");
                DHCachedPasswordUtil *dh = [DHCachedPasswordUtil new];
                MPSimpleKeychain *kc = [[MPSimpleKeychain alloc] initWithKeychainFile:MP_AUTHSTATUS_KEYCHAIN];
                MPPassItem *pi = [kc retrievePassItemForService:MP_AUTHSTATUS_ITEM error:&err];
                if (!err)
                {
                    isValid = [dh checkPassword:pi.userPass forUserWithName:pi.userName];
                    qldebug(@"Is FV UserName and Password Valid: %@",isValid ? @"Yes":@"No");
                    
                    if (!isValid) {
                        [d setObject:[NSNumber numberWithBool:YES] forKey:@"outOfSync"];
                        [d writeToFile:MP_AUTHSTATUS_FILE atomically:NO];
                    }
                } else {
                    qlerror(@"Could not retrievePassItemForService");
                    qlerror(@"%@",err.localizedDescription);
                }
            }
        } else {
            qlerror(@"Authrestart is not enabled.");
        }
    }
    
    reply(err,isValid);
}

// Private
- (BOOL)recoveryKeyIsValid:(NSString *)rKey
{
    BOOL isValid = NO;

    NSString *script = [NSString stringWithFormat:@"#!/bin/bash \n"
    "/usr/bin/expect -f- << EOT \n"
    "spawn /usr/bin/fdesetup validaterecovery; \n"
    "expect \"Enter the current recovery key:*\" \n"
    "send -- %@ \n"
    "send -- \"\\r\" \n"
    "expect \"true\" \n"
    "expect eof; \n"
    "EOT",rKey];
    MPScript *mps = [MPScript new];
    NSString *res = [mps runScriptReturningResult:script];
    // Now Look for our result ...
    NSArray *arr = [res componentsSeparatedByString:@"\n"];
    for (NSString *l in arr) {
        if ([l containsString:@"fdesetup"]) {
            continue;
        }
        if ([l containsString:@"Enter the "]) {
            continue;
        }
        if ([[l trim] isEqualToString:@"false"]) {
            isValid = NO;
            break;
        }
        if ([[l trim] isEqualToString:@"true"]) {
            isValid = YES;
            break;
        }
    }

    return isValid;
}

#pragma mark - Provisioning

- (void)createDirectory:(NSString *)path withReply:(void(^)(NSError *error))reply
{
    NSError *err = nil;
    NSFileManager *dfm = [NSFileManager defaultManager];
    [dfm createDirectoryRecursivelyAtPath:path];
    if (![dfm isDirectoryAtPath:path]) {
        NSDictionary *errDetail = @{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"%@ is not a directory.",path]};
        err = [NSError errorWithDomain:@"gov.llnl.mp.status.ui" code:101 userInfo:errDetail];
    }
    reply(err);
}

- (void)postProvisioningData:(NSString *)key dataForKey:(NSData *)data dataType:(NSString *)dataType withReply:(void(^)(NSError *error))reply
{
    NSError *err = nil;
    id _data = nil;
    
    if ([[dataType lowercaseString] isEqualToString:@"string"]) {
        _data = (NSString*) [NSKeyedUnarchiver unarchiveObjectWithData:data];
    } else if ([[dataType lowercaseString] isEqualToString:@"dict"]) {
        _data = (NSDictionary*) [NSKeyedUnarchiver unarchiveObjectWithData:data];
    } else if ([[dataType lowercaseString] isEqualToString:@"array"]) {
        _data = (NSArray*) [NSKeyedUnarchiver unarchiveObjectWithData:data];
    } else if ([[dataType lowercaseString] isEqualToString:@"bool"]) {
        // Bools are wrapped in NSDict key = key
        NSDictionary *x = (NSDictionary*) [NSKeyedUnarchiver unarchiveObjectWithData:data];
        _data = x[key];
    } else {
        NSDictionary *errDetail = @{NSLocalizedDescriptionKey:@"Error writing provisioning data to file. Type not supported."};
        err = [NSError errorWithDomain:@"gov.llnl.mp.status.ui" code:101 userInfo:errDetail];
        reply(err);
    }

    MPFileCheck *fc = [MPFileCheck new];
    
    NSMutableDictionary *_pFile;
    if ([fc fExists:MP_PROVISION_FILE]) {
        _pFile = [NSMutableDictionary dictionaryWithContentsOfFile:MP_PROVISION_FILE];
    } else {
        _pFile = [NSMutableDictionary new];
    }
    
    if ([key isEqualToString:@"status"])
    {
        NSMutableArray *_status = [NSMutableArray new];
        if (_pFile[@"status"]) {
            _status = [_pFile[@"status"] mutableCopy];
        }
        [_status addObject:_data];
        [_pFile setObject:_status forKey:key];
    } else {
        [_pFile setObject:_data forKey:key];
    }
    
    if (![_pFile writeToFile:MP_PROVISION_FILE atomically:NO]) {
        NSDictionary *errDetail = @{NSLocalizedDescriptionKey:@"Error writing provisioning data to file."};
        err = [NSError errorWithDomain:@"gov.llnl.mp.status.ui" code:101 userInfo:errDetail];
    }
    
    reply(err);
}

- (void)touchFile:(NSString *)filePath withReply:(void(^)(NSError *error))reply
{
    NSError *err = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:filePath]) {
        [@"NA" writeToFile:filePath atomically:NO encoding:NSUTF8StringEncoding error:&err];
    }
    
    reply(err);
}

- (void)rebootHost:(void(^)(NSError *error))reply
{
    NSError *err = nil;
    qlinfo(@"Provisioning issued a cli reboot.");
    [NSTask launchedTaskWithLaunchPath:@"/sbin/reboot" arguments:@[]];
    reply(err);
}

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

/*
#pragma mark • Software
- (void)installSoftware:(NSDictionary *)swItem withReply:(void(^)(NSError *error, NSInteger resultCode, NSData *installData))reply
{
    //__block NSError *err;
    //__block NSInteger res;
    //__block NSData *resData;
    // Default timeout is 30min
    [self installSoftware:swItem timeOut:1800 withReply:^(NSError *error, NSInteger resultCode, NSData *installData) {
        //err = error;
        //res = resultCode;
        //resData = installData;
        reply(error, resultCode, installData);
    }];
}

- (void)installSoftware:(NSDictionary *)swItem timeOut:(NSInteger)timeout withReply:(void(^)(NSError *error, NSInteger resultCode, NSData *installData))reply
{
    qlinfo(@"Start install of %@",swItem[@"name"]);
    qldebug(@"swItem: %@",swItem);
    
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
    // Download Software
    // -----------------------------------------
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
        [self postStatus:@"Installing %@",dlSoftwareFile.lastPathComponent];
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
        [self postStatus:@"Checking file hash..."];
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
        [self postStatus:@"Checking file hash..."];
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
        qlerror(@"Install Type Not Supported for %@",swItem[@"name"]);
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
    
    NSDictionary *wsRes = @{@"tuuid":swItem[@"id"],
                            @"suuid":[swItem valueForKeyPath:@"Software.sid"],
                            @"action":@"i",
                            @"result":[NSString stringWithFormat:@"%d",(int)result],
                            @"resultString":@""};
    MPRESTfull *mpr = [MPRESTfull new];
    err = nil;
    [mpr postSoftwareInstallResults:wsRes error:&err];
    if (err) {
        qlerror(@"Error posting software install results.");
        qlerror(@"%@",err.localizedDescription);
    }
    
    reply(err,result,installResultData);
}

- (BOOL)downloadSoftware:(NSDictionary *)swTask toDestination:(NSString *)toPath
{
    qlinfo(@"downloadSoftware for task %@",swTask[@"name"]);
    NSString *_url;
    NSInteger useS3 = [[swTask valueForKeyPath:@"Software.sw_useS3"] integerValue];
    if (useS3 == 1) {
        MPRESTfull *mpr = [MPRESTfull new];
        NSDictionary *res = [mpr getS3URLForType:@"sw" id:swTask[@"id"]];
        if (res) {
            _url = res[@"url"];
        } else {
            qlerror(@"Result from getting the S3 url was nil. No download can occure.");
            return FALSE;
        }
    } else {
        _url = [NSString stringWithFormat:@"/mp-content%@",[swTask valueForKeyPath:@"Software.sw_url"]];
    }
    
    NSError *dlErr = nil;
    MPHTTPRequest *req = [[MPHTTPRequest alloc] init];
    req.delegate = self;
    NSString *dlPath = [req runSyncFileDownload:_url downloadDirectory:toPath error:&dlErr];
    qldebug(@"Downloaded software to %@",dlPath);
    return YES;
}
*/
/**
 Method will run a script using MPScript.
 
 aScript (NSString) is a Base64 encoded string.
 
 aScriptType (int) is for the logging it's
     values: 0 = pre and 1 = post
 */
/*
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

/**
 Copy application from a directory to the Applications directory
 
 action is MPFileMoveAction kMPFileCopy or kMPFileMove
 
 Method also calls changeOwnershipOfItem
 */
/*
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
            qldebug(@"Found, %@. Now remove it.",[@"/Applications" stringByAppendingPathComponent:app]);
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
*/
/**
 Method will change the ownership of a item at a given path, owner and group are strings
 */
/*
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

// Helpers
- (int)runTask:(NSString *)aBinPath binArgs:(NSArray *)aBinArgs environment:(NSString *)env
{
    MPNSTask *task = [MPNSTask new];
    task.taskTimeoutValue = swTaskTimeoutValue;
    int taskResult = -1;
    
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
    
    logit(lcl_vDebug,@"[task][environment]: %@",environment);
    logit(lcl_vDebug,@"[task][setLaunchPath]: %@",aBinPath);
    logit(lcl_vDebug,@"[task][setArguments]: %@",aBinArgs);
    qlinfo(@"[task][setTimeout]: %d",swTaskTimeoutValue);
    
    NSString *result;
    NSError *error = nil;
    result = [task runTaskWithBinPath:aBinPath args:aBinArgs environment:environment error:&error];
    if (error) {
        qlerror(@"%@",error.localizedDescription);
    } else {
        taskResult = task.taskTerminationStatus;
    }

    return taskResult;
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

*/
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

#pragma mark • Misc

- (void)removeFile:(NSString *)aFile withReply:(void(^)(NSInteger result))reply
{
    int res = 0;
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL result = [fm removeFileIfExistsAtPath:aFile];
    if (!result) res = 1;
    reply(res);
}

#pragma mark - Private

- (NSURL *)swDataDirURL
{
    NSURL *appSupportDir = [[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSSystemDomainMask] objectAtIndex:0];
    NSURL *appSupportMPDir = [appSupportDir URLByAppendingPathComponent:@"MacPatch/SW_Data"];
    [self configDataDir];
    return appSupportMPDir;
}
@end
