//
//  AgentVC.m
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

#import "AgentVC.h"
#import <WebKit/WebKit.h>

@interface AgentVC ()
{
    NSDictionary *settings;
}

@property (weak) IBOutlet NSOutlineView *outlineView;

// XPC Connection
@property (atomic, strong, readwrite) NSXPCConnection *workerConnection;

- (void)connectToHelperTool;
- (void)connectAndExecuteCommandBlock:(void(^)(NSError *))commandBlock;

@end

@implementation AgentVC
{
	NSMutableDictionary *outlineViewData;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    NSDictionary *data = [NSDictionary dictionaryWithContentsOfFile:MP_AGENT_SETTINGS];
    settings = data[@"settings"];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self showAgent:nil];
    });
}

- (IBAction)showAgent:(id)sender
{
	NSDictionary *agent = settings[@"agent"][@"data"];
	NSMutableString *htmlData = [NSMutableString new];
	
	NSArray *sortedKeys = [[agent allKeys] sortedArrayUsingSelector: @selector(compare:)];
	for (NSString *key in sortedKeys)
	{
		if ([agent[key] isEqualToString:@"0"] || [agent[key] isEqualToString:@"1"]) {
			NSString *res = [agent[key] isEqualToString:@"0"] ? @"True" : @"False";
			[htmlData appendFormat:@"<dt>%@:</dt><dd>%@</dd>",[[key stringByReplacingOccurrencesOfString:@"_" withString:@" "] capitalizedString], res ];
		} else {
			[htmlData appendFormat:@"<dt>%@:</dt><dd>%@</dd>",[[key stringByReplacingOccurrencesOfString:@"_" withString:@" "] capitalizedString], agent[key] ];
		}
		
		
	}
	
	NSString *filePath = [[NSBundle mainBundle] pathForResource:@"agent" ofType:@"html" inDirectory:@"html"];
	
	NSString *htmlStringBase = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:NULL];
	NSString *htmlString = [htmlStringBase stringByReplacingOccurrencesOfString:@"[DATA]" withString:htmlData];
	
	[_wkWebView loadHTMLString:htmlString baseURL:[[NSBundle mainBundle] resourceURL]];
}

- (IBAction)showServers:(id)sender
{
	NSArray *servers = settings[@"servers"][@"data"];
	NSArray *serversKeys = [[servers objectAtIndex:0] allKeys];
	NSArray *visKeys = @[@"host",@"port"];
	
	NSMutableString *htmlData = [NSMutableString new];
	[htmlData appendString:@"columns: ["];
	for (NSString *key in serversKeys)
	{
		if ([visKeys containsObject:key]) {
			[htmlData appendFormat:@"{field: '%@', title: '%@', visible: true,},",key, key ];
		} else {
			[htmlData appendFormat:@"{field: '%@', title: '%@', visible: false,},",key, key ];
		}
		
	}
	[htmlData appendString:@"], data: ["];
	for (NSDictionary *server in servers)
	{
		[htmlData appendString:@"{"];
		for (NSString *key in serversKeys)
		{
			[htmlData appendFormat:@"%@: '%@',",key, server[key] ];
		}
		[htmlData appendString:@"},"];
	}
	[htmlData appendString:@"],"];
	
	NSString* filePath = [[NSBundle mainBundle] pathForResource:@"servers" ofType:@"html" inDirectory:@"html"];
	NSString *htmlStringBase = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:NULL];
	NSString *htmlString = [htmlStringBase stringByReplacingOccurrencesOfString:@"[JSON]" withString:htmlData];
	htmlString = [htmlString stringByReplacingOccurrencesOfString:@"[TITLE]" withString:@"Agent Servers"];
	
	[_wkWebView loadHTMLString:htmlString baseURL:[[NSBundle mainBundle] resourceURL]];
}

- (IBAction)showSUServers:(id)sender
{
	NSMutableString *htmlData = [NSMutableString new];
	NSArray *servers = settings[@"suservers"][@"data"];
	if (servers.count <= 0)
	{
		[htmlData appendString:@"columns: [],"];
	}
	else
	{
		NSArray *serversKeys = [[servers objectAtIndex:0] allKeys];
		NSArray *visKeys = @[@"CatalogURL",@"serverType"];
		
		
		[htmlData appendString:@"columns: ["];
		for (NSString *key in serversKeys)
		{
			if ([visKeys containsObject:key]) {
				[htmlData appendFormat:@"{field: '%@', title: '%@', visible: true,},",key, key ];
			} else {
				[htmlData appendFormat:@"{field: '%@', title: '%@', visible: false,},",key, key ];
			}
			
		}
		[htmlData appendString:@"], data: ["];
		for (NSDictionary *server in servers)
		{
			[htmlData appendString:@"{"];
			for (NSString *key in serversKeys)
			{
				[htmlData appendFormat:@"%@: '%@',",key, server[key] ];
			}
			[htmlData appendString:@"},"];
		}
		[htmlData appendString:@"],"];
	}
	NSString* filePath = [[NSBundle mainBundle] pathForResource:@"servers" ofType:@"html" inDirectory:@"html"];
	NSString *htmlStringBase = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:NULL];
	NSString *htmlString = [htmlStringBase stringByReplacingOccurrencesOfString:@"[JSON]" withString:htmlData];
	htmlString = [htmlString stringByReplacingOccurrencesOfString:@"[TITLE]" withString:@"SoftwareUpdate Servers"];
	
	[_wkWebView loadHTMLString:htmlString baseURL:[[NSBundle mainBundle] resourceURL]];
}

- (IBAction)showTasks:(id)sender
{
	NSArray *tasks = settings[@"tasks"][@"data"];
	NSArray *taskKeys = [[tasks objectAtIndex:0] allKeys];
	NSArray *visKeys = @[@"cmd",@"name",@"interval"];
	
	NSMutableString *htmlData = [NSMutableString new];
	[htmlData appendString:@"columns: ["];
	for (NSString *key in taskKeys)
	{
		if ([visKeys containsObject:key]) {
			[htmlData appendFormat:@"{field: '%@', title: '%@', visible: true,},",key, key ];
		} else {
			[htmlData appendFormat:@"{field: '%@', title: '%@', visible: false,},",key, key ];
		}
		
	}
	[htmlData appendString:@"], data: ["];
	for (NSDictionary *task in tasks)
	{
		[htmlData appendString:@"{"];
		for (NSString *key in taskKeys)
		{
			[htmlData appendFormat:@"%@: '%@',",key, task[key] ];
		}
		[htmlData appendString:@"},"];
	}
	[htmlData appendString:@"],"];
	
	NSString* filePath = [[NSBundle mainBundle] pathForResource:@"tasks" ofType:@"html" inDirectory:@"html"];
	NSString *htmlStringBase = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:NULL];
	NSString *htmlString = [htmlStringBase stringByReplacingOccurrencesOfString:@"[JSON]" withString:htmlData];
	
	[_wkWebView loadHTMLString:htmlString baseURL:[[NSBundle mainBundle] resourceURL]];
}

- (IBAction)showClientID:(id)sender
{
	MPSettings *mps = [MPSettings sharedInstance];
	[mps refresh];
	
	NSString *htmlData = [NSString stringWithFormat:@"<h5>%@</h5>",mps.ccuid];
	NSString *filePath = [[NSBundle mainBundle] pathForResource:@"data" ofType:@"html" inDirectory:@"html"];
	NSString *htmlStringBase = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:NULL];
	NSString *htmlString = [htmlStringBase stringByReplacingOccurrencesOfString:@"[TITLE]" withString:@"Client ID"];
	htmlString = [htmlString stringByReplacingOccurrencesOfString:@"[DATA]" withString:htmlData];
	
	[_wkWebView loadHTMLString:htmlString baseURL:[[NSBundle mainBundle] resourceURL]];
	
}

- (IBAction)showSerialNo:(id)sender
{
	MPSettings *mps = [MPSettings sharedInstance];
	[mps refresh];
	
	NSString *htmlData = [NSString stringWithFormat:@"<h5>%@</h5>",mps.serialno];
	NSString *filePath = [[NSBundle mainBundle] pathForResource:@"data" ofType:@"html" inDirectory:@"html"];
	NSString *htmlStringBase = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:NULL];
	NSString *htmlString = [htmlStringBase stringByReplacingOccurrencesOfString:@"[TITLE]" withString:@"Serial Number"];
	htmlString = [htmlString stringByReplacingOccurrencesOfString:@"[DATA]" withString:htmlData];
	
	[_wkWebView loadHTMLString:htmlString baseURL:[[NSBundle mainBundle] resourceURL]];
	
}

- (IBAction)showFileVaultStatus:(id)sender
{
	MPNSTask *task = [[MPNSTask alloc] init];
	NSError *err = nil;
	NSString *res = [task runTask:@"/usr/bin/fdesetup" binArgs:@[@"status",@"--verbose"] error:&err];
	if (err) {
		qlerror(@"%@",err.localizedDescription);
	}
	
	BOOL status = NO;
	NSString *dev = @"";
	NSArray *lines = [[NSArray alloc] initWithArray:[res componentsSeparatedByString:@"\n"]];
	for (NSString *l in lines)
	{
		if ([l containsString:@"fdesetup: "]) {
			dev = [l stringByReplacingOccurrencesOfString:@"fdesetup: device path = " withString:@""];
		}
		
		if ([l containsString:@"FileVault is On"]) {
			status = YES;
		}
	}
	
	NSString *fvStatus;
	if (status)
	{
		if ([dev isEqualToString:@""]) {
			fvStatus = [NSString stringWithFormat:@"FileVault is on."];
		} else {
			fvStatus = [NSString stringWithFormat:@"FileVault is on for %@",dev];
		}
	}
	else
	{
		fvStatus = @"FileVault is Off.";
	}
	
	NSString *htmlData = [NSString stringWithFormat:@"<h5>%@</h5>",fvStatus];
	NSString *filePath = [[NSBundle mainBundle] pathForResource:@"data" ofType:@"html" inDirectory:@"html"];
	NSString *htmlStringBase = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:NULL];
	NSString *htmlString = [htmlStringBase stringByReplacingOccurrencesOfString:@"[TITLE]" withString:@"FileVault Status"];
	htmlString = [htmlString stringByReplacingOccurrencesOfString:@"[DATA]" withString:htmlData];
	
	[_wkWebView loadHTMLString:htmlString baseURL:[[NSBundle mainBundle] resourceURL]];
	
}

- (IBAction)showNetworkInfo:(id)sender
{
	MPNSTask *task = [[MPNSTask alloc] init];
	NSError *err = nil;
	NSString *res = [task runTask:@"/usr/sbin/system_profiler" binArgs:@[@"SPNetworkDataType",@" -detailLevel", @"basic"] error:&err];
	if (err) {
		qlerror(@"%@",err.localizedDescription);
	}
	
	NSString *htmlData = [NSString stringWithFormat:@"<pre>%@</pre>",res];
	NSString *filePath = [[NSBundle mainBundle] pathForResource:@"datapre" ofType:@"html" inDirectory:@"html"];
	NSString *htmlStringBase = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:NULL];
	NSString *htmlString = [htmlStringBase stringByReplacingOccurrencesOfString:@"[TITLE]" withString:@"Network Info"];
	htmlString = [htmlString stringByReplacingOccurrencesOfString:@"[DATA]" withString:htmlData];
	
	[_wkWebView loadHTMLString:htmlString baseURL:[[NSBundle mainBundle] resourceURL]];
}

- (IBAction)showOSProfiles:(id)sender
{
	[self connectAndExecuteCommandBlock:^(NSError * connectError) {
		if (connectError != nil) {
			qlerror(@"connectError: %@",connectError);
		} else {
			[[self.workerConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
				qlerror(@"proxyError: %@",proxyError);
			}] getInstalledConfigProfilesWithReply:^(NSString * _Nullable aString, NSData * _Nullable aProfilesData) {
				
				if (!aProfilesData) {
					return;
				}
				
				NSArray *profiles = [NSKeyedUnarchiver unarchiveObjectWithData:aProfilesData];
				NSArray *proKeys = @[@"displayName",@"version",@"installDate"];
				NSArray *proTitles = @[@"Name",@"Version",@"Install Date"];
				
				NSMutableString *htmlData = [NSMutableString new];
				[htmlData appendString:@"columns: ["];
				for (int i=0; i < proKeys.count; i++)
				{
					[htmlData appendFormat:@"{field: '%@', title: '%@', visible: true},",proKeys[i], proTitles[i] ];
				}
				[htmlData appendFormat:@"{field: 'payload', title: 'Payload', visible: false, escape: true},"];
				[htmlData appendString:@"], data: ["];
				for (ConfigProfile *p in profiles)
				{
					[htmlData appendString:@"{"];
					for (NSString *key in proKeys)
					{
						if ([key isEqualToString:@"displayName"]) {
							[htmlData appendFormat:@"%@: '%@',",key, p.displayName ];
						} else if ([key isEqualToString:@"version"]) {
							[htmlData appendFormat:@"%@: '%@',",key, p.version ];
						} else if ([key isEqualToString:@"installDate"]) {
							[htmlData appendFormat:@"%@: '%@',",key, p.installDate ];
						}
					}
					[htmlData appendString:@"},"];
				}
				[htmlData appendString:@"],"];
				
				NSString *filePath = [[NSBundle mainBundle] pathForResource:@"profiles" ofType:@"html" inDirectory:@"html"];
				NSString *htmlStringBase = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:NULL];
				NSString *htmlString = [htmlStringBase stringByReplacingOccurrencesOfString:@"[JSON]" withString:htmlData];
				
				[htmlString writeToFile:@"/tmp/foo.html" atomically:NO encoding:NSUTF8StringEncoding error:NULL];
				
				dispatch_async(dispatch_get_main_queue(), ^{
					[self->_wkWebView loadHTMLString:htmlString baseURL:[[NSBundle mainBundle] resourceURL]];
				});
				
			}];
		}
	}];

}

#pragma mark - Helper

- (void)connectToHelperTool
// Ensures that we're connected to our helper tool.
{
	//assert([NSThread isMainThread]);
	if (self.workerConnection == nil) {
		self.workerConnection = [[NSXPCConnection alloc] initWithMachServiceName:kHelperServiceName options:NSXPCConnectionPrivileged];
		self.workerConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(MPHelperProtocol)];
		
		// Register Progress Messeges From Helper
		self.workerConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(MPHelperProgress)];
		self.workerConnection.exportedObject = self;
		
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
		// We can ignore the retain cycle warning because a) the retain taken by the
		// invalidation handler block is released by us setting it to nil when the block
		// actually runs, and b) the retain taken by the block passed to -addOperationWithBlock:
		// will be released when that operation completes and the operation itself is deallocated
		// (notably self does not have a reference to the NSBlockOperation).
		self.workerConnection.invalidationHandler = ^{
			// If the connection gets invalidated then, on the main thread, nil out our
			// reference to it.  This ensures that we attempt to rebuild it the next time around.
			self.workerConnection.invalidationHandler = nil;
			[[NSOperationQueue mainQueue] addOperationWithBlock:^{
				self.workerConnection = nil;
			}];
		};
#pragma clang diagnostic pop
		[self.workerConnection resume];
	}
}

- (void)connectAndExecuteCommandBlock:(void(^)(NSError *))commandBlock
// Connects to the helper tool and then executes the supplied command block on the
// main thread, passing it an error indicating if the connection was successful.
{
	//assert([NSThread isMainThread]);
	
	// Ensure that there's a helper tool connection in place.
	self.workerConnection = nil;
	[self connectToHelperTool];
	
	commandBlock(nil);
}

#pragma mark - MPHelperProgress protocol

- (void)postStatus:(NSString *)status type:(MPPostDataType)type
{
	// NSLog(@"status: %@",status);
}
@end
