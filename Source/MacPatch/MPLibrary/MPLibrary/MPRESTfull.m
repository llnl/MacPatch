//
//  MPRESTfull.m
//  MPLibrary
//
//  Created by Charles Heizer on 10/19/17.
//
//

#import "MPRESTfull.h"
#import "MPHTTPRequest.h"
#import "MPWSResult.h"
#import "MPSettings.h"

@interface MPRESTfull ()
{
    MPSettings *settings;
}

@property (nonatomic, strong) NSString *clientID;

@end

@implementation MPRESTfull

@synthesize clientID;

- (id)init
{
    self = [super init];
    if (self)
    {
        qldebug(@"MPRESTfull init");
        settings = [MPSettings sharedInstance];
        self.clientID = settings.ccuid;
    }
    
    return self;
}

- (id)initNoSettings
{
    qlinfo(@"MPRESTfull initNoSettings");
    self = [super init];
    return self;
}

- (id)initWithClientID:(NSString *)clientID
{
    qlinfo(@"MPRESTfull initWithClientID %@",clientID);
    self = [super init];
    if (self)
    {
        self.clientID = clientID;
    }
    
    return self;
}

/**
 Generic Get Data for MacPatch Web Services
 
 @param urlPath URL Path for web service
 @param error NSError, not used yet
 @return NSDictionary containing result, result is usually the data key
 */
- (NSDictionary *)getDataFromWS:(NSString *)urlPath error:(NSError **)error
{
    NSDictionary *result = nil;
    MPHTTPRequest *req;
    MPWSResult *wsresult;
    
    req = [[MPHTTPRequest alloc] init];
    wsresult = [req runSyncGET:urlPath];
	qldebug(@"[getDataFromWS][result]:%ld",(long)wsresult.statusCode);
    if (wsresult.statusCode >= 200 && wsresult.statusCode <= 299) {
        logit(lcl_vDebug,@"Get Data from web service (%@) returned true.",urlPath);
        logit(lcl_vDebug,@"Data Result: %@",wsresult.result);
        result = wsresult.result;
    } else {
        logit(lcl_vError,@"Get Data from web service (%@), returned false.", urlPath);
        logit(lcl_vDebug,@"%@",wsresult.toDictionary);
        
        *error = [NSError errorWithDomain:@"gov.llnl.mp.rest"
                                     code:wsresult.statusCode
                                 userInfo:@{NSLocalizedDescriptionKey: @"Failed to get data from web service"}];
    }
    
    return result;
}

/**
 Generic Post Data to MacPatch Web Services
 
 @param urlPath URL Path for web service
 @param data data as NSDictionary
 @param err NSError, not used yet
 @return BOOL
 */
- (BOOL)postDataToWS:(NSString *)urlPath data:(NSDictionary *)data error:(NSError **)error
{
    MPHTTPRequest *req;
    MPWSResult *result;
    
    req = [[MPHTTPRequest alloc] init];
    result = [req runSyncPOST:urlPath body:data];
    
    if (result.statusCode >= 200 && result.statusCode <= 299) {
        logit(lcl_vDebug,@"Data post to web service (%@), returned true.", urlPath);
        logit(lcl_vDebug,@"Data Result: %@",result.result);
    } else {
        logit(lcl_vError,@"Data post to web service (%@), returned false.", urlPath);
        logit(lcl_vDebug,@"%@",result.toDictionary);
        
        *error = [NSError errorWithDomain:@"gov.llnl.mp.rest"
                                     code:result.statusCode
                                 userInfo:@{NSLocalizedDescriptionKey: @"Failed to post data to web service"}];
        return NO;
    }
    
    return YES;
}


/**
 Post Client check in data
 
 @param data Client check in data as NSDictionary
 @param error Error object
 @return Dictionary containing settings revisions
 */
- (NSDictionary *)postClientCheckinData:(NSDictionary *)data error:(NSError **)error
{
    MPWSResult *ws_result;
    
    MPHTTPRequest *req = [[MPHTTPRequest alloc] init];
    NSString *urlPath = [@"/api/v3/client/checkin" stringByAppendingPathComponent:self.clientID];
    ws_result = [req runSyncPOST:urlPath body:data];
    
    if (ws_result.statusCode >= 200 && ws_result.statusCode <= 299) {
        logit(lcl_vInfo,@"Running client base checkin, returned true.");
        return ws_result.result;
    } else {
        logit(lcl_vError,@"Running client base checkin, returned false.");
        logit(lcl_vDebug,@"%@",ws_result.toDictionary);
    }
    
    logit(lcl_vInfo,@"Running client check in completed.");
    return nil;
}


/**
 Get the last checkin times for the agent
 Return  values are to different date objects
 
 @param err Error object
 @return dictonary {mdate1 & mdate2}
 */
- (NSDictionary *)getLastCheckinData:(NSError **)err
{
    NSDictionary *data;
    NSError *error = nil;
    NSString *urlPath = [@"/api/v2/client/checkin/info" stringByAppendingPathComponent:self.clientID];
    data = [self getDataFromWS:urlPath error:&error];
    if (err != NULL) *err = error;
    
    return data;
}

/**
 Post Patch Scan data to web service
 
 @param scanData patches found array
 @param type 1 = Apple, 2 = Third
 @param err NSError, not used yet
 @return BOOL
 */
- (BOOL)postClientScanDataWithType:(NSArray *)scanData type:(NSInteger)type error:(NSError **)err
{
    BOOL result = NO;
    NSError *error = nil;
    NSDictionary *data = @{@"rows":scanData};
    NSString *urlPath = [NSString stringWithFormat:@"/api/v1/client/patch/scan/%d/%@",(int)type, self.clientID];
    qldebug(@"[postClientScanDataWithType][urlPath] %@",urlPath);
    
    result = [self postDataToWS:urlPath data:data error:&error];
    if (result) {
        qlinfo(@"Client Scan Data was posted to webservice.");
    }
    
    return result;
}


/**
 Get Agent Patch Scan List, severity is used for filtering critical patches
 
 @param aSeverity Patch severity level used for filtering
 @param err Error object
 @return array of patches, nil if error
 */
- (NSArray *)getCustomPatchScanListWithSeverity:(NSString *)aSeverity error:(NSError **)err
{
    NSError *ws_err = nil;
    NSDictionary *ws_result;
    NSArray *result = [NSArray array];
    NSString *urlPath;
    
    if (!aSeverity) {
        urlPath = [NSString stringWithFormat:@"/api/v2/client/patch/scan/list/all/%@",self.clientID];
    } else {
        // Set OS Level *, any OS
        urlPath = [NSString stringWithFormat:@"/api/v2/client/patch/scan/list/%@/%@",aSeverity, self.clientID];
    }
    
    ws_result = [self getDataFromWS:urlPath error:&ws_err];
    if (ws_err) {
        *err = ws_err;
        return nil;
    }
    
    if ([ws_result objectForKey:@"data"])
    {
        if ([[ws_result objectForKey:@"data"] isKindOfClass:[NSArray class]])
        {
            qldebug(@"Web Servce result: %@",ws_result);
            result = [ws_result objectForKey:@"data"];
        }
        else
        {
            qlerror(@"Result was not of type array.");
            qlerror(@"Result: %@", ws_result);
        }
    }
    
    return result;
}


/**
 Get a dictionary containing the approved apple and custom patches for a patch group
 assigned to the client agent.
 
 @param err Error object
 @return a dictioanary containg two arrays "AppleUpdates, CustomUpdates"
 */
- (NSDictionary *)getApprovedPatchesForClient:(NSError **)err
{
    NSError *ws_err = nil;
    NSDictionary *ws_result;
    NSDictionary *result = nil;
    
    NSString *urlPath = [NSString stringWithFormat:@"/api/v3/client/patch/group/%@",self.clientID];
    
    ws_result = [self getDataFromWS:urlPath error:&ws_err];
    if (ws_err) {
        *err = ws_err;
        return nil;
    }
    
    if ([ws_result objectForKey:@"data"])
    {
        if ([[ws_result objectForKey:@"data"] isKindOfClass:[NSDictionary class]])
        {
            qldebug(@"Web Servce result: %@",ws_result);
            result = [ws_result objectForKey:@"data"];
        }
        else
        {
            qlerror(@"Result was not of type dictionary.");
            qlerror(@"Result: %@", ws_result);
        }
    }
    
    return result;
}

/**
 Get a dictionary containing all active apple and custom patches
 
 @param err Error object
 @return a dictioanary containg two arrays "AppleUpdates, CustomUpdates"
 */
- (NSDictionary *)getAllPatchesForClient:(NSError **)err
{
	NSError *ws_err = nil;
	NSDictionary *ws_result;
	NSDictionary *result = nil;
	
	NSString *urlPath = [NSString stringWithFormat:@"/api/v3/client/patch/all/%@",self.clientID];
	
	ws_result = [self getDataFromWS:urlPath error:&ws_err];
	if (ws_err) {
		*err = ws_err;
		return nil;
	}
	
	if ([ws_result objectForKey:@"data"])
	{
		if ([[ws_result objectForKey:@"data"] isKindOfClass:[NSDictionary class]])
		{
			qldebug(@"Web Servce result: %@",ws_result);
			result = [ws_result objectForKey:@"data"];
		}
		else
		{
			qlerror(@"Result was not of type dictionary.");
			qlerror(@"Result: %@", ws_result);
		}
	}
	
	return result;
}

/**
 Post patch install using patch and type
 
 @param patch patch id or name depending on type
 @param type Apple, Third
 @param err Error object
 @return BOOL
 */
- (BOOL)postPatchInstallResults:(NSString *)patch type:(NSString *)type error:(NSError **)err
{
    BOOL result = NO;
    NSError *error = nil;
    NSString *urlPath = [NSString stringWithFormat:@"/api/v1/client/patch/install/%@/%@/%@",patch,type,self.clientID];
    qldebug(@"[postPatchInstallResults][urlPath] %@",urlPath);
    
    result = [self postDataToWS:urlPath data:nil error:&error];
    if (result) {
        qlinfo(@"Patch install data was posted to webservice.");
    }
    
    return result;
}

/**
 Post OS Migration Status
 
 @param action start / stop
 @param label
 @param migrationID migration id
 @param err Error object
 @return BOOL
 */
- (BOOL)postOSMigrationStatus:(NSString *)action label:(NSString *)label migrationID:(NSString *)migrationID error:(NSError **)err
{
    NSDictionary *data = @{@"clientID":self.clientID,
                           @"action":action,
                           @"os": [[MPSystemInfo osVersionInfo] objectForKey:@"ProductUserVisibleVersion"],
                           @"label":label, @"migrationID":migrationID};
    
    
    BOOL result = NO;
    NSError *error = nil;
    NSString *urlPath = [NSString stringWithFormat:@"/api/v1/provisioning/migration/%@",self.clientID];
    qldebug(@"[postOSMigrationStatus][urlPath] %@",urlPath);
    
    result = [self postDataToWS:urlPath data:data error:&error];
    if (result) {
        qlinfo(@"OS Migration Status data was posted to webservice.");
    }
    
    return result;
}

/**
 Post Agent Registration Data using registration key
 
 @param regData A dictionary containing the registration data
 @param key registration key given from console
 @param err Error object
 @return BOOL
 */
- (BOOL)postAgentRegistration:(NSDictionary *)regData regKey:(NSString *)key error:(NSError **)err;
{
    BOOL result = NO;
    NSError *error = nil;
    
    NSString *urlPath;
    if (!key) {
        urlPath = [NSString stringWithFormat:@"/api/v2/client/register/%@",self.clientID];
    } else {
        urlPath = [NSString stringWithFormat:@"/api/v2/client/register/%@/%@",self.clientID,key];
    }
    
    qldebug(@"[postAgentRegistration][urlPath] %@",urlPath);
    qldebug(@"[postAgentRegistration][data] %@",regData);
    
    result = [self postDataToWS:urlPath data:regData error:&error];
    if (result) {
        qlinfo(@"Agent registration data was posted to webservice.");
    }
    
    return result;
}

/**
 Get agent registration status from web service
 
 @param key Client reg key hash
 @param err Error object
 @return BOOL on if registered
 */
- (BOOL)getAgentRegistrationStatusUsingKey:(NSString *)key error:(NSError **)err
{
    BOOL        result = NO;
    NSString    *urlPath;
    if (!key) {
        urlPath = [NSString stringWithFormat:@"/api/v2/client/register/status/%@",self.clientID];
    } else {
        urlPath = [NSString stringWithFormat:@"/api/v2/client/register/status/%@/%@",self.clientID,key];
    }
    
    MPHTTPRequest *req;
    MPWSResult *wsresult;
    
    req = [[MPHTTPRequest alloc] init];
    wsresult = [req runSyncGET:urlPath];
   
    logit(lcl_vInfo,@"Web Service Status code %d",(int)wsresult.statusCode);
    logit(lcl_vDebug,@"Data Result: %@",wsresult.result);
    
    switch (wsresult.statusCode) {
        case 200:
            result = YES;
            break;
        case 204:
            result = NO;
            break;
        default:
            result = NO;
            break;
    }
    
    return result;
}


/**
 Post software install data
 
 @param data software install data
 @param err Error object
 @return BOOL
 */
- (BOOL)postSoftwareInstallResults:(NSDictionary *)data error:(NSError **)err
{
    BOOL result = NO;
    NSError *error = nil;
    NSString *urlPath = [@"/api/v1/sw/installed" stringByAppendingPathComponent:self.clientID];
    qldebug(@"[postSoftwareInstallResults][urlPath] %@",urlPath);
    qldebug(@"[postSoftwareInstallResults][data] %@",data);
    
    result = [self postDataToWS:urlPath data:data error:&error];
    if (error) {
        *err = error;
    }
    if (result) {
        qlinfo(@"Software install data was posted to webservice.");
    }
    
    return result;
}


/**
 Get software tasks for a catalog group
 
 @param aGroupName catalog group name String
 @param err Error object
 @return NSArray
 */
- (NSArray *)getSoftwareTasksForGroup:(NSString *)groupName error:(NSError **)err
{
    if (!groupName) {
        NSError *tErr = [NSError errorWithDomain:NSCocoaErrorDomain code:-1000 userInfo:@{NSLocalizedDescriptionKey: @"No Group Name Found"}];
        if (err != NULL) *err = tErr;
        return nil;
    }
    
    NSError *ws_err = nil;
    NSDictionary *ws_result;
    NSArray *result = nil;
    
    //NSString *urlPath = [NSString stringWithFormat:@"/api/v2/sw/tasks/%@/%@",self.ccuid, [groupName stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]]];
	NSString *urlPath = [NSString stringWithFormat:@"/api/v4/sw/tasks/%@/%@",self.clientID, [groupName stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]]];
    qldebug(@"[getSoftwareTasksForGroup][urlPath] %@",urlPath);
    
    ws_result = [self getDataFromWS:urlPath error:&ws_err];
    if (ws_err) {
        *err = ws_err;
        return nil;
    }
    
    if ([ws_result objectForKey:@"data"])
    {
        if ([[ws_result objectForKey:@"data"] isKindOfClass:[NSArray class]])
        {
            qldebug(@"Web Servce result: %@",ws_result);
            result = [ws_result objectForKey:@"data"];
        }
        else
        {
            qlerror(@"Result was not of type array.");
            qlerror(@"Result: %@", ws_result);
        }
    }
    
    return result;
}

/**
 Get software task data using software task id (tuuid)
 
 @param taskID Software task id
 @param err Error object
 @return NSDictionary
 */
- (NSDictionary *)getSoftwareTaskUsingTaskID:(NSString *)taskID error:(NSError **)err
{
	if (!taskID) {
		NSError *tErr = [NSError errorWithDomain:NSCocoaErrorDomain code:-1000 userInfo:@{NSLocalizedDescriptionKey: @"No Task ID Found"}];
		if (err != NULL) *err = tErr;
		return nil;
	}
	
	NSError *ws_err = nil;
	NSDictionary *ws_result;
	NSDictionary *result = nil;
	
	NSString *urlPath = [NSString stringWithFormat:@"/api/v2/sw/task/%@/%@",self.clientID, taskID];
	qldebug(@"[getSoftwareTasksForGroup][urlPath] %@",urlPath);
	
	ws_result = [self getDataFromWS:urlPath error:&ws_err];
	if (ws_err) {
		*err = ws_err;
		return nil;
	}
	
	if ([ws_result objectForKey:@"data"])
	{
		if ([[ws_result objectForKey:@"data"] isKindOfClass:[NSDictionary class]])
		{
			qldebug(@"Web Servce result: %@",ws_result);
			result = [ws_result objectForKey:@"data"];
		}
		else
		{
			qlerror(@"Result was not of type dictionary.");
			qlerror(@"Result: %@", ws_result);
		}
	}
	
	return result;
}

/**
 Get Hash to run plugin
 
 @param plugin plugin name
 @param bundleID plugin bundleid
 @param version plugin version
 @param err Error object
 @return NSString
 */
- (NSString *)getHashForPluginName:(NSString *)plugin pluginBunleID:(NSString *)bundleID pluginVersion:(NSString *)version error:(NSError **)err
{
    NSError *ws_err = nil;
    NSDictionary *ws_result;
    
    NSString *result;
    NSString *urlPath = [NSString stringWithFormat:@"/api/v2/agent/plugin/hash/%@/%@/%@/%@", plugin, bundleID, version, self.clientID];
    qldebug(@"[urlPath] %@",urlPath);
    
    ws_result = [self getDataFromWS:urlPath error:&ws_err];
    if (ws_err) {
        *err = ws_err;
        return nil;
    }
    
    if ([ws_result objectForKey:@"data"])
    {
        if ([[ws_result objectForKey:@"data"] isKindOfClass:[NSString class]])
        {
            qldebug(@"Web Servce result: %@",ws_result);
            result = [ws_result objectForKey:@"data"];
        }
        else
        {
            qlerror(@"Result was not of type array.");
            qlerror(@"Result: %@", ws_result);
        }
    }
    
    return result;
}

/**
 Get agent inventory state, checks wether agent has posted inventory or not.
 
 @param err Error Object
 @return BOOL
 */
- (BOOL)getAgentHasInventoryDataInDB:(NSError **)err
{
    BOOL      result    = NO;
    NSString  *urlPath  = [NSString stringWithFormat:@"/api/v2/client/inventory/state/%@",self.clientID];
    
    MPHTTPRequest *req;
    MPWSResult *wsresult;
    
    req = [[MPHTTPRequest alloc] init];
    wsresult = [req runSyncGET:urlPath];
    
    if (wsresult.statusCode >= 200 && wsresult.statusCode <= 299)
    {
        logit(lcl_vDebug,@"Web Service Status code %d",(int)wsresult.statusCode);
        logit(lcl_vDebug,@"Get Data from web service (%@) returned true.",urlPath);
        logit(lcl_vDebug,@"Data Result: %@",wsresult.result);
        result = [[wsresult.result objectForKey:@"data"] boolValue];
    }
    else
    {
        logit(lcl_vError,@"Get Data from web service (%@), returned false.", urlPath);
        logit(lcl_vDebug,@"%@",wsresult.toDictionary);
        
        NSError *error = [NSError errorWithDomain:@"gov.llnl.mp.rest"
                                             code:wsresult.statusCode
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to get data from web service"}];
        
        if (err != NULL) *err = error;
    }
    
    return result;
}


/**
 Post that the agent has inventory data populated
 
 @param err Error Object
 @return BOOL
 */
- (BOOL)postAgentHasInventoryData:(NSError **)err
{
    BOOL result = NO;
    NSError *error = nil;
    NSString *urlPath = [NSString stringWithFormat:@"/api/v2/client/inventory/state/%@",self.clientID];
    qldebug(@"[postAgentHasInventoryData][urlPath] %@",urlPath);
    
    result = [self postDataToWS:urlPath data:nil error:&error];
    if (error) {
        *err = error;
    }
    
    return result;
}

/**
 Get an array of software catalogs to display

 @return NSArray
 */
- (NSArray *)getSoftwareCatalogs:(NSError **)err
{
    NSError *ws_err = nil;
    NSDictionary *ws_result;
    NSArray *result = nil;
    
    NSString *urlPath = [NSString stringWithFormat:@"/api/v2/sw/groups/%@",self.clientID];
    qldebug(@"[getSoftwareTasksForGroup][urlPath] %@",urlPath);
    
    ws_result = [self getDataFromWS:urlPath error:&ws_err];
    if (ws_err) {
        *err = ws_err;
        return nil;
    }
    
    if ([ws_result objectForKey:@"data"])
    {
        if ([[ws_result objectForKey:@"data"] isKindOfClass:[NSArray class]])
        {
            qldebug(@"Web Servce result: %@",ws_result);
            result = [ws_result objectForKey:@"data"];
        }
        else
        {
            qlerror(@"Result was not of type array.");
            qlerror(@"Result: %@", ws_result);
        }
    }
    
    return result;
}

/**
 Get patch dictionary for a bundle id, this method is used for patching
 client group required software
 
 @param bundleID plugin bundleid
 @param err Error object
 
 @return NSDictionary
 */
- (NSDictionary *)getPatchForBundleID:(NSString *)bundleID error:(NSError **)err
{
	NSError *ws_err = nil;
	NSDictionary *ws_result;
	NSDictionary *result = nil;
	
	NSString *urlPath = [NSString stringWithFormat:@"/api/v3/patch/bundleID/%@/%@",bundleID,self.clientID];
	qldebug(@"[getPatchForBundleID][urlPath] %@",urlPath);
	
	ws_result = [self getDataFromWS:urlPath error:&ws_err];
	if (ws_err) {
		*err = ws_err;
		return nil;
	}
	
	
	if ([ws_result objectForKey:@"data"])
	{
		if ([[ws_result objectForKey:@"data"] isKindOfClass:[NSDictionary class]])
		{
			qldebug(@"Web Servce result: %@",ws_result);
			result = [ws_result objectForKey:@"data"];
		}
		else
		{
			qlerror(@"Result was not of type dictionary.");
			qlerror(@"Result: %@", ws_result);
		}
	}
	
	return result;
}

/**
 Get software restrictions for the client
 
 @param err Error object
 @return Dictionary of the revision and rules
 */
- (NSDictionary *)getSoftwareRestrictions:(NSError **)err
{
	NSError *ws_err = nil;
	NSDictionary *ws_result;
	NSDictionary *result = nil;
	
	NSString *urlPath = [NSString stringWithFormat:@"/api/v3/sw/restrictions/%@",self.clientID];
	qldebug(@"[getSoftwareRestrictions][urlPath] %@",urlPath);
	
	ws_result = [self getDataFromWS:urlPath error:&ws_err];
	if (ws_err) {
		*err = ws_err;
		return nil;
	}
	
	
	if ([ws_result objectForKey:@"data"])
	{
		if ([[ws_result objectForKey:@"data"] isKindOfClass:[NSDictionary class]])
		{
			qldebug(@"Web Servce result: %@",ws_result);
			result = [ws_result objectForKey:@"data"];
		}
		else
		{
			qlerror(@"Result was not of type dictionary.");
			qlerror(@"Result: %@", ws_result);
		}
	}
	
	return result;
}


/**
 Get S3 url for package type

 @param type (patch, sw)
 @param id ID of the package to download
 @return Dictionary (url is the key)
 */
- (NSDictionary *)getS3URLForType:(NSString *)type id:(NSString *)packageID
{
	// /url/<string:type>/<string:id>/<string:cuuid>
	
	NSError *ws_err = nil;
	NSDictionary *ws_result;
	NSDictionary *result = nil;
	
	NSString *urlPath = [NSString stringWithFormat:@"/api/v1/aws/url/%@/%@/%@",type,packageID,self.clientID];
	qldebug(@"[getS3URLForType][urlPath] %@",urlPath);
	
	ws_result = [self getDataFromWS:urlPath error:&ws_err];
	if (ws_err) {
		qlerror(@"%@",ws_err.localizedDescription);
		//*err = ws_err;
		return nil;
	}
	
	if ([ws_result objectForKey:@"result"])
	{
		if ([[ws_result objectForKey:@"result"] isKindOfClass:[NSDictionary class]])
		{
			qldebug(@"Web Servce result: %@",ws_result);
			result = [ws_result objectForKey:@"result"];
		}
		else
		{
			qlerror(@"Result was not of type dictionary.");
			qlerror(@"Result: %@", ws_result);
		}
	}
	
	return result;
}

/**
 Post agent install
 
 @param agentVer agent version installed
 @param err Error object
 @return BOOL
 */
- (BOOL)postAgentInstall:(NSString *)agentVer error:(NSError **)err
{
    BOOL result = NO;
    NSError *error = nil;
	NSString *urlPath = [NSString stringWithFormat:@"/api/v3/agent/install/%@/%@",self.clientID,agentVer];
    qldebug(@"[postAgentInstall][urlPath] %@",urlPath);
    
    result = [self postDataToWS:urlPath data:nil error:&error];
    if (error) {
        *err = error;
    }
    if (result) {
        qlinfo(@"Agent install data was posted to webservice.");
    }
    
    return result;
}

/**
 Get provisioning dictionary to provision a host
 
 @param clientID client ID, used for determingin if QA scope can be used.
 @param err Error object
 
 @return NSDictionary
 */
- (NSDictionary *)getProvisioningDataForHost:(NSString *)clientID error:(NSError **)err
{
    NSError *ws_err = nil;
    NSDictionary *ws_result;
    NSDictionary *result = nil;
    
    NSString *urlPath = [NSString stringWithFormat:@"/api/v1/provisioning/data/%@",self.clientID];
    qldebug(@"[getProvisioningDataForHost][urlPath] %@",urlPath);
    
    ws_result = [self getDataFromWS:urlPath error:&ws_err];
    if (ws_err) {
        *err = ws_err;
        return nil;
    }
    
    
    if ([ws_result objectForKey:@"data"])
    {
        if ([[ws_result objectForKey:@"data"] isKindOfClass:[NSDictionary class]])
        {
            qldebug(@"Web Servce result: %@",ws_result);
            result = [ws_result objectForKey:@"data"];
        }
        else
        {
            qlerror(@"Result was not of type dictionary.");
            qlerror(@"Result: %@", ws_result);
        }
    }
    
    return result;
}

/**
 Get provisioning config json data, needs to be written to file.
 Will return NSString of JSON data
 
 @param err Error object
 
 @return NSString
 */
- (NSString *)getProvisioningConfig:(NSError **)err
{
    NSError *ws_err = nil;
    NSDictionary *ws_result;
    NSString *result = nil;
    
    NSString *urlPath = [NSString stringWithFormat:@"/api/v1/provisioning/config/%@",self.clientID];
    qldebug(@"[getProvisioningConfig][urlPath] %@",urlPath);
    
    ws_result = [self getDataFromWS:urlPath error:&ws_err];
    if (ws_err) {
        *err = ws_err;
        return nil;
    }
    
    
    if ([ws_result objectForKey:@"data"])
    {
        if ([[ws_result objectForKey:@"data"] isKindOfClass:[NSDictionary class]])
        {
            qldebug(@"Web Servce result: %@",ws_result);
            NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:[ws_result objectForKey:@"data"] options:0];
            result = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
        }
        else
        {
            qlerror(@"Result was not of type dictionary.");
            qlerror(@"Result: %@", ws_result);
        }
    }
    
    return result;
}
@end
