//
//  XPCStatus.m
//  gov.llnl.mp.status.ui
//
/*
 Copyright (c) 2024, Lawrence Livermore National Security, LLC.
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
    logit(lcl_vInfo,@"getTestWithReply");
    
    MPConfigProfiles *p = [[MPConfigProfiles alloc] init];
    NSArray *cp = [p readProfileStoreReturnAsConfigProfile];
    NSString *str = [NSString stringWithFormat:@"Profiles Found %lu",(unsigned long)cp.count];
    
    qldebug(@"getTestWithReply");
    reply(str);
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
    MPPassItem *pi = [kc retrievePassItemForService:@"mpauthrestart" error:&err];
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
    
    [script writeToFile:@"/private/var/tmp/authScript" atomically:NO encoding:NSUTF8StringEncoding error:NULL];
    
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
                MPSimpleKeychain *kc = [[MPSimpleKeychain alloc] initWithKeychainFile:MP_AUTHSTATUS_KEYCHAIN];
                MPPassItem *pi = [kc retrievePassItemForService:@"mpauthrestart" error:&err];
                if (!err)
                {
                    isValid = [self recoveryKeyIsValid:pi.userPass];
                    qldebug(@"Is FV Recovery Key Valid: %@",isValid ? @"Yes":@"No");
                    
                    if (!isValid) {
                        [d setObject:[NSNumber numberWithBool:YES] forKey:@"keyOutOfSync"];
                        [d writeToFile:MP_AUTHSTATUS_FILE atomically:NO];
                    }
                } else {
                    qlerror(@"Could not retrievePassItemForService");
                    qlerror(@"%@",err.localizedDescription);
                }
            } else {
                DHCachedPasswordUtil *dh = [DHCachedPasswordUtil new];
                MPSimpleKeychain *kc = [[MPSimpleKeychain alloc] initWithKeychainFile:MP_AUTHSTATUS_KEYCHAIN];
                MPPassItem *pi = [kc retrievePassItemForService:@"mpauthrestart" error:&err];
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
    //qlinfo(@"CEHD [postProvisioningData]: key:%@ dataType:%@",key,dataType);
    
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
        // _pFile[key] = _status;
    } else {
        [_pFile setObject:_data forKey:key];
        // _pFile[key] = _data;
    }
    
    if (![_pFile writeToFile:MP_PROVISION_FILE atomically:NO]) {
        NSDictionary *errDetail = @{NSLocalizedDescriptionKey:@"Error writing provisioning data to file."};
        err = [NSError errorWithDomain:@"gov.llnl.mp.status.ui" code:101 userInfo:errDetail];
    }
    
    //qlinfo(@"CEHD: Verify postProvisioningData");
    //qlinfo(@"CEHD: Data: %@",[NSDictionary dictionaryWithContentsOfFile:MP_PROVISION_FILE]);
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
