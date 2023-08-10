//
//  MPStatusProtocol.h
//  gov.llnl.mp.status.ui
/*
Copyright (c) 2023, Lawrence Livermore National Security, LLC.
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

// Rev 1

#import <Foundation/Foundation.h>

enum {
    kMPInstallStatus = 0,
    kMPProcessStatus = 1,
    kMPProcessProgress = 2,
    kMPPatchProcessStatus = 3,
    kMPPatchProcessProgress = 4,
    kMPPatchAllProcessProgress = 5,
    kMPPatchAllProcessStatus = 6,
    kMPPatchAllInstallComplete = 7,
    kMPPatchAllInstallError = 8
};
typedef NSUInteger MPPostDataType;

enum {
    kMPCopyFile = 0,
    kMPMoveFile = 1
};
typedef NSUInteger MPFileMoveAction;

enum {
    kPatchingPausedOff = 0,
    kPatchingPausedOn = 1
};
typedef NSUInteger MPPatchingPausedState;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const MPXPCErrorDomain;

NS_ASSUME_NONNULL_END

enum {
    MPGeneralError = 1000,
    MPFileHashCheckError = 1001,
    MPFileUnZipError = 1002,
    MPPreInstallScriptError = 1003,
    MPPostInstallScriptError = 1004,
    MPRemoveFileError = 1005,
    MPCopyFileError = 1006,
    MPMountDMGError = 1007,
    MPUnMountDMGError = 1008
    
};


#define kMPStatusUIMachName @"mp.status.ui.XPC"

// HelperToolProtocol is the NSXPCConnection-based protocol implemented by the helper tool
// and called by the app.

@protocol MPStatusProtocol

@required



// This command simply returns the version number of the tool.  It's a good idea to include a
// command line this so you can handle app upgrades cleanly.

// The next two commands imagine an app that needs to store a license key in some global location
// that's not writable by all users; thus, setting the license key requires elevated privileges.
// To manage this there's a 'read' command--which by default can be used by everyone--to return
// the key and a 'write' command--which requires admin authentication--to set the key.

@optional
- (void)getVersionWithReply:(nullable void(^)(NSString * _Nullable verData))reply;
- (void)getTestWithReply:(nullable void(^)(NSString * _Nullable aString))reply;

// ----------------------------------------
// Client Checkin     ---------------------
// ----------------------------------------
- (void)runCheckInWithReply:(nullable void(^)(NSError * _Nullable error, NSDictionary * _Nonnull result))reply;

// ----------------------------------------
// FileVault                     ----------
// ----------------------------------------
- (void)runAuthRestartWithReply:(nullable void(^)(NSError * _Nullable error, NSInteger result))reply;
- (void)fvAuthrestartAccountIsValid:(nullable void(^)(NSError * _Nullable error, BOOL result))reply;

// ----------------------------------------
// Provisioning                  ----------
// ----------------------------------------
- (void)createDirectory:(NSString * _Nullable )path withReply:(nullable void(^)(NSError * _Nullable error))reply;
- (void)postProvisioningData:(NSString * _Nullable )key dataForKey:(NSData * _Nullable)data dataType:(NSString * _Nullable)dataType withReply:(nullable void(^)(NSError * _Nullable error))reply;
- (void)touchFile:(NSString * _Nullable )filePath withReply:(nullable void(^)(NSError * _Nullable error))reply;
- (void)rebootHost:(nullable void(^)(NSError * _Nullable error))reply;

// ----------------------------------------
// Misc                          ----------
// ----------------------------------------
- (void)removeFile:(NSString *_Nonnull)aFile withReply:(nullable void(^)(NSInteger result))reply;

@end

@protocol MPStatusProgress

- (void)patchProgress:(nullable NSString *)progressStr;
- (void)postStatus:(nullable NSString *)status type:(MPPostDataType)type;
- (void)postPatchInstallStatus:(nullable NSString *)patchID type:(MPPostDataType)type;

@end
