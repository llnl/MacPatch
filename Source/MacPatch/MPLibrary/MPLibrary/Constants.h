//
//  Constants.h
/*
 Copyright (c) 2021, Lawrence Livermore National Security, LLC.
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

extern NSString * const MP_ROOT;
extern NSString * const MP_ROOT_CLIENT;
extern NSString * const MP_ROOT_SERVER;
extern NSString * const MP_ROOT_UPDATE;

extern NSString * const AGENT;
extern NSString * const AGENT_EXEC;
extern NSString * const AGENT_WORKER;
extern NSString * const AGENT_VER_PLIST;
extern NSString * const AGENT_PREFS_PLIST;
extern NSString * const AGENT_FRAMEWORK_PATH;
extern NSString * const AGENT_SERVERS_PLIST;
extern NSString * const AGENT_SUS_SERVERS_PLIST;
extern NSString * const AGENT_REG_FILE;
extern NSString * const APP_PREFS_PLIST;
extern NSString * const PATCHES_NEEDED_PLIST;
extern NSString * const PATCHES_APPROVED_PLIST;
extern NSString * const PATCHES_CRITICAL_PLIST;
extern NSString * const SW_RESTRICTIONS_PLIST;
extern NSString * const PATCH_GROUP_PATCHES_PLIST;
extern NSString * const SOFTWARE_DATA_DIR;

extern NSString * const WS_CLIENT_REG;
extern NSString * const WS_CLIENT_FILE;
extern NSString * const WS_SERVER_FILE;
extern NSString * const WS_FAILED_REQ_PLIST;

extern NSString * const ASUS_BIN_PATH;
extern NSString * const ASUS_APP_PATH;
extern NSString * const ASUS_PLIST_PATH;
extern NSString * const ASUS_PREF_PANE;

extern NSString * const CLIENT_PATCH_STATUS_FILE;
extern NSString * const SELF_PATCH_PATH;
extern NSString * const MPREBOOT_APP_PATH;
extern NSString * const MPLOGOUT_APP_PATH;
extern NSString * const MPLOGOUT_BIN_PATH;
extern NSString * const MPLOGOUT_HOOK_PLIST;

extern NSString * const SWDIST_APP_PATH;
extern NSString * const MP_SWDIST_WORK_DIR;

extern NSString * const SYSPROFILE_BIN_PATH;
extern NSString * const INSTALLER_BIN_PATH;

extern NSString * const kMPPatchSCAN __deprecated_msg("Use kScanRunningFile instead");
extern NSString * const kMPPatchUPDATE __deprecated_msg("Use kPatchRunningFile instead");
extern NSString * const kMPInventory __deprecated_msg("Use kInventoryRunningFile instead");
extern NSString * const kMPAVUpdate __deprecated_msg("Use kAVUpdateRunningFile instead");

extern NSString * const kScanRunningFile;
extern NSString * const kPatchRunningFile;
extern NSString * const kInventoryRunningFile;
extern NSString * const kAVUpdateRunningFile;

extern NSString * const MP_KEYCHAIN_FILE;
extern NSString * const MP_AGENT_HASH;
extern NSString * const OS_MIGRATION_STATUS;

extern NSString * const MP_AGENT_DEPL_PLIST;
extern NSString * const MP_AGENT_SETTINGS;
extern NSString * const MP_AGENT_DB;

extern NSString * const MP_AUTHRUN_FILE;
extern NSString * const MP_PATCH_ON_LOGOUT_FILE;
extern NSString * const MP_AUTHSTATUS_KEYCHAIN;
extern NSString * const MP_AUTHSTATUS_FILE;

extern NSString * const MP_PROVISION_DIR;
extern NSString * const MP_PROVISION_FILE;
extern NSString * const MP_PROVISION_DATA_FILE;
extern NSString * const MP_PROVISION_BEGIN;
extern NSString * const MP_PROVISION_DONE;

#pragma mark - ENUMS

typedef enum {
	kApplePatches = 1,
	kCustomPatches,
	kAllPatches,
	kCriticalPatches,
	kAllActivePatches
} MPPatchContentType;

extern NSString * const MPPatchContentType_toString[];

// Client Database
enum
{
	kMPSoftwareType = 0,
	kMPPatchType = 1
};
typedef NSUInteger DBHistoryType;

enum
{
	kMPInstallAction = 0,
	kMPUnInstallAction = 1
};
typedef NSUInteger DBHistoryAction;

@interface Constants : NSObject {

}

@end
