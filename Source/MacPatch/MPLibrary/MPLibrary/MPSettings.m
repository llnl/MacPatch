//
//  MPSettings.m
//  MPLibrary
//
//  Created by Charles Heizer on 6/12/17.
//
//

#import "MPSettings.h"
#import <IOKit/IOKitLib.h>

#import "Agent.h"
#import "Server.h"
#import "Suserver.h"
#import "Task.h"
#import "MPHTTPRequest.h"

#define SCHEMA_REV  310


#undef  ql_component
#define ql_component lcl_cMPSettings

static MPSettings *_instance;

@interface MPSettings ()

@property (nonatomic, readwrite) NSFileManager *fm;

@property (nonatomic, strong, readwrite) NSString *ccuid;
@property (nonatomic, strong, readwrite) NSString *serialno;
@property (nonatomic, strong, readwrite) NSString *osver;
@property (nonatomic, strong, readwrite) NSString *ostype;

@property (nonatomic, strong, readwrite) Agent *agent;
@property (nonatomic, strong, readwrite) NSArray *servers;
@property (nonatomic, strong, readwrite) NSArray *suservers;
@property (nonatomic, strong, readwrite) NSArray *tasks;

@end

@implementation MPSettings

@synthesize fm;

@synthesize ccuid;
@synthesize serialno;
@synthesize osver;
@synthesize ostype;

@synthesize agent;
@synthesize servers;
@synthesize suservers;
@synthesize tasks;

+ (MPSettings *)sharedInstance
{
    @synchronized(self)
    {
        if (_instance == nil)
		{
            _instance = [[super allocWithZone:NULL] init];
            _instance = [[MPSettings alloc] init];
            // Perform other initialisation...
            _instance.fm = [NSFileManager defaultManager];
            
            // Set Permissions on db file
            NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
            [dict setObject:[NSNumber numberWithInt:511] forKey:NSFilePosixPermissions];
            NSError *error = nil;
            [_instance.fm setAttributes:dict ofItemAtPath:MP_AGENT_SETTINGS error:&error];
            [_instance setCcuid:[_instance clientID]];
            [_instance setSerialno:[_instance clientSerialNumber]];
            [_instance collectOSInfo];
            [_instance settings];
        }
    }
    return _instance;
}

#pragma mark Singleton Methods

+ (id)allocWithZone:(NSZone *)zone
{
    return [self sharedInstance];
}

- (id)copyWithZone:(NSZone *)zone
{
    return self;
}

#pragma mark - Public
- (BOOL)refresh
{
    return [self settings];
}

- (BOOL)settings
{
    NSDictionary *_settings;
    
    if (![fm fileExistsAtPath:MP_AGENT_SETTINGS])
    {
        // No Settings File, need to download and create
        _settings = [self allSettingsFromServer:YES];
        qlinfo(@"Writing new agent settings to disk.");
        
        if ([fm isWritableFileAtPath:[MP_AGENT_SETTINGS stringByDeletingLastPathComponent]]) {
            [_settings writeToFile:MP_AGENT_SETTINGS atomically:YES];
        } else {
            qlerror(@"Unable to write file to %@",[MP_AGENT_SETTINGS stringByDeletingLastPathComponent]);
            return NO;
        }
    }
    else
    {
        _settings = [NSDictionary dictionaryWithContentsOfFile:MP_AGENT_SETTINGS];
    }
    
    self.agent      = [[Agent alloc] initWithDictionary:_settings[@"settings"][@"agent"][@"data"]];
    self.servers    = [self serversFromDictionary:_settings[@"settings"][@"servers"]];
    self.suservers  = [self suServersFromDictionary:_settings[@"settings"][@"suservers"]];
    self.tasks      = [self tasksFromDictionary:_settings[@"settings"][@"tasks"]];
    
    return YES;
}

- (NSDictionary *)settingsRevisionsFromServer:(BOOL)useAgentPlist
{
    NSDictionary *data;
    MPHTTPRequest *req;
    MPWSResult *result;
    
    if (useAgentPlist) {
        req = [[MPHTTPRequest alloc] initWithAgentPlist];
    } else {
        req = [[MPHTTPRequest alloc] init];
    }
    
    NSString *urlPath = [@"/api/v1/agent/config/info" stringByAppendingPathComponent:self.ccuid];
    result = [req runSyncGET:urlPath];
    
    if (result.statusCode >= 200 && result.statusCode <= 299) {
        logit(lcl_vInfo,@"Agent Settings data, returned true.");
        data = result.result[@"data"][@"settings"];
    } else {
        logit(lcl_vError,@"Agent Settings data, returned false.");
        logit(lcl_vDebug,@"%@",result.toDictionary);
        return nil;
    }
    
    return data;
}

- (NSDictionary *)allSettingsFromServer:(BOOL)useAgentPlist
{
    NSDictionary *data;
    MPHTTPRequest *req;
    MPWSResult *result;
    
    if (useAgentPlist) {
        logit(lcl_vDebug,@"[MPHTTPRequest] Using Agent Plist");
        req = [[MPHTTPRequest alloc] initWithAgentPlist];
    } else {
        req = [[MPHTTPRequest alloc] init];
    }
    
    NSString *urlPath = [@"/api/v2/agent/config/data" stringByAppendingPathComponent:self.ccuid];
    result = [req runSyncGET:urlPath];
    
    if (result.statusCode >= 200 && result.statusCode <= 299) {
        logit(lcl_vInfo,@"Agent Settings data, returned true.");
        data = result.result[@"data"];
    } else {
        logit(lcl_vError,@"Agent Settings data, returned false.");
        logit(lcl_vDebug,@"%@",result.toDictionary);
        return nil;
    }
    
    return data;
}

- (BOOL)compareAndUpdateSettings:(NSDictionary *)remoteSettingsRevs
{
	[self refresh];
	
    NSDictionary *local = [NSDictionary dictionaryWithContentsOfFile:MP_AGENT_SETTINGS];
    NSDictionary *localRevs = local[@"revs"];
	NSString *localID = self.agent.groupId;
	NSString *remoteID = @"";
	
    if ([localRevs isEqualToDictionary:remoteSettingsRevs])
	{
        qldebug(@"Setting Revisions did match.");
        return YES;
    } else {
        qlinfo(@"Setting Revisions did not match. Updating settings.");
        NSDictionary *remoteSettings = [self allSettingsFromServer:NO];
		
		if (!remoteSettingsRevs[@"id"]) {
			remoteID = remoteSettings[@"settings"][@"agent"][@"data"][@"client_group_id"];
		} else {
			remoteID = remoteSettingsRevs[@"id"];
		}
		
		if (![localID isEqualToString:remoteID])
		{
			// Update all, group id does not match
			qlinfo(@"Client group has been changed. Update all settings.");
			localRevs = @{@"agent":@0,@"servers":@0,@"suservers":@0,@"tasks":@0};
		}
		
        if ([[remoteSettingsRevs objectForKey:@"agent"] intValue] != [[localRevs objectForKey:@"agent"] intValue]) {
            // Usdate Agent Settings
            qlinfo(@"Update Agent Settings, settings did not match.");
            [self updateSettingsUsingKey:@"agent" settings:remoteSettings[@"settings"][@"agent"]];
        }
        if ([remoteSettingsRevs objectForKey:@"servers"] != [localRevs objectForKey:@"servers"]) {
            // Usdate Servers
            qlinfo(@"Update Agent Servers, servers did not match.");
            [self updateSettingsUsingKey:@"servers" settings:remoteSettings[@"settings"][@"servers"]];
        }
        if ([remoteSettingsRevs objectForKey:@"suservers"] != [localRevs objectForKey:@"suservers"]) {
            // Usdate SUServers
            qlinfo(@"Update Agent SUServers, SUServers did not match.");
            [self updateSettingsUsingKey:@"suservers" settings:remoteSettings[@"settings"][@"suservers"]];
        }
        if ([remoteSettingsRevs objectForKey:@"tasks"] != [localRevs objectForKey:@"tasks"]) {
            // Usdate Tasks
            qlinfo(@"Update Agent tasks, tasks did not match.");
            [self updateSettingsUsingKey:@"tasks" settings:remoteSettings[@"settings"][@"tasks"]];
        }
		if ([remoteSettingsRevs objectForKey:@"restrictions"] != [self readSoftwareRestrictionRevisionFromFile]) {
			// Usdate Tasks
			qlinfo(@"Update Software restrictions, restrictions did not match.");
			[self writeNewSoftwareRestritionsFile];
		}
        qlinfo(@"Setting have been updated.");
    }
    
    return YES;
}

- (void)updateSettingsUsingKey:(NSString *)key settings:(NSDictionary *)agentSettings
{
	if (agentSettings)
	{
		NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:MP_AGENT_SETTINGS];
		[dict[@"settings"] setObject:agentSettings forKey:key];
		[dict[@"revs"] setObject:agentSettings[@"rev"] forKey:key];
		[dict writeToFile:MP_AGENT_SETTINGS atomically:YES];
	}
	else
	{
		qlerror(@"Unable to update setting for key \"%@\", value was null.",key);
	}
}

#pragma mark - Private

- (NSString *)clientID
{
    NSString *result = NULL;
    io_struct_inband_t iokit_entry;
    uint32_t bufferSize = 4096; // this signals the longest entry we will take
    io_registry_entry_t ioRegistryRoot = IORegistryEntryFromPath(kIOMasterPortDefault, "IOService:/");
    IORegistryEntryGetProperty(ioRegistryRoot, kIOPlatformUUIDKey, iokit_entry, &bufferSize);
    result = [NSString stringWithCString:iokit_entry encoding:NSASCIIStringEncoding];
    
    IOObjectRelease((unsigned int) iokit_entry);
    IOObjectRelease(ioRegistryRoot);
    
    return result;
}

- (NSString *)clientSerialNumber
{
    NSString *result = nil;
    
    io_registry_entry_t rootEntry = IORegistryEntryFromPath( kIOMasterPortDefault, "IOService:/" );
    CFTypeRef serialAsCFString = NULL;
    
    serialAsCFString = IORegistryEntryCreateCFProperty( rootEntry,
                                                       CFSTR(kIOPlatformSerialNumberKey),
                                                       kCFAllocatorDefault,
                                                       0);
    
    IOObjectRelease( rootEntry );
    if (serialAsCFString == NULL) {
        result = @"NA";
    } else {
        result = [NSString stringWithFormat:@"%@",(__bridge NSString *)serialAsCFString];
        CFRelease(serialAsCFString);
    }
    
    return result;
}

- (void)collectOSInfo
{
    self.osver = @"10.0.0";
    self.ostype = @"Mac OS X";
    
    NSDictionary *results = nil;
    
    NSString *clientVerPath = @"/System/Library/CoreServices/SystemVersion.plist";
    NSString *serverVerPath = @"/System/Library/CoreServices/ServerVersion.plist";
    
    if ([fm fileExistsAtPath:serverVerPath] == TRUE) {
        results = [NSDictionary dictionaryWithContentsOfFile:serverVerPath];
    } else {
        if ([fm fileExistsAtPath:clientVerPath] == TRUE) {
            results = [NSDictionary dictionaryWithContentsOfFile:clientVerPath];
        }
    }
    
    if (results) {
        if ([results objectForKey:@"ProductVersion"]) self.osver = [results objectForKey:@"ProductVersion"];
        if ([results objectForKey:@"ProductName"]) self.ostype = [results objectForKey:@"ProductName"];
    }
}

- (NSDictionary *)settingsRevisionsFromFile
{
    NSDictionary *result = nil;
    if ([fm fileExistsAtPath:MP_AGENT_SETTINGS])
    {
        NSDictionary *_settingsDict = [NSDictionary dictionaryWithContentsOfFile:MP_AGENT_SETTINGS];
        if ([_settingsDict objectForKey:@"revs"]) {
            result = [_settingsDict objectForKey:@"revs"];
        }
    }
    return result;
}

- (NSArray *)serversFromDictionary:(NSDictionary *)settings
{
    NSMutableArray *_srvs = [NSMutableArray new];
    NSArray *_raw_srvs = settings[@"data"];
    
    NSSortDescriptor * descriptor = [[NSSortDescriptor alloc] initWithKey:@"serverType" ascending:YES];
    _raw_srvs = [_raw_srvs sortedArrayUsingDescriptors:@[descriptor]];
    
    for (NSDictionary *_srv in _raw_srvs)
    {
        [_srvs addObject:[[Server alloc] initWithDictionary:_srv]];
    }
    
    return (NSArray *)_srvs;
}

- (NSArray *)suServersFromDictionary:(NSDictionary *)settings
{
    NSMutableArray *_srvs = [NSMutableArray new];
    NSArray *_raw_srvs = settings[@"data"];
    
    NSSortDescriptor * descriptor = [[NSSortDescriptor alloc] initWithKey:@"serverType" ascending:YES];
    _raw_srvs = [_raw_srvs sortedArrayUsingDescriptors:@[descriptor]];
    
    for (NSDictionary *_srv in _raw_srvs)
    {
        [_srvs addObject:[[Suserver alloc] initWithDictionary:_srv]];
    }
    
    return (NSArray *)_srvs;
}

- (NSArray *)tasksFromDictionary:(NSDictionary *)settings
{
    return settings[@"data"];
}

- (NSArray *)randomizeArray:(NSArray *)arrayToRandomize
{
    NSMutableArray *_newArray = [[NSMutableArray alloc] initWithArray:arrayToRandomize];
    NSUInteger count = [_newArray count];
    for (NSUInteger i = 0; i < count; ++i) {
        // Select a random element between i and end of array to swap with.
        NSInteger nElements = count - i;
        NSInteger n = (arc4random() % nElements) + i;
        [_newArray exchangeObjectAtIndex:i withObjectAtIndex:n];
    }
    
    return (NSArray *)_newArray;
}

- (NSString *)readSoftwareRestrictionRevisionFromFile
{
	if (![fm fileExistsAtPath:SW_RESTRICTIONS_PLIST]) return @"0-0";
	
	NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:SW_RESTRICTIONS_PLIST];
	if ([d objectForKey:@"revision"]) {
		return [d objectForKey:@"revision"];
	}
	
	return @"0-0";
}

- (BOOL)writeNewSoftwareRestritionsFile
{
	NSError *err = nil;
	MPRESTfull *mpr = [MPRESTfull new];
	NSDictionary *res = [mpr getSoftwareRestrictions:&err];
	if (err) {
		qlerror(@"%@",err.localizedDescription);
	}
	[res writeToFile:SW_RESTRICTIONS_PLIST atomically:NO];
}
@end
