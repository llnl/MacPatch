//
//  MPClientDatabase.h
//  MPLibrary
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


#import <Foundation/Foundation.h>

@interface MPClientDatabase : NSObject

- (void)setupDatabase;

#pragma mark - Software
// Software

/**
 Record the install of a software task.

 @param swTask - Software Task Dictionary
 @return BOOL
 */
- (BOOL)recordSoftwareInstall:(NSDictionary *)swTask;

/**
 Record the uninstall of a software task.

 @param swTaskName - SW Task Name
 @param swTaskID - SW Task ID
 @return BOOL
 */
- (BOOL)recordSoftwareUninstall:(NSString *)swTaskName taskID:(NSString *)swTaskID;


/**
 Return an array of all software tasks installed

 @return NSArray
 */
- (NSArray *)retrieveInstalledSoftwareTasks;

/**
 Method answers if a software task is installed.
 
 @param tuuid - Software task id
 @return BOOL
 */
- (BOOL)isSoftwareTaskInstalled:(NSString *)swTaskID;

#pragma mark - Patches
// Patch

/**
 Record the insatll of a patch

 @param patch - NSDictionary
 @return BOOL
 */
- (BOOL)recordPatchInstall:(NSDictionary *)patch;


/**
 Add required patch to database

 @param patch - NSDictionary
 @return BOOL
 */
- (BOOL)addRequiredPatch:(NSDictionary *)patch;


/**
 After patch has been installed the record is removed from database table of required patches.

 @param type - NSString
 @param patchID - NSString
 @param patch - NSString
 @return BOOL
 */
- (BOOL)removeRequiredPatch:(NSString *)type patchID:(NSString *)patchID patch:(NSString *)patch;


/**
 Returns an array of required patches

 @return NSArray
 */
- (NSArray *)retrieveRequiredPatches;

/**
 Clear all required patches from database table. This is
 done prior to adding new found patches after a scan.
 
 @return BOOL
 */
- (BOOL)clearRequiredPatches;

#pragma mark - History
// History

/**
 Record a action in the history table. This is done for software installs and
 uninstalls. It's also done for patch installs.

 @param hstType - History Type
 @param aName - Name
 @param aUUID - Type ID PUUID or TUUID
 @param aAction - Action type (install or remove)
 @param code - Action return code
 @param aErrMsg - If, error message
 @return BOOL
 */
- (BOOL)recordHistory:(DBHistoryType)hstType name:(NSString *)aName uuid:(NSString *)aUUID
			   action:(DBHistoryAction)aAction result:(NSInteger)code errorMsg:(NSString *)aErrMsg;
@end

