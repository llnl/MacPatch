//
//  MPRESTfull.h
//  MPLibrary
//
//  Created by Charles Heizer on 10/19/17.
//
//

#import <Foundation/Foundation.h>

@interface MPRESTfull : NSObject

- (id)initNoSettings;
- (id)initWithClientID:(NSString *)clientID;


/**
 Generic Get Data for MacPatch Web Services

 @param urlPath URL Path for web service
 @param error NSError, not used yet
 @return NSDictionary containing result, result is usually the data key
 */
- (NSDictionary *)getDataFromWS:(NSString *)urlPath error:(NSError **)error;

/**
 Generic Post Data to MacPatch Web Services

 @param urlPath URL Path for web service
 @param data data as NSDictionary
 @param err NSError, not used yet
 @return BOOL
 */
- (BOOL)postDataToWS:(NSString *)urlPath data:(NSDictionary *)data error:(NSError **)error;



/**
 Post Client check in data

 @param data Client check in data as NSDictionary
 @param error Error object
 @return Dictionary containing settings revisions
 */
- (NSDictionary *)postClientCheckinData:(NSDictionary *)data error:(NSError **)error;

/**
 Get the last checkin times for the agent
 Return  values are to different date objects
 
 @param err Error object
 @return dictonary {mdate1 & mdate2}
 */
- (NSDictionary *)getLastCheckinData:(NSError **)err;

/**
 Post Patch Scan data to web service
 
 @param scanData patches found array
 @param type 1 = Apple, 2 = Third
 @param err NSError, not used yet
 @return BOOL
 */
- (BOOL)postClientScanDataWithType:(NSArray *)scanData type:(NSInteger)type error:(NSError **)err;

/**
 Get Agent Patch Scan List, severity is used for filtering critical patches
 
 @param aSeverity Patch severity level used for filtering, use Nil for all
 @param err Error object
 @return array of patches, nil if error
 */
- (NSArray *)getCustomPatchScanListWithSeverity:(NSString *)aSeverity error:(NSError **)err;

/**
 Get a dictionary containing the approved apple and custom patches for a patch group
 assigned to the client agent.
 
 @param err Error object
 @return a dictioanary containg two arrays "AppleUpdates, CustomUpdates"
 */
- (NSDictionary *)getApprovedPatchesForClient:(NSError **)err;

/**
 Post patch install using patch and type

 @param patch patch id or name depending on type
 @param type Apple, Third
 @param err Error object
 @return BOOL
 */
- (BOOL)postPatchInstallResults:(NSString *)patch type:(NSString *)type error:(NSError **)err;

/**
 Post OS Migration Status
 
 @param action start / stop
 @param label
 @param migrationID migration id
 @param err Error object
 @return BOOL
 */
- (BOOL)postOSMigrationStatus:(NSString *)action label:(NSString *)label migrationID:(NSString *)migrationID error:(NSError **)err;

/**
 Post Agent Registration Data using registration key

 @param regData A dictionary containing the registration data
 @param key registration key given from console
 @param err Error object
 @return BOOL
 */
- (BOOL)postAgentRegistration:(NSDictionary *)regData regKey:(NSString *)key error:(NSError **)err;

/**
 Get agent registration status from web service

 @param key Client reg key hash
 @param err Error object
 @return BOOL on if registered
 */
- (BOOL)getAgentRegistrationStatusUsingKey:(NSString *)key error:(NSError **)err;

/**
 Post software install data
 
 @param data software install data
 @param err Error object
 @return BOOL
 */
- (BOOL)postSoftwareInstallResults:(NSDictionary *)data error:(NSError **)err;

/**
 Get software tasks for a catalog group
 
 @param aGroupName catalog group name String
 @param err Error object
 @return NSArray
 */
- (NSArray *)getSoftwareTasksForGroup:(NSString *)groupName error:(NSError **)err;

/**
 Get software task data using software task id (tuuid)
 
 @param taskID Software task id
 @param err Error object
 @return NSDictionary
 */
- (NSDictionary *)getSoftwareTaskUsingTaskID:(NSString *)taskID error:(NSError **)err;

/**
 Get Hash to run plugin
 
 @param plugin plugin name
 @param bundleID plugin bundleid
 @param version plugin version
 @param err Error object
 @return NSString
 */
- (NSString *)getHashForPluginName:(NSString *)plugin pluginBunleID:(NSString *)bundleID pluginVersion:(NSString *)version error:(NSError **)err;

/**
 Get agent inventory state, checks wether agent has posted inventory or not.
 
 @param err Error Object
 @return BOOL
 */
- (BOOL)getAgentHasInventoryDataInDB:(NSError **)err;

/**
 Post that the agent has inventory data populated
 
 @param err Error Object
 @return BOOL
 */
- (BOOL)postAgentHasInventoryData:(NSError **)err;

/**
 Get an array of software catalogs to display
 
 @return NSArray
 */
- (NSArray *)getSoftwareCatalogs:(NSError **)err;

/**
 Get patch dictionary for a bundle id, this method is used for patching
 client group required software
 
 @param bundleID plugin bundleid
 @param err Error object
 */
- (NSDictionary *)getPatchForBundleID:(NSString *)bundleID error:(NSError **)err;


/**
 Get software restrictions for the client

 @param err Error object
 @return Dictionary of the revision and rules
 */
- (NSDictionary *)getSoftwareRestrictions:(NSError **)err;

/**
 Post agent install
 
 @param agentVer agent version installed
 @param err Error object
 @return BOOL
 */
- (BOOL)postAgentInstall:(NSString *)agentVer error:(NSError **)err;
@end
