//
//  MinScanAndPatchVC.m
//  MPLoginAgent
//
/*
 Copyright (c) 2018, Lawrence Livermore National Security, LLC.
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

#import "MinScanAndPatchVC.h"
#import "MacPatch.h"
#include <unistd.h>
#include <sys/reboot.h>

#import <CoreServices/CoreServices.h>

#undef  ql_component
#define ql_component lcl_cMain

#define	BUNDLE_ID       @"gov.llnl.MPLoginAgent"

extern OSStatus MDSendAppleEventToSystemProcess(AEEventID eventToSend);

@interface MinScanAndPatchVC ()
{
    MPSettings *settings;
}

// Main
- (void)scanAndPatch;
- (void)scanAndPatchThread;
- (void)countDownToClose;
- (void)rebootOrLogout:(int)action;
- (void)toggleStatusProgress;

// Misc
- (void)progress:(NSString *)text,...;

// Web Service
- (void)postInstallToWebService:(NSString *)aPatch type:(NSString *)aType;

// XPC Connection
@property (atomic, strong, readwrite) NSXPCConnection *workerConnection;

- (void)connectToHelperTool;
- (void)connectAndExecuteCommandBlock:(void(^)(NSError *))commandBlock;
@end

@implementation MinScanAndPatchVC

@synthesize taskThread;
@synthesize killTaskThread;
@synthesize cancelTask;

- (void)awakeFromNib
{
    static BOOL alreadyInit = NO;
    
    if (!alreadyInit)
    {
        alreadyInit = YES;
        
        fm = [NSFileManager defaultManager];
        settings = [MPSettings sharedInstance];
        cancelTask = FALSE;
        
        [self->progressBar  setUsesThreadedAnimation: YES];
        
        dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0);
        dispatch_queue_t main = dispatch_get_main_queue();
        
        dispatch_async(queue, ^{
            dispatch_async(main, ^{
                [self scanAndPatch];
            });
        });
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do view setup here.
}

#pragma mark - Main

- (void)scanAndPatch
{
    [progressText setHidden:NO];
    [progressText setStringValue:@""];
    [progressCountText setHidden:NO];
    [progressCountText setStringValue:@""];
    [self->progressBar  setHidden:YES];
    [self->progressBar  stopAnimation:nil];
    
    killTaskThread = NO;
    
    if (taskThread != nil) {
        taskThread = nil;
    }
    
    taskThread = [[NSThread alloc] initWithTarget:self selector:@selector(scanAndPatchThread) object:nil];
    [taskThread start];
}

- (void)scanAndPatchThread
{
	@autoreleasepool
	{
		[self toggleStatusProgress];
		[NSThread sleepForTimeInterval:2];
		[NSApp activateIgnoringOtherApps:YES];
		
		NSArray *approvedUpdates = [NSArray array];
	
		// Scan for Apple Patches
		[self progress:@"Scanning for patches..."];
		if (cancelTask) [self _stopThread];
		MPPatching *patching = [MPPatching new];
		patching.delegate = self;
		
		// Scan host for patches
		approvedUpdates = [patching scanForPatchesUsingTypeFilter:kAllPatches forceRun:YES];
		qlinfo(@"approvedUpdates: %@",approvedUpdates);
		if (approvedUpdates.count <= 0)
		{
			[self progress:@"No patches found..."];
			[self toggleStatusProgress];
			[self rebootOrLogout:1]; // Exit app, no reboot.
			return;
		}
		
		// Sort approved pacthes by install weight
		NSMutableArray *approvedUpdatesArray = [[NSMutableArray alloc] initWithArray:approvedUpdates];
		NSSortDescriptor *desc = [NSSortDescriptor sortDescriptorWithKey:@"patch_install_weight" ascending:YES];
		[approvedUpdatesArray sortUsingDescriptors:[NSArray arrayWithObject:desc]];
		approvedUpdates = [approvedUpdatesArray copy];
		
		// Install required patches
		dispatch_async(dispatch_get_main_queue(), ^(void)
		{
			[self->progressBar  setIndeterminate:NO];
			[self->progressBar  setDoubleValue:1.0];
			[self->progressBar  setMaxValue:approvedUpdates.count+1];
		});
		
		// Begin Patching
		__block NSMutableArray *failedPatches = [[NSMutableArray alloc] init];
		int requiresHalt = 0;
		
		for (NSDictionary *patch in approvedUpdates)
		{
			if (cancelTask) [self _stopThread];
			
			qlinfo(@"Installing: %@",patch[@"patch"]);
			qldebug(@"Patch: %@",patch);
			[self progress:@"Installing %@",patch[@"patch"]];
			MPPatchContentType pType = kCustomPatches;
			if ([patch[@"type"] isEqualToString:@"Apple"]) {
				pType = kApplePatches;
			}
			
			int install_result = 9999;
			NSDictionary *res = [patching installPatchUsingTypeFilter:patch typeFilter:pType];
			if (res[@"patchInstallErrors"]) {
				qldebug(@"patchResult[patchInstallErrors] = %d",[res[@"patchInstallErrors"] intValue]);
				if ([res[@"patchInstallErrors"] intValue] >= 1) {
					qlerror(@"Error installing %@",patch[@"patch"]);
					install_result = 1;
				} else {
					install_result = 0;
				}
			}
			
			if (res[@"patchesRequireHalt"]) {
				if ([res[@"patchInstallErrors"] intValue] >= 1) requiresHalt++;
			}
			
			if (install_result != 0) {
				qlerror(@"Patch %@ failed to install.",patch[@"patch"]);
				[failedPatches addObject:patch];
			}
			
			dispatch_async(dispatch_get_main_queue(), ^(void){
				[self->progressBar setDoubleValue:([self->progressBar doubleValue]+1)];
			});
			
		}
		
		[self progress:@"Complete"];
		[NSThread sleepForTimeInterval:1.0];
		
		if (requiresHalt >= 1) {
			qlinfo(@"Patches have been installed, system will now halt and reboot.");
			[self countDownToClose:2];
		} else {
			qlinfo(@"Patches have been installed, system will now reboot.");
			[self countDownToClose];
		}
	}
}

- (void)countDownToClose
{
	[self countDownToClose:0];
}

- (void)countDownToClose:(int)rebootAction
{
	for (int i = 0; i < 5;i++)
	{
		// Message that window is closing
		[self progress:@"Rebooting system in %d seconds...",(5-i)];
		sleep(1);
	}
	
	[self progress:@"Rebooting System Please Be Patient"];
	[self rebootOrLogout:rebootAction];
}

- (void)countDownShowRebootButton
{
	@autoreleasepool
	{
		for (int i = 0; i < 300;i++)
		{
			sleep(1);
		}
		dispatch_async(dispatch_get_global_queue(0, 0), ^{
			dispatch_async(dispatch_get_main_queue(), ^{
				self->cancelButton.title = @"Reboot";
				self->cancelButton.hidden = NO;
			});
		});
	}
}

- (void)bypassFileVaultForRestart
{
	NSDictionary *authPlist = [NSDictionary dictionaryWithContentsOfFile:MP_AUTHSTATUS_FILE];
	if (![authPlist[@"enabled"] boolValue]) {
		return;
	}
	
	__block NSDictionary *authData = nil;
	dispatch_semaphore_t sem = dispatch_semaphore_create(0);
	[self connectAndExecuteCommandBlock:^(NSError * connectError) {
		if (connectError != nil) {
			qlerror(@"Error getting connection to helper. Authrestart will not occure.");
			qlerror(@"%@",connectError);
			dispatch_semaphore_signal(sem);
		} else {
			[[self.workerConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
				qlerror(@"Error getting remote object from helper. Authrestart will not occure.");
				qlerror(@"%@",proxyError);
				dispatch_semaphore_signal(sem);
			}] getAuthRestartDataWithReply:^(NSError *error, NSDictionary *result) {
				
				if (error) {
					qlerror(@"Error getting result from helper. Authrestart will not occure.");
					qlerror(@"%@",error);
				} else {
					authData = [result copy];
				}
				
				dispatch_semaphore_signal(sem);
			}];
		}
	}];
	dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
	
	if (!authData) return; // Authdata is empty, no need to run the script
	
	NSString *script = [NSString stringWithFormat:@"#!/bin/bash \n"
	"/usr/bin/fdesetup authrestart -delayminutes -0 -verbose -inputplist <<EOF"
	"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
	"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\"> \n"
	"<plist version=\"1.0\"> \n"
	"<dict> \n"
	"	<key>Username</key> \n"
	"	<string>%@</string> \n"
	"	<key>Password</key> \n"
	"	<string>\"%@\"</string> \n"
	"</dict></plist>\n"
	"EOF",authData[@"userName"],authData[@"userPass"]];
	
	MPScript *mps = [MPScript new];
	BOOL res = [mps runScript:script];
	if (!res) {
		qlerror(@"bypassFileVaultForRestart script failed to run.");
	}
	
	// Quick Sleep before the reboot
	[NSThread sleepForTimeInterval:1.0];
}

- (void)rebootOrLogout:(int)action
{
	switch ( action )
	{
		case 0:
			[self bypassFileVaultForRestart];
			[NSTask launchedTaskWithLaunchPath:@"/bin/launchctl" arguments:@[@"reboot"]];
			qlinfo(@"MPAuthPlugin issued a launchctl reboot.");
			[NSThread detachNewThreadSelector:@selector(countDownShowRebootButton) toTarget:self withObject:nil];
			break;
		case 1:
			// just return to loginwindow
			exit(0);
			break;
		case 2:
			// Firmware updates are needed requiring a shutdown (halt)
			[self bypassFileVaultForRestart];
			[NSTask launchedTaskWithLaunchPath:@"/sbin/halt" arguments:@[]];
			qlinfo(@"MPAuthPlugin issued a launchctl reboot and halt.");
			[NSThread detachNewThreadSelector:@selector(countDownShowRebootButton) toTarget:self withObject:nil];
			break;
		default:
			// Code
			exit(0);
			break;
	}
}

- (void)toggleStatusProgress
{
    if ([self->progressBar  isHidden]) {
        
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [self->progressBar  setUsesThreadedAnimation:YES];
                [self->progressBar  setHidden:NO];
                [self->progressBar  startAnimation:nil];
            });
        });
        
    } else {
        [self->progressBar  setHidden:YES];
        [self->progressBar  stopAnimation:nil];
    }
}

- (IBAction)cancelOperation:(id)sender
{
	if ([cancelButton.title isEqualToString:@"Reboot"])
	{
		int rb = 0;
		qlerror(@"User forced a reboot. Some items may not have gotten installed.");
		rb = reboot(RB_AUTOBOOT);
	}
}

- (void)_stopThread
{
    @autoreleasepool
    {
        MDSendAppleEventToSystemProcess(kAERestart);
    }
}

OSStatus MDSendAppleEventToSystemProcess(AEEventID eventToSendID)
{
    qlinfo(@"MDSendAppleEventToSystemProcess called");
    
    AEAddressDesc targetDesc;
    static const ProcessSerialNumber kPSNOfSystemProcess = {0, kSystemProcess };
    AppleEvent eventReply = {typeNull, NULL};
    AppleEvent eventToSend = {typeNull, NULL};
    
    OSStatus status = AECreateDesc(typeProcessSerialNumber,
                                   &kPSNOfSystemProcess, sizeof(kPSNOfSystemProcess), &targetDesc);
    
    if (status != noErr) return status;
    
    status = AECreateAppleEvent(kCoreEventClass, eventToSendID,
                                &targetDesc, kAutoGenerateReturnID, kAnyTransactionID, &eventToSend);
    
    AEDisposeDesc(&targetDesc);
    
    if (status != noErr) return status;
    
    status = AESendMessage(&eventToSend, &eventReply,
                           kAENormalPriority, kAEDefaultTimeout);
    
    AEDisposeDesc(&eventToSend);
    if (status != noErr) return status;
    AEDisposeDesc(&eventReply);
    return status;
}

#pragma mark - Delegates

- (void)patchingProgress:(MPPatching *)mpPatching progress:(NSString *)progressStr
{
	[self progress:progressStr];
}

#pragma mark - Misc

- (void)progress:(NSString *)text,...
{
	va_list va;
	va_start(va, text);
	NSString *string = [[NSString alloc] initWithFormat:text arguments:va];
	va_end(va);
	
    dispatch_async(dispatch_get_main_queue(), ^(void){
		[self->progressText setStringValue:string];
    });
}

#pragma mark - Web Services

- (void)postInstallToWebService:(NSString *)aPatch type:(NSString *)aType
{
    BOOL result = NO;
    NSError *wsErr = nil;
    
    MPRESTfull *rest = [[MPRESTfull alloc] init];
    result = [rest postPatchInstallResults:aPatch type:aType error:&wsErr];
    if (wsErr) {
        qlerror(@"%@",wsErr.localizedDescription);
    } else {
        if (result == TRUE) {
            qlinfo(@"Patch (%@) install result was posted to webservice.",aPatch);
        } else {
            qlerror(@"Patch (%@) install result was not posted to webservice.",aPatch);
        }
    }
    return;
}

#pragma mark - Helper

- (void)connectToHelperTool
// Ensures that we're connected to our helper tool.
{
	assert([NSThread isMainThread]);
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
	assert([NSThread isMainThread]);
	
	// Ensure that there's a helper tool connection in place.
	self.workerConnection = nil;
	[self connectToHelperTool];
	
	commandBlock(nil);
}
@end
