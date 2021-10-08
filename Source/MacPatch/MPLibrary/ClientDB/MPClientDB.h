//
//  MPDB.h
//  FMDBme
//
//  Created by Charles Heizer on 10/23/19.
//  Copyright © 2019 Charles Heizer. All rights reserved.
//

#import <Foundation/Foundation.h>

@class InstalledSoftware;

/*
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
*/

NS_ASSUME_NONNULL_BEGIN

@interface MPClientDB : NSObject

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
 Return an array of all software task ids installed

 @return NSArray
 */
- (NSArray *)retrieveInstalledSoftwareTasks;

/**
 Return an array of dictionaries of all software tasks installed

 @return NSArray
 */
- (NSArray *)retrieveInstalledSoftwareTasksDict;

/**
 Method answers if a software task is installed.
 
 @param swTaskID - Software task id
 @return BOOL
 */
- (BOOL)isSoftwareTaskInstalled:(NSString *)swTaskID;

/**
 Get a software yask using a Sw TaskID
 
 @param swTaskID - Software task id
 @return IntsalledSoftware object or nil
 */
- (InstalledSoftware *)getSoftwareTaskUsingID:(NSString *)swTaskID;

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
			   action:(DBHistoryAction)aAction result:(NSInteger)code errorMsg:(nullable NSString *)aErrMsg;

/**
 Return an array of all history tasks

 @return NSArray
 */
- (NSArray *)retrieveHistory;

@end



NS_ASSUME_NONNULL_END
