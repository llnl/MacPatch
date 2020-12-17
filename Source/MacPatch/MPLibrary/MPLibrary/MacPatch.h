//
//  MacPatch.h
/*
 Copyright (c) 2017, Lawrence Livermore National Security, LLC.
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

#import <Cocoa/Cocoa.h>
#import "Constants.h"
// Logging
#import "lcl.h"
#import "MPLog.h"

// Settings
#import "MPSettings.h"

// Uitlities & Networking
#import "MPNetworkUtils.h"
#import "MPDiskUtil.h"
#import "MPSystemInfo.h"
#import "MPDate.h"
#import "MPNSTask.h"
#import "MPClientInfo.h"
#import "MPDownloadManager.h"
#import "DHCachedPasswordUtil.h"

// NEW
#import "MPFileUtils.h"
#import "MPSoftware.h"
#import "MPPatching.h"
#import "MPClientDB.h"
#import "MPFileVaultInfo.h"

// Networking Add for MP 3.1.0
#import "MPHTTPRequest.h"
#import "MPWSResult.h"
#import "STHTTPRequest.h"
#import "MPRESTfull.h"

// Patching & Scanning
#import "MPAsus.h"
#import "MPASUSCatalogs.h"

#import "MPPatchScan.h"
#import "MPBundle.h"
#import "MPFileCheck.h"
#import "MPOSCheck.h"
#import "MPScript.h"

#import "MPInstaller.h"
#import "MPApplePatch.h"
#import "MPCustomPatch.h"

// OS Config Profiles
#import "MPConfigProfiles.h"

// Software Distribution
#import "MPSWTasks.h"

// WebServices
#import "MPDataMgr.h"
//#import "MPWebServices.h"
#import "MPFailedRequests.h"

// New WS Class
#import "MPRESTfull.h"

// Crypto
#import "MPCrypto.h"
#import "MPCodeSign.h"
#import "MPKeychain.h"
#import "MPKeyItem.h"
#import "MPPassItem.h"
#import "MPSimpleKeychain.h"
#import "MPRemoteFingerprint.h"

// SQLite
#import "FMDB.h"
#import "FMDBx.h"

// Helpers - Extensions
#import "NSString+Helper.h"
#import "NSString+Hash.h"
#import "NSFileManager+Helper.h"
#import "NSFileManager+DirectoryLocations.h"
#import "NSDictionary+Helper.h"
#import "NSMutableDictionary+Helper.h"
#import "NSDate+Helper.h"
#import "NSDate+MPHelper.h"
#import "NSData+Base64.h"
#import "NSString+Base64.h"
#import "NSFileHandle-Helper.h"

// -- Models
// Settings
#import "Agent.h"
#import "Server.h"
#import "Suserver.h"
#import "Task.h"

// Client DB Models
#import "History.h"
#import "InstalledSoftware.h"
#import "RequiredPatch.h"

// OS Config Profile
#import "ConfigProfile.h"

#import "AgentData.h"

// Inventory Plugin
//#import "InventoryPlugin.h"
#import "MPGCDTask.h"
