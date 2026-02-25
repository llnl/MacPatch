//
//  SoftwareController.m
//  MPAgent
//
/*
 Copyright (c) 2026, Lawrence Livermore National Security, LLC.
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

#import "SoftwareController.h"

@interface SoftwareController ()
{
	NSFileManager *fm;
	MPSettings *settings;
}

@property (nonatomic, assign, readwrite) int        errorCode;
@property (nonatomic, strong, readwrite) NSString  *errorMsg;
@property (nonatomic, assign, readwrite) int        needsReboot;

@property (nonatomic, strong)           NSURL       *mp_SOFTWARE_DATA_DIR;

// Web Services
- (void)postInstallResults:(int)resultNo resultText:(NSString *)resultString task:(NSDictionary *)taskDict;

// Misc
- (void)iLoadStatus:(NSString *)str, ...;

@end

@implementation SoftwareController

@synthesize iLoadMode;
@synthesize needsReboot;
@synthesize mp_SOFTWARE_DATA_DIR;

- (id)init
{
	self = [super init];
	if (self)
	{
		fm          = [NSFileManager defaultManager];
		settings    = [MPSettings sharedInstance];
		
		[self setILoadMode:NO];
		[self setErrorCode:-1];
		[self setErrorMsg:@""];
	}
	return self;
}

#pragma mark - SW Dist Installs
/**
 Install a list of software tasks using a string of task ID's
 
 @param tasks - string of task ID's
 @param delimiter - delimter default is ","
 @return int
 */
- (int)installSoftwareTasksFromString:(NSString *)tasks delimiter:(NSString *)delimiter
{
	needsReboot = 0;
	NSString *_delimiter = @",";
	if (delimiter != NULL) _delimiter = delimiter;
	
	NSArray *_tasksArray = [tasks componentsSeparatedByString:_delimiter];
	if (!_tasksArray) {
		LogError(@"Software tasks list was empty. No installs will occure.");
		LogDebug(@"Task List String: %@",tasks);
		return 1;
	}
	
	for (NSString *_task in _tasksArray)
	{
		if (![self installSoftwareTask:_task]) return 1;
	}
	
	if (needsReboot >= 1) {
		LogInfo(@"Software has been installed that requires a reboot.");
		return 2;
	}
	
	return 0;
}


/**
 Install all software tasks for a given group name.
 
 @param aGroupName - Group Name
 @return int
 */
- (int)installSoftwareTasksForGroup:(NSString *)aGroupName
{
	needsReboot = 0;
	int result = 1;
    
	NSArray *tasks;
	NSString *urlPath = [NSString stringWithFormat:@"/api/v2/sw/tasks/%@/%@",settings.ccuid, aGroupName];
	NSDictionary *data = [self getDataFromWS:urlPath];
	
	if (data[@"data"])
	{
		tasks = data[@"data"];
		if ([tasks count] <= 0) {
			LogError(@"Group (%@) contains no tasks.",aGroupName);
			return 0;
		}
	}
	else
	{
		LogError(@"No tasks for group %@ were found.",aGroupName);
		return result;
	}
	
	for (NSDictionary *task in tasks)
	{
        if (![self installSoftwareUsingTaskDictionary:task])
        {
            LogInfo(@"Software has been installed that requires a reboot.");
            result++;
        }
	}
	
	if (needsReboot >= 1) {
		LogInfo(@"Software has been installed that requires a reboot.");
		result = 2;
	}
	
	return result;
}


/**
 Install software tasks using a plist. Plist must contain "tasks" key
 of the type array. Each task id is a string.
 
 @param aPlist file path to the plist
 @return int 0 = ok
 */
- (int)installSoftwareTasksUsingPLIST:(NSString *)aPlist
{
	needsReboot = 0;
	int result = 0;
	
	if ([fm fileExistsAtPath:aPlist] == NO)
	{
		LogError(@"No installs will occure. Plist %@ was not found.",aPlist);
		return 1;
	}
	
	NSDictionary *pData = [NSDictionary dictionaryWithContentsOfFile:aPlist];
	if (![pData objectForKey:@"tasks"])
	{
		LogError(@"No installs will occure. No tasks found.");
		return 1;
	}
	
	NSArray *pTasks = pData[@"tasks"];
	for (NSString *aTask in pTasks)
	{
		if (![self installSoftwareTask:aTask])
		{
			LogInfo(@"Software has been installed that requires a reboot.");
			result++;
		}
	}
	
	if (needsReboot >= 1)
	{
		LogInfo(@"Software has been installed that requires a reboot.");
		return 2;
	}
	
	return result;
}
/**
 Install Mandatory Software
 
 @return INT
 */
- (int)installMandatorySoftware
{
    needsReboot = 0;
    int result = 1;
    
    Agent *agent = [settings agent];
    NSString *clientGroup = agent.clientGroup;
    
    NSArray *tasks;
    NSString *urlPath = [NSString stringWithFormat:@"/api/v2/sw/tasks/%@/%@",settings.ccuid, clientGroup];
    NSDictionary *data = [self getDataFromWS:urlPath];
    
    if (data[@"data"])
    {
        tasks = data[@"data"];
        if ([tasks count] <= 0) {
            LogError(@"Group (%@) contains no tasks.",clientGroup);
            return 0;
        }
    }
    else
    {
        LogError(@"No tasks for group %@ were found.",clientGroup);
        return result;
    }
    
    for (NSDictionary *task in tasks)
    {
        if ([task[@"sw_task_type"] isEqualToString:@"m"])
        {
            LogInfo(@"Installing mandarory software task %@ (%@)",task[@"name"],task[@"id"]);
            if (![self installSoftwareUsingTaskDictionary:task])
            {
                LogInfo(@"Software has been installed that requires a reboot.");
                result++;
            }
        }
    }
    
    if (needsReboot >= 1) {
        LogInfo(@"Software has been installed that requires a reboot.");
        result = 2;
    }
    
    return result;
}

/**
 Private Method
 Install Software Task using software task ID
 
 @param aTask software task ID
 @return BOOL
 */
- (BOOL)installSoftwareTask:(NSString *)aTask
{
	BOOL result = NO;
	NSDictionary *task = [self getSoftwareTaskForID:aTask];
	
	if (!task) {
		LogError(@"Error, no task to install.");
		return NO;
	}
	MPSoftware *software = [MPSoftware new];
	[self iLoadStatus:@"Begin: %@", task[@"name"]];
	if ([software installSoftwareTask:task] == 0)
	{
		LogInfo(@"%@ task was installed.",task[@"name"]);
		result = YES;
		if ([self softwareTaskRequiresReboot:task]) needsReboot++;
		[self iLoadStatus:@"Completed: %@\n", task[@"name"]];
	} else {
		LogError(@"%@ task was not installed.",task[@"name"]);
		[self iLoadStatus:@"Completed: %@ Failed.\n", task[@"name"]];
	}
	return result;
}

/**
 Private Method
 Install Software Task using software task dictionary
 
 @param task software task dictionary
 @return BOOL
 */
- (BOOL)installSoftwareUsingTaskDictionary:(NSDictionary *)task
{
    BOOL result = NO;
    
    MPSoftware *software = [MPSoftware new];
    [self iLoadStatus:@"Begin: %@", task[@"name"]];
    if ([software installSoftwareTask:task] == 0)
    {
        LogInfo(@"%@ task was installed.",task[@"name"]);
        result = YES;
        if ([self softwareTaskRequiresReboot:task]) needsReboot++;
        [self iLoadStatus:@"Completed: %@\n", task[@"name"]];
    } else {
        LogError(@"%@ task was not installed.",task[@"name"]);
        [self iLoadStatus:@"Completed: %@ Failed.\n", task[@"name"]];
    }
    return result;
}

// Private
- (BOOL)recordInstallSoftwareItem:(NSDictionary *)dict
{
	NSString *installFile = [[mp_SOFTWARE_DATA_DIR path] stringByAppendingPathComponent:@".installed.plist"];
	NSMutableDictionary *installData = [[NSMutableDictionary alloc] init];
	[installData setObject:[NSDate date] forKey:@"installDate"];
	[installData setObject:[dict objectForKey:@"id"] forKey:@"id"];
	[installData setObject:[dict objectForKey:@"name"] forKey:@"name"];
	if ([dict objectForKey:@"sw_uninstall"]) {
		[installData setObject:[dict objectForKey:@"sw_uninstall"] forKey:@"sw_uninstall"];
	} else {
		[installData setObject:@"" forKey:@"sw_uninstall"];
	}
	NSMutableArray *_data;
	if ([fm fileExistsAtPath:installFile]) {
		_data = [NSMutableArray arrayWithContentsOfFile:installFile];
	} else {
		if (![fm fileExistsAtPath:[mp_SOFTWARE_DATA_DIR path]]) {
			NSDictionary *attributes = [NSDictionary dictionaryWithObject:[NSNumber numberWithShort:0777] forKey:NSFilePosixPermissions];
			[fm createDirectoryAtPath:[mp_SOFTWARE_DATA_DIR path] withIntermediateDirectories:YES attributes:attributes error:NULL];
		}
		_data = [NSMutableArray array];
	}
	[_data addObject:installData];
	[_data writeToFile:installFile atomically:YES];
	installData = nil;
	return YES;
}

// Private
- (void)postInstallResults:(int)resultNo resultText:(NSString *)resultString task:(NSDictionary *)taskDict
{
	MPSWTasks *swt = [[MPSWTasks alloc] init];
	int result = -1;
	result = [swt postInstallResults:resultNo resultText:resultString task:taskDict];
	swt = nil;
}

// Private
- (NSDictionary *)getSoftwareTaskForID:(NSString *)swTaskID
{
	NSDictionary *task = nil;
	NSDictionary *data = nil;
	
	NSString *urlPath = [NSString stringWithFormat:@"/api/v2/sw/task/%@/%@",settings.ccuid, swTaskID];
	data = [self getDataFromWS:urlPath];
	if (data[@"data"])
	{
		task = data[@"data"];
	}
	
	return task;
}


/**
 Private Method
 Query a Software Task for reboot requirement.
 
 @param task software task dictionary
 @return BOOL
 */
- (BOOL)softwareTaskRequiresReboot:(NSDictionary *)task
{
	BOOL result = NO;
	NSNumber *_rbNumber = [task valueForKeyPath:@"Software.reboot"];
	NSInteger _reboot = [_rbNumber integerValue];
	switch (_reboot) {
		case 0:
			result = NO;
			break;
		case 1:
			result = YES;
			break;
		default:
			break;
	}
	
	return result;
}

// Private
- (BOOL)softwareTaskCriteriaCheck:(NSDictionary *)aTask
{
	LogInfo(@"Checking %@ criteria.",[aTask objectForKey:@"name"]);
	
	MPOSCheck *mpos = [[MPOSCheck alloc] init];
	NSDictionary *_SoftwareCriteria = [aTask objectForKey:@"SoftwareCriteria"];
	
	// OSArch
	if ([mpos checkOSArch:[_SoftwareCriteria objectForKey:@"arch_type"]]) {
		LogDebug(@"OSArch=TRUE: %@",[_SoftwareCriteria objectForKey:@"arch_type"]);
	} else {
		LogInfo(@"OSArch=FALSE: %@",[_SoftwareCriteria objectForKey:@"arch_type"]);
		return NO;
	}
	
	// OSType
    /* CEH: Dsable for now, no longer needed.
	if ([mpos checkOSType:[_SoftwareCriteria objectForKey:@"os_type"]]) {
		LogDebug(@"OSType=TRUE: %@",[_SoftwareCriteria objectForKey:@"os_type"]);
	} else {
		LogInfo(@"OSType=FALSE: %@",[_SoftwareCriteria objectForKey:@"os_type"]);
		return NO;
	}
     */
	// OSVersion
	if ([mpos checkOSVer:[_SoftwareCriteria objectForKey:@"os_vers"]]) {
		LogDebug(@"OSVersion=TRUE: %@",[_SoftwareCriteria objectForKey:@"os_vers"]);
	} else {
		LogInfo(@"OSVersion=FALSE: %@",[_SoftwareCriteria objectForKey:@"os_vers"]);
		return NO;
	}
	
	mpos = nil;
	return YES;
}

/**
 Echo status to stdout for iLoad. Will only echo if iLoadMode is true
 
 @param str Status string to echo
 */
- (void)iLoadStatus:(NSString *)str, ...
{
	va_list va;
	va_start(va, str);
	NSString *string = [[NSString alloc] initWithFormat:str arguments:va];
	va_end(va);
	if (iLoadMode == YES) {
		fprintf(stdout,"%s\n", [string cStringUsingEncoding:NSUTF8StringEncoding]);
		//printf("%s\n", [string cStringUsingEncoding:NSUTF8StringEncoding]);
	}
}

#pragma mark - Web Service Requests

- (BOOL)postDataToWS:(NSString *)urlPath data:(NSDictionary *)data
{
	MPHTTPRequest *req;
	MPWSResult *result;
	
	req = [[MPHTTPRequest alloc] init];
	result = [req runSyncPOST:urlPath body:data];
	
	if (result.statusCode >= 200 && result.statusCode <= 299) {
		LogInfo(@"[MPAgentExecController][postDataToWS]: Data post to web service (%@), returned true.", urlPath);
		//LogDebug(@"Data post to web service (%@), returned true.", urlPath);
		LogDebug(@"Data Result: %@",result.result);
	} else {
		LogError(@"Data post to web service (%@), returned false.", urlPath);
		LogDebug(@"%@",result.toDictionary);
		return NO;
	}
	
	return YES;
}

- (NSDictionary *)getDataFromWS:(NSString *)urlPath
{
	NSDictionary *result = nil;
	MPHTTPRequest *req;
	MPWSResult *wsresult;
	
	req = [[MPHTTPRequest alloc] init];
	wsresult = [req runSyncGET:urlPath];
	
	if (wsresult.statusCode >= 200 && wsresult.statusCode <= 299) {
		LogDebug(@"Get Data from web service (%@) returned true.",urlPath);
		LogDebug(@"Data Result: %@",wsresult.result);
		result = wsresult.result;
	} else {
		LogError(@"Get Data from web service (%@), returned false.", urlPath);
		LogDebug(@"%@",wsresult.toDictionary);
	}
	
	return result;
}

@end
