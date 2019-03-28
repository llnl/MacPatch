//
//  SysInfoNetworkPlugin.m
//  SysInfoNetwork
//
//  Created by Heizer, Charles on 8/31/15.
//  Copyright (c) 2015 Charles Heizer. All rights reserved.
//

#import "SysInfoNetworkPlugin.h"
#import "InventoryPlugin.h"
#import "lcl.h"

//#define kSP_DATA_Dir			@"/private/tmp/.mpData"
#define kSP_DATA_Dir			@"/private/tmp"
#define kPluginPrefs            @"/Library/Preferences/gov.llnl.mp.inv.plugin.plist"

#undef  ql_component
#define ql_component lcl_cMPInventoryPlugin

@implementation SysInfoNetworkPlugin

@synthesize pluginName;
@synthesize pluginVersion;
@synthesize wstype;
@synthesize type;
@synthesize data;

- (id)init
{
    self = [super init];
    if (self) {
        self.wstype = @"MPInvSysInfoGen";
        self.type   = @"MPInvSysInfoGen";
        self.data   = nil;
    }
    
    return self;
}

- (void)setUpLogging
{
    //NSString *_logFile = [NSString stringWithFormat:@"%@/Logs/InventoryPlugin.log",MP_ROOT_CLIENT];
    NSString *_logFile = @"/private/tmp/InventoryPlugin.log";
    [LCLLogFile setPath:_logFile];
    BOOL debugLogging = NO;
    
    // Check for Logging State
    if ([[NSFileManager defaultManager] fileExistsAtPath:kPluginPrefs]) {
        NSDictionary *defaults = [NSDictionary dictionaryWithContentsOfFile:kPluginPrefs];
        if ([defaults objectForKey:@"Debug"]) {
            debugLogging = [[defaults objectForKey:@"Debug"] boolValue];
        }
    }
    
    if (debugLogging) {
        lcl_configure_by_name("*", lcl_vDebug);
        qlinfo(@"***** %@ v.%@ started -- Debug Enabled *****", self.pluginName, self.pluginVersion);
    } else {
        lcl_configure_by_name("*", lcl_vInfo);
        qlinfo(@"***** %@ v.%@ started *****", self.pluginName, self.pluginVersion);
    }
}

- (id)getSysInfoGenDataForType:(NSString *)aType error:(NSError **)error
{
    // SystemProfiler Output file Name
    NSString *spFileName = [kSP_DATA_Dir stringByAppendingPathComponent:@"sysInfoGen.plist"];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    
    BOOL isDir;
    if (([fm fileExistsAtPath:kSP_DATA_Dir isDirectory:&isDir] && isDir) == NO) {
        [fm createDirectoryAtPath:kSP_DATA_Dir withIntermediateDirectories:YES attributes:nil error:NULL];
    }
    
    if (![fm isWritableFileAtPath:kSP_DATA_Dir]) {
        qlerror(@"Temp directory (%@) is not writable. Inventory will no get processed properly.",kSP_DATA_Dir);
    }
    
    // If File Exists then delete it
    if ([fm fileExistsAtPath:spFileName isDirectory:NO]) [fm removeItemAtPath:spFileName error:NULL];
    
    qlinfo(@"Begin running sysinfocachegen to collect data.");
    
    NSTask *task;
    task = [[NSTask alloc] init];
    [task setLaunchPath:@"/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Support/sysinfocachegen"];
    
    NSArray *arguments;
    arguments = [NSArray arrayWithObjects:@"-p",spFileName,nil];
    [task setArguments: arguments];
    
    NSPipe *pipe;
    pipe = [NSPipe pipe];
    [task setStandardOutput: pipe];
    
    NSFileHandle *file;
    file = [pipe fileHandleForReading];
    
    [task launch];
    
    NSData *tData;
    tData = [file readDataToEndOfFile];
    
    NSString *string;
    string = [[NSString alloc] initWithData:tData encoding: NSUTF8StringEncoding];
    qlinfo(@"Completed running sysinfocachegen, %@",string);
    
    NSLog(@"Writing result to %@",spFileName);
    NSDictionary *ddata = [NSDictionary dictionaryWithContentsOfFile:spFileName];
    if ([ddata objectForKey:@"Objects"]) {
        if ([[ddata objectForKey:@"Objects"] objectForKey:aType]) {
            qldebug(@"sysinfocachegen collected data: %@",ddata);
            return [[ddata objectForKey:@"Objects"] objectForKey:aType];
        } else {
            qlerror(@"%@ was not found in Objects",aType);
        }
    } else {
        qlerror(@"Objects object was not found sys info data.");
        return nil;
    }
    
    return nil;
}

- (NSArray *)parseSysInfoNetworkData:(NSArray *)networkData
{
    qlinfo(@"Parsing sysinfocachegen results data.");
    
    NSArray *netKeys = [NSArray arrayWithObjects:@"HardwareAddress",@"IsPrimary",@"InterfaceName",@"PrimaryIPAddress",
                        @"ConfigurationType",@"AllDNSServers",@"PrimaryDNSServer",@"IsActive",@"RouterAddress",
                        @"ConfigurationName",@"DomainName",@"AllIPAddresses", nil];
    
    NSMutableDictionary *netDict = [[NSMutableDictionary alloc] init];
    for (NSString *key in netKeys) {
        [netDict setObject:@"NA" forKey:key];
    }
    
    NSDictionary *item;
    NSMutableDictionary *result;
    NSMutableArray *items = [[NSMutableArray alloc] init];
    for (int i = 0; i < [networkData count]; i++)
    {
        item = [networkData objectAtIndex:i];
        result = [[NSMutableDictionary alloc] initWithDictionary:netDict];
        for (NSString *akey in netKeys)
        {
            if ([item objectForKey:akey]) {
                if ([[item objectForKey:akey] isKindOfClass:[NSNumber class]]) {
                    [result setObject:[[item objectForKey:akey] stringValue] forKey:akey];
                }
                if ([[item objectForKey:akey] isKindOfClass:[NSString class]]) {
                    [result setObject:[item objectForKey:akey] forKey:akey];
                }
            }
        }
        [items addObject:result];
    }
    
    qldebug(@"Parsed sysinfocachegen data: %@",items);
    return [NSArray arrayWithArray:items];
}

- (void)collectData
{
    NSArray *networkDataArray = [self getSysInfoGenDataForType:@"Mac_NetworkInterfaceElement" error:NULL];
    NSArray *result = [self parseSysInfoNetworkData:networkDataArray];
    self.data = result;
}

#define mark - Required Protocol Methods

- (NSString *)pluginKey
{
    return @"None";
}

- (NSDictionary *)runInventoryCollection
{
    [self setUpLogging];
    [self collectData];
    return @{ @"type":self.type, @"wstype":self.wstype , @"data":self.data };
}

@end
