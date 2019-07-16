//
//  SoftwareController.m
//  MPAgent
//
//  Created by Charles Heizer on 5/9/19.
//  Copyright © 2019 LLNL. All rights reserved.
//

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
		qlerror(@"Software tasks list was empty. No installs will occure.");
		qldebug(@"Task List String: %@",tasks);
		return 1;
	}
	
	for (NSString *_task in _tasksArray)
	{
		if (![self installSoftwareTask:_task]) return 1;
	}
	
	if (needsReboot >= 1) {
		qlinfo(@"Software has been installed that requires a reboot.");
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
			qlerror(@"Group (%@) contains no tasks.",aGroupName);
			return 0;
		}
	}
	else
	{
		qlerror(@"No tasks for group %@ were found.",aGroupName);
		return result;
	}
	
	for (NSDictionary *task in tasks)
	{
		MPSoftware *software = [MPSoftware new];
		if (![software installSoftwareTask:task])
		{
			qlerror(@"FAILED to install task %@",[task objectForKey:@"name"]);
			result = 1;
		}
	}
	
	if (needsReboot >= 1) {
		qlinfo(@"Software has been installed that requires a reboot.");
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
		logit(lcl_vError,@"No installs will occure. Plist %@ was not found.",aPlist);
		return 1;
	}
	
	NSDictionary *pData = [NSDictionary dictionaryWithContentsOfFile:aPlist];
	if (![pData objectForKey:@"tasks"])
	{
		logit(lcl_vError,@"No installs will occure. No tasks found.");
		return 1;
	}
	
	NSArray *pTasks = pData[@"tasks"];
	for (NSString *aTask in pTasks)
	{
		if (![self installSoftwareTask:aTask])
		{
			qlinfo(@"Software has been installed that requires a reboot.");
			result++;
		}
	}
	
	if (needsReboot >= 1)
	{
		qlinfo(@"Software has been installed that requires a reboot.");
		return 2;
	}
	
	return result;
}

/**
 Private Method
 Install Software Task using software task ID
 
 @param swTaskID software task ID
 @return BOOL
 */
- (BOOL)installSoftwareTask:(NSString *)aTask
{
	BOOL result = NO;
	NSDictionary *task = [self getSoftwareTaskForID:aTask];
	
	if (!task) {
		qlerror(@"Error, no task to install.");
		return NO;
	}
	MPSoftware *software = [MPSoftware new];
	[self iLoadStatus:@"Begin: %@\n", task[@"name"]];
	if ([software installSoftwareTask:task] == 0)
	{
		qlinfo(@"%@ task was installed.",task[@"name"]);
		result = YES;
		if ([self softwareTaskRequiresReboot:task]) needsReboot++;
		//[self iLoadStatus:@"Installing: %@\n Succeeded.", task[@"name"]];
		[self iLoadStatus:@"Completed: %@\n", task[@"name"]];
	} else {
		qlerror(@"%@ task was not installed.",task[@"name"]);
		//[self iLoadStatus:@"Installing: %@\n Failed.", task[@"name"]];
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
	qlinfo(@"Checking %@ criteria.",[aTask objectForKey:@"name"]);
	
	MPOSCheck *mpos = [[MPOSCheck alloc] init];
	NSDictionary *_SoftwareCriteria = [aTask objectForKey:@"SoftwareCriteria"];
	
	// OSArch
	if ([mpos checkOSArch:[_SoftwareCriteria objectForKey:@"arch_type"]]) {
		qldebug(@"OSArch=TRUE: %@",[_SoftwareCriteria objectForKey:@"arch_type"]);
	} else {
		qlinfo(@"OSArch=FALSE: %@",[_SoftwareCriteria objectForKey:@"arch_type"]);
		return NO;
	}
	
	// OSType
	if ([mpos checkOSType:[_SoftwareCriteria objectForKey:@"os_type"]]) {
		qldebug(@"OSType=TRUE: %@",[_SoftwareCriteria objectForKey:@"os_type"]);
	} else {
		qlinfo(@"OSType=FALSE: %@",[_SoftwareCriteria objectForKey:@"os_type"]);
		return NO;
	}
	// OSVersion
	if ([mpos checkOSVer:[_SoftwareCriteria objectForKey:@"os_vers"]]) {
		qldebug(@"OSVersion=TRUE: %@",[_SoftwareCriteria objectForKey:@"os_vers"]);
	} else {
		qlinfo(@"OSVersion=FALSE: %@",[_SoftwareCriteria objectForKey:@"os_vers"]);
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
		qlinfo(@"[MPAgentExecController][postDataToWS]: Data post to web service (%@), returned true.", urlPath);
		//qldebug(@"Data post to web service (%@), returned true.", urlPath);
		qldebug(@"Data Result: %@",result.result);
	} else {
		qlerror(@"Data post to web service (%@), returned false.", urlPath);
		qldebug(@"%@",result.toDictionary);
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
		qldebug(@"Get Data from web service (%@) returned true.",urlPath);
		qldebug(@"Data Result: %@",wsresult.result);
		result = wsresult.result;
	} else {
		qlerror(@"Get Data from web service (%@), returned false.", urlPath);
		qldebug(@"%@",wsresult.toDictionary);
	}
	
	return result;
}

@end
