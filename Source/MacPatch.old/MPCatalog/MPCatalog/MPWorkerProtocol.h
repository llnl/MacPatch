//
//  MPWorkerProtocol.h
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

// MacPatch MPWorkerProtocol.h version 1.7.6

#import <Foundation/Foundation.h>

#define kMPWorkerPortName      @"gov.llnl.mp.worker"

// Messages the client will receive from the Helper
@protocol MPWorkerClient

@optional
- (void)statusData:(in bycopy NSString *)aData;
- (void)installData:(in bycopy NSString *)aData;

@end

// Messages the Helper will receive from the client
@protocol MPWorkerServer

- (oneway void)unregisterClient:(in byref id <MPWorkerClient>)client;
- (BOOL)registerClient:(in byref id <MPWorkerClient>)newClient;


// Software Dist
- (int)installSoftwareViaHelper:(in bycopy NSDictionary *)aSWDict;
- (int)patchSoftwareViaHelper:(in bycopy NSDictionary *)aSWDict;
- (int)removeSoftwareViaHelper:(in bycopy NSString *)aScript;
- (oneway void)setLoggingLevel:(BOOL)aState;

// Patching
- (int)setCatalogURLViaHelper;
- (void)unSetCatalogURLViaHelper;
- (void)disableSoftwareUpdateScheduleViaHelper;

- (NSArray *)scanForAppleUpdatesViaHelper;
- (NSArray *)scanForCustomUpdatesViaHelper;

- (int)installAppleSoftwareUpdateViaHelper:(in bycopy NSString *)approvedUpdate;

- (int)installPkgToRootViaHelper:(in bycopy NSString *)pkgPath;
- (int)installPkgToRootViaHelper:(in bycopy NSString *)pkgPath env:(in bycopy NSString *)aEnvString;
- (int)installPkgViaHelper:(in bycopy NSString *)pkgPath target:(in bycopy NSString *)aTarget env:(in bycopy NSString *)aEnv;

- (int)runScriptViaHelper:(in bycopy NSString *)scriptText;
- (void)setLogoutHookViaHelper;

- (int)createDirAtPathWithIntermediateDirectoriesViaHelper:(in bycopy NSString *)path intermediateDirectories:(BOOL)withDirs;
- (int)createDirAtPathWithIntermediateDirectoriesViaHelper:(in bycopy NSString *)path intermediateDirectories:(BOOL)withDirs attributes:(NSDictionary *)attrs;
- (int)writeDataToFileViaHelper:(id)data toFile:(NSString *)aFile;
- (int)writeArrayToFileViaHelper:(NSArray *)data toFile:(NSString *)aFile;
- (int)setPermissionsForFileViaHelper:(in bycopy NSString *)aFile posixPerms:(unsigned long)posixPermissions;
- (void)setDebugLogging:(BOOL)aState;
- (void)removeStatusFilesViaHelper;

- (int)stagePatchWithBaseDirectory:(in bycopy NSDictionary *)aPatch directory:(in bycopy NSString *)path;

- (int)runCMD:(in bycopy NSString *)binPath arguments:(in bycopy NSArray *)arguments;

// Inventory Collection
- (int)collectInventoryData;

// Collect Client Checkin Data
- (NSDictionary *)clientCheckInData;
//
- (void)updateClientGroupSettingViaHelper:(in bycopy NSDictionary *)settingsRevs;

// Misc
- (NSString *)createAppSupportDirectoryForDomain:(NSSearchPathDomainMask)aDomainMask directoryAttributes:(in bycopy NSDictionary *)attributes;

- (BOOL)unzipFile:(in bycopy NSString *)file error:(NSError **)error;
- (BOOL)removeStagedDirectory:(in bycopy NSString *)stagedDirectory;
- (BOOL)removeFilesUsingExtensionsFromDirectory:(in bycopy NSString *)stagedDirectory types:(in bycopy NSArray *)types;

// MPReboot
- (int)cleanUpRebootFileViaHelper;

// Diag Data
- (int)collectAgentDiagnosticsDataViaHelper;



@end
