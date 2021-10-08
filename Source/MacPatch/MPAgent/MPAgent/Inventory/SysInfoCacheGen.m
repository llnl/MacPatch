//
//  SysInfoCacheGen.m
//  MPAgent
//
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

#import "SysInfoCacheGen.h"
#import "MacPatch.h"

#define kDefault_DATA_Dir			@"/private/tmp"

@interface SysInfoCacheGen ()
{
	NSFileManager *fm;
}

@property (nonatomic, strong) NSString *dataDir;
@property (nonatomic, strong) NSDictionary *sysData;

- (NSDictionary *)getSysInfoGenData:(NSError **)error;

@end

@implementation SysInfoCacheGen

@synthesize dataDir;
@synthesize sysData;

- (id)init
{
	self = [super init];
	if (self)
	{
		fm = [NSFileManager defaultManager];
		
		NSError *err = nil;
		dataDir = [self genTempDir:&err];
		if (err) dataDir = kDefault_DATA_Dir;
		
		err = nil;
		sysData = [self getSysInfoGenData:&err];
		if (err)
		{
			qlerror(@"Error getting SysInfoGenData. %@",err.localizedDescription);
		}
	}
	
	return self;
}

#pragma mark - Public

- (NSArray *)getNetworkData:(NSError **)error
{
	if (!sysData) {
		qlerror(@"Can not get network data. Data is nil.");
		NSError *err = [NSError errorWithDomain:@"gov.llnl.mp.sysinfocachegen" code:1001 userInfo:@{@"Error reason": @"Data is nil."}];
		if (error != NULL) *error = err;
		return [NSArray array];
	}
	
	if (!sysData[@"Mac_NetworkInterfaceElement"])
	{
		qlerror(@"Mac_NetworkInterfaceElement was not found.");
		NSError *err = [NSError errorWithDomain:@"gov.llnl.mp.sysinfocachegen" code:1002 userInfo:@{@"Error reason": @"Mac_NetworkInterfaceElement is nil."}];
		if (error != NULL) *error = err;
		return [NSArray array];
	}
	
	NSArray *networkDataArray = sysData[@"Mac_NetworkInterfaceElement"];
	
	// Parse results
	NSArray *netKeys = @[@"HardwareAddress",@"IsPrimary",@"InterfaceName",@"PrimaryIPAddress",
						@"ConfigurationType",@"AllDNSServers",@"PrimaryDNSServer",@"IsActive",@"RouterAddress",
						@"ConfigurationName",@"DomainName",@"AllIPAddresses"];
	
	NSMutableDictionary *netDict = [NSMutableDictionary new];
	for (NSString *key in netKeys) {
		[netDict setObject:@"NA" forKey:key];
	}
	
	NSMutableDictionary *result;
	NSMutableArray *items = [NSMutableArray new];
	
	for (NSDictionary *d in networkDataArray)
	{
		result = [[NSMutableDictionary alloc] initWithDictionary:netDict];
		for (NSString *k in netKeys)
		{
			if (d[k])
			{
				if ([d[k] isKindOfClass:[NSNumber class]])
				{
					[result setObject:[d[k] stringValue] forKey:k];
				}
				if ([d[k] isKindOfClass:[NSString class]])
				{
					[result setObject:d[k] forKey:k];
				}
			}
		}
		[items addObject:result];
	}
	
	qldebug(@"Parsed sysinfocachegen data: %@",items);
	return [NSArray arrayWithArray:items];
}

- (NSArray *)getHardDriveData:(NSError **)error
{
	if (!sysData) {
		qlerror(@"Can not get hard drive data. Data is nil.");
		NSError *err = [NSError errorWithDomain:@"gov.llnl.mp.sysinfocachegen" code:1001 userInfo:@{@"Error reason": @"Data is nil."}];
		if (error != NULL) *error = err;
		return [NSArray array];
	}
	
	if (!sysData[@"Mac_HardDriveElement"])
	{
		qlerror(@"Mac_HardDriveElement was not found.");
		NSError *err = [NSError errorWithDomain:@"gov.llnl.mp.sysinfocachegen" code:1002 userInfo:@{@"Error reason": @"Mac_HardDriveElement is nil."}];
		if (error != NULL) *error = err;
		return [NSArray array];
	}
	
	NSArray *dataArray = sysData[@"Mac_HardDriveElement"];
	
	NSMutableDictionary *result;
	NSMutableArray *items = [NSMutableArray new];
	
	for (NSDictionary *d in dataArray)
	{
		result = [[NSMutableDictionary alloc] initWithDictionary:d];
		for (NSString *k in result.allKeys)
		{
			if (d[k])
			{
				if ([d[k] isKindOfClass:[NSNumber class]])
				{
					[result setObject:[d[k] stringValue] forKey:k];
				}
				if ([d[k] isKindOfClass:[NSDate class]])
				{
					[result setObject:d[k] forKey:k];
				}
				else if ([d[k] boolValue])
				{
					BOOL _value = [d[k] boolValue];
					NSString *_strVal = _value ? @"YES" : @"NO";
					[result setObject:_strVal forKey:k];
				}
				else
				{
					[result setObject:d[k] forKey:k];
				}
			}
		}
		[items addObject:result];
	}
	return [NSArray arrayWithArray:items];
}
					 
- (NSArray *)getRAMData:(NSError **)error
{
	if (!sysData) {
		qlerror(@"Can not get RAM data. Data is nil.");
		NSError *err = [NSError errorWithDomain:@"gov.llnl.mp.sysinfocachegen" code:1001 userInfo:@{@"Error reason": @"Data is nil."}];
		if (error != NULL) *error = err;
		return [NSArray array];
	}
	
	if (!sysData[@"Mac_RAMSlotElement"])
	{
		qlerror(@"Mac_RAMSlotElement was not found.");
		NSError *err = [NSError errorWithDomain:@"gov.llnl.mp.sysinfocachegen" code:1002 userInfo:@{@"Error reason": @"Mac_RAMSlotElement is nil."}];
		if (error != NULL) *error = err;
		return [NSArray array];
	}
	
	NSArray *dataArray = sysData[@"Mac_RAMSlotElement"];
	
	NSMutableDictionary *result;
	NSMutableArray *items = [NSMutableArray new];
	
	for (NSDictionary *d in dataArray)
	{
		result = [[NSMutableDictionary alloc] initWithDictionary:d];
		for (NSString *k in result.allKeys)
		{
			if (d[k])
			{
				if ([d[k] isKindOfClass:[NSNumber class]])
				{
					[result setObject:[d[k] stringValue] forKey:k];
				}
				else if ([d[k] boolValue])
				{
					BOOL _value = [d[k] boolValue];
					NSString *_strVal = _value ? @"YES" : @"NO";
					[result setObject:_strVal forKey:k];
				}
				else
				{
					[result setObject:d[k] forKey:k];
				}
			}
		}
		[items addObject:result];
	}
	return [NSArray arrayWithArray:items];
}

- (NSArray *)getPCIData:(NSError **)error
{
	if (!sysData) {
		qlerror(@"Can not get PCI data. Data is nil.");
		NSError *err = [NSError errorWithDomain:@"gov.llnl.mp.sysinfocachegen" code:1001 userInfo:@{@"Error reason": @"Data is nil."}];
		if (error != NULL) *error = err;
		return [NSArray array];
	}
	
	if (!sysData[@"Mac_PCIBusElement"])
	{
		qlerror(@"Mac_PCIBusElement was not found.");
		NSError *err = [NSError errorWithDomain:@"gov.llnl.mp.sysinfocachegen" code:1002 userInfo:@{@"Error reason": @"Mac_PCIBusElement is nil."}];
		if (error != NULL) *error = err;
		return [NSArray array];
	}
	
	
	
	NSMutableDictionary *result;
	NSMutableArray *items = [NSMutableArray new];
	id pciData = sysData[@"Mac_PCIBusElement"];
	@try
	{
		if ([pciData isKindOfClass:[NSArray class]])
		{
			for (NSDictionary *d in pciData)
			{
				result = [[NSMutableDictionary alloc] initWithDictionary:d];
				for (NSString *k in result.allKeys)
				{
					if (d[k])
					{
						if ([d[k] isKindOfClass:[NSNumber class]])
						{
							[result setObject:[d[k] stringValue] forKey:k];
						}
						else if ([d[k] boolValue])
						{
							BOOL _value = [d[k] boolValue];
							NSString *_strVal = _value ? @"YES" : @"NO";
							[result setObject:_strVal forKey:k];
						}
						else
						{
							[result setObject:d[k] forKey:k];
						}
					}
				}
				[items addObject:result];
			}
		}
		else if ([pciData isKindOfClass:[NSArray class]])
		{
			result = [[NSMutableDictionary alloc] initWithDictionary:pciData];
			for (NSString *k in result.allKeys)
			{
				if (pciData[k])
				{
					if ([pciData[k] isKindOfClass:[NSNumber class]])
					{
						[result setObject:[pciData[k] stringValue] forKey:k];
					}
					else if ([pciData[k] boolValue])
					{
						BOOL _value = [pciData[k] boolValue];
						NSString *_strVal = _value ? @"YES" : @"NO";
						[result setObject:_strVal forKey:k];
					}
					else
					{
						[result setObject:pciData[k] forKey:k];
					}
				}
			}
			[items addObject:result];
		}
		return [NSArray arrayWithArray:items];
	} @catch (NSException *exception) {
		qlerror(@"%@",exception);
		qlerror(@"Mac_PCIBusElement: %@",sysData[@"Mac_PCIBusElement"]);
	}
	
	return (NSArray*)items;
}

- (NSArray *)getUSBData:(NSError **)error
{
	if (!sysData) {
		qlerror(@"Can not get USB data. Data is nil.");
		NSError *err = [NSError errorWithDomain:@"gov.llnl.mp.sysinfocachegen" code:1001 userInfo:@{@"Error reason": @"Data is nil."}];
		if (error != NULL) *error = err;
		return [NSArray array];
	}
	
	if (!sysData[@"Mac_USBDeviceElement"])
	{
		qlerror(@"Mac_USBDeviceElement was not found.");
		NSError *err = [NSError errorWithDomain:@"gov.llnl.mp.sysinfocachegen" code:1002 userInfo:@{@"Error reason": @"Mac_USBDeviceElement is nil."}];
		if (error != NULL) *error = err;
		return [NSArray array];
	}
	
	NSArray *dataArray = sysData[@"Mac_USBDeviceElement"];
	
	NSMutableDictionary *result;
	NSMutableArray *items = [NSMutableArray new];
	
	for (NSDictionary *d in dataArray)
	{
		result = [[NSMutableDictionary alloc] initWithDictionary:d];
		for (NSString *k in result.allKeys)
		{
			if (d[k])
			{
				if ([d[k] isKindOfClass:[NSNumber class]])
				{
					[result setObject:[d[k] stringValue] forKey:k];
				}
				else if ([d[k] boolValue])
				{
					BOOL _value = [d[k] boolValue];
					NSString *_strVal = _value ? @"YES" : @"NO";
					[result setObject:_strVal forKey:k];
				}
				else
				{
					[result setObject:d[k] forKey:k];
				}
			}
		}
		[items addObject:result];
	}
	return [NSArray arrayWithArray:items];
}


#pragma mark - Private

- (NSDictionary *)getSysInfoGenData:(NSError **)error
{
	// SystemProfiler Output file Name
	NSString *spFileName = [dataDir stringByAppendingPathComponent:@"sysInfoGen.plist"];
	
	BOOL isDir;
	if (([fm fileExistsAtPath:dataDir isDirectory:&isDir] && isDir) == NO)
	{
		[fm createDirectoryAtPath:dataDir withIntermediateDirectories:YES attributes:nil error:NULL];
	}
	
	if (![fm isWritableFileAtPath:dataDir]) {
		qlerror(@"Temp directory (%@) is not writable. Inventory will no get processed properly.",dataDir);
	}
	
	// If File Exists then delete it
	if (([fm fileExistsAtPath:spFileName isDirectory:&isDir] && isDir) == NO) [fm removeItemAtPath:spFileName error:NULL];
	
	qlinfo(@"Begin running sysinfocachegen to collect data.");
	
	NSTask *task;
	task = [[NSTask alloc] init];
	[task setLaunchPath:@"/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Support/sysinfocachegen"];
	
	NSArray *arguments = @[@"-p",spFileName];
	[task setArguments: arguments];
	
	NSPipe *pipe = [NSPipe pipe];
	[task setStandardOutput: pipe];
	
	NSFileHandle *file = [pipe fileHandleForReading];
	
	[task launch];
	
	NSData *tData;
	tData = [file readDataToEndOfFile];
	
	NSString *string;
	string = [[NSString alloc] initWithData:tData encoding: NSUTF8StringEncoding];
	qlinfo(@"Completed running sysinfocachegen, %@",string);

	NSDictionary *ddata = [NSDictionary dictionaryWithContentsOfFile:spFileName];
	if (ddata[@"Objects"])
	{
		return ddata[@"Objects"];
	}
	else
	{
		qlerror(@"Objects object was not found sys info data.");
		return nil;
	}
	
	return nil;
}

- (NSString *)genTempDir:(NSError **)error
{
	NSString *tempDirectoryTemplate = [NSTemporaryDirectory() stringByAppendingPathComponent:@"SysInfoCacheGen.XXXXXX"];
	const char *tempDirectoryTemplateCString = [tempDirectoryTemplate fileSystemRepresentation];
	char *tempDirectoryNameCString = (char *)malloc(strlen(tempDirectoryTemplateCString) + 1);
	strcpy(tempDirectoryNameCString, tempDirectoryTemplateCString);
	
	char *result = mkdtemp(tempDirectoryNameCString);
	if (!result)
	{
		// handle directory creation failure
		qlerror(@"Error, unable to create temporary directory string.");
	}
	
	NSString *tempDirectoryPath = [fm stringWithFileSystemRepresentation:tempDirectoryNameCString length:strlen(result)];
	NSError *dirErr = nil;
	[fm createDirectoryAtPath:tempDirectoryPath withIntermediateDirectories:YES attributes:NULL error:&dirErr];
	if (dirErr) {
		qlerror(@"Error creating temporary directory %@",tempDirectoryPath);
		if (error != NULL) *error = dirErr;
	}
	
	free(tempDirectoryNameCString);
	return tempDirectoryPath;
}

@end
