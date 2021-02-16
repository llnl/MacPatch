//
//  Constants.m
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

#import "Constants.h"

NSString * const MP_ROOT                    = @"/Library/MacPatch";
NSString * const MP_ROOT_CLIENT				= @"/Library/MacPatch/Client";
NSString * const MP_ROOT_SERVER				= @"/Library/MacPatch/Server";
NSString * const MP_ROOT_UPDATE             = @"/Library/MacPatch/Updater";

NSString * const AGENT                      = @"/Library/MacPatch/Client/MPAgent";
NSString * const AGENT_WORKER               = @"/Library/MacPatch/Client/MPWorker";
NSString * const AGENT_VER_PLIST			= @"/Library/MacPatch/Client/.mpVersion.plist";
NSString * const AGENT_PREFS_PLIST			= @"/Library/Preferences/gov.llnl.mpagent.plist";
NSString * const AGENT_FRAMEWORK_PATH		= @"/Library/Frameworks/MPFramework.framework/Resources/Info.plist";
NSString * const AGENT_SERVERS_PLIST        = @"/Library/MacPatch/Client/lib/Servers.plist";
NSString * const AGENT_SUS_SERVERS_PLIST    = @"/Library/MacPatch/Client/lib/SUServers.plist";
NSString * const AGENT_REG_FILE				= @"/private/var/db/.mp.arc";
NSString * const APP_PREFS_PLIST			= @"/Library/Preferences/gov.llnl.MPClientStatus.plist";
NSString * const PATCHES_NEEDED_PLIST       = @"/Library/MacPatch/Client/Data/.neededPatches.plist";
NSString * const PATCHES_APPROVED_PLIST     = @"/Library/MacPatch/Client/Data/.approvedPatches.plist";
NSString * const PATCHES_CRITICAL_PLIST     = @"/Library/MacPatch/Client/Data/.criticalPatches.plist";
NSString * const SW_RESTRICTIONS_PLIST      = @"/Library/MacPatch/Client/Data/.softwareRestrictions.plist";
NSString * const PATCH_GROUP_PATCHES_PLIST  = @"/Library/MacPatch/Client/Data/.gov.llnl.mp.patchgroup.data.plist";
NSString * const SOFTWARE_DATA_DIR          = @"/Library/Application Support/MacPatch/SW_Data";

NSString * const WS_CLIENT_REG              = @"/MPRegister.cfc";
NSString * const WS_CLIENT_FILE             = @"/Service/MPClientService.cfc";
NSString * const WS_SERVER_FILE             = @"/Service/MPServerService.cfc";
NSString * const WS_FAILED_REQ_PLIST        = @"/Library/MacPatch/Client/lib/WebRequests.plist";

NSString * const ASUS_BIN_PATH				= @"/usr/sbin/softwareupdate";
NSString * const ASUS_APP_PATH				= @"/System/Library/CoreServices/Software Update.app";
NSString * const ASUS_PLIST_PATH			= @"/Library/Preferences/com.apple.SoftwareUpdate.plist";

NSString * const CLIENT_PATCH_STATUS_FILE	= @"~/Library/Application Support/.mpUpdateCStatus";
NSString * const SELF_PATCH_PATH			= @"/Library/MacPatch/Client/Self Patch.app";
NSString * const MPREBOOT_APP_PATH			= @"/Library/MacPatch/Client/MPReboot.app";
NSString * const MPLOGOUT_APP_PATH			= @"/Library/MacPatch/Client/MPLogout.app";
NSString * const MPLOGOUT_BIN_PATH			= @"/Library/MacPatch/Client/MPLogout.app/Contents/MacOS/MPLogout";
NSString * const MPLOGOUT_HOOK_PLIST		= @"/var/root/Library/Preferences/com.apple.loginwindow.plist";

NSString * const SWDIST_APP_PATH            = @"/Library/MacPatch/Client/MPCatalog.app";
NSString * const MP_SWDIST_WORK_DIR			= @"/private/tmp/.mp/Data";

NSString * const SYSPROFILE_BIN_PATH		= @"/usr/sbin/system_profiler";
NSString * const INSTALLER_BIN_PATH			= @"/usr/sbin/installer";

NSString * const kMPPatchSCAN               = @".mpScanRunning";
NSString * const kMPPatchUPDATE             = @".mpUpdateRunning";
NSString * const kMPInventory               = @".mpInventoryRunning";
NSString * const kMPAVUpdate                = @".mpAVUpdateRunning";

NSString * const kScanRunningFile			= @".mpScanRunning";
NSString * const kPatchRunningFile			= @".mpUpdateRunning";
NSString * const kInventoryRunningFile		= @".mpInventoryRunning";
NSString * const kAVUpdateRunningFile		= @".mpAVUpdateRunning";

NSString * const MP_KEYCHAIN_FILE           = @"/Library/Application Support/MacPatch/.MacPatch.keychain";
NSString * const MP_AGENT_HASH              = @"/Library/Application Support/MacPatch/.keyHash";

NSString * const OS_MIGRATION_STATUS        = @"/Users/Shared/.migrationid";

NSString * const MP_AGENT_DEPL_PLIST        = @"/Library/Application Support/MacPatch/gov.llnl.mpagent.plist";
NSString * const MP_AGENT_SETTINGS          = @"/Library/Application Support/MacPatch/gov.llnl.mp.plist";
NSString * const MP_AGENT_DB 				= @"/private/var/db/.MacPatch.db";

NSString * const MP_AUTHRUN_FILE 			= @"/private/tmp/.MPAuthRun";
NSString * const MP_PATCH_ON_LOGOUT_FILE 	= @"/private/tmp/.MPAuthRun";
NSString * const MP_AUTHSTATUS_KEYCHAIN 	= @"/Library/Application Support/MacPatch/.MPAuthStatus.keychain";
NSString * const MP_AUTHSTATUS_FILE 		= @"/Library/Application Support/MacPatch/.MPAuthStatus.plist";

NSString * const MP_PROVISION_DIR          = @"/Library/Application Support/MacPatch/Provision";
NSString * const MP_PROVISION_FILE         = @"/Library/Application Support/MacPatch/Provision/MPProvision.plist"; // New - Provisioning Status and details
NSString * const MP_PROVISION_DATA_FILE    = @"/Library/MacPatch/Client/Data/provision.json"; // New - Provisioning Status and details


// In a source file
// initialize arrays with explicit indices to make sure
// the string match the enums properly
NSString * const MPPatchContentType_toString[] = {
	[kApplePatches] = @"Apple",
	[kCustomPatches ] = @"Custom",
	[kAllPatches] = @"All",
	[kCriticalPatches] = @"Critical",
	[kAllActivePatches] = @"AllActive" // All Patches ignore patch group, only for GUI
};

@implementation Constants

@end
