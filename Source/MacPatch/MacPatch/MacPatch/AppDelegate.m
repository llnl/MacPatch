//
//  AppDelegate.m
//  MacPatch
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

#import "AppDelegate.h"
#import "SoftwareViewController.h"
#import "UpdatesVC.h"
#import "HistoryViewController.h"
#import "AgentVC.h"
#import "EventToSend.h"

// Prefs
#import "PrefsGeneralViewController.h"
#import "PrefsSoftwareVC.h"
#import "PrefsUpdatesVC.h"
#import "PrefsAdvancedVC.h"

@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@property (weak) IBOutlet NSToolbarItem *SoftwareToolbarItem;
@property (weak) IBOutlet NSToolbarItem *UpdatesToolbarItem;
@property (weak) IBOutlet NSToolbarItem *HistoryToolbarItem;
@property (weak) IBOutlet NSToolbarItem *AgentToolbarItem;

@property (weak) IBOutlet NSButton *SoftwareToolbarButton;
@property (weak) IBOutlet NSButton *UpdatesToolbarButton;
@property (weak) IBOutlet NSButton *HistoryToolbarButton;
@property (weak) IBOutlet NSButton *AgentToolbarButton;

@property (weak) NSString *eventAction;


// Helper Setup
@property (atomic, strong, readwrite) NSXPCConnection *worker;

- (void)connectToHelperTool;
- (void)connectAndExecuteCommandBlock:(void(^)(NSError *))commandBlock;

@end

@implementation AppDelegate

@synthesize preferencesWindowController=_preferencesWindowController;

+ (void)initialize
{
	NSMutableDictionary *defaultValues = [NSMutableDictionary dictionary];
	
	[defaultValues setObject:[NSNumber numberWithBool:NO] forKey:@"enableDebugLogging"];
	[defaultValues setObject:[NSNumber numberWithBool:NO] forKey:@"enableScanOnLaunch"];
	[defaultValues setObject:[NSNumber numberWithBool:NO] forKey:@"preStageRebootPatches"];
	// [defaultValues setObject:[NSNumber numberWithBool:NO] forKey:@"allowRebootPatchInstalls"];
    [defaultValues setObject:[NSNumber numberWithBool:YES] forKey:@"allowRebootPatchInstalls"];
	
	[[NSUserDefaults standardUserDefaults] registerDefaults:defaultValues];
}

- (id)init
{
    self = [super init];
	
	NSString *_logFile = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/MacPatch.log"];
	[MPLog setupLogging:_logFile level:lcl_vInfo];
	[LCLLogFile setMirrorsToStdErr:YES];
	
	qlinfo(@"Logging up and running");
    
    // instantiate the controllers array
    availableControllers = [[NSMutableArray alloc] init];

    
    // define a controller
    NSViewController *controller;
    
    // instantiate each controller and add it to the
    // controllers list; make sure the controllers
    // are added respecting the tag (check it out the
    // toolbar button tag number)
	
    controller = [[SoftwareViewController alloc] init];
    [availableControllers addObject:controller];
	
	controller = [[UpdatesVC alloc] init];
	[availableControllers addObject:controller];
	
    controller = [[HistoryViewController alloc] init];
    [availableControllers addObject:controller];
	
	controller = [[AgentVC alloc] init];
	[availableControllers addObject:controller];
	
	NSFileManager *fm = [NSFileManager defaultManager];
	if (![fm fileExistsAtPath:MP_AGENT_DB])
	{
		[self connectAndExecuteCommandBlock:^(NSError * connectError) {
			if (connectError != nil) {
				qlerror(@"connectError: %@",connectError.localizedDescription);
			} else {
				[[self.worker remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
					qlerror(@"proxyError: %@",proxyError.localizedDescription);
				}] createAndUpdateDatabase:^(BOOL result) {
					qlinfo(@"MacPatch Database created and updated.");
				}];
			}
		}];
	}
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    if (@available(macOS 11.0, *)) {
        //[[self window] setToolbarStyle:NSWindowToolbarStylePreference];
        [[self window] setToolbarStyle:NSWindowToolbarStyleExpanded];
    }
    
	[[NSAppleEventManager sharedAppleEventManager] setEventHandler:self
													   andSelector:@selector(handleURLEvent:withReplyEvent:)
													 forEventClass:kInternetEventClass
														andEventID:kAEGetURL];
	
    // Insert code here to initialize your application
    self.toolBar.delegate = self;
    
    // This will be a nsdefault
    NSButton *button = [[NSButton alloc] init];
    button.tag = 0;
    
    [self changeView:button];
	[self setDefaultPatchCount:0];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    // Insert code here to tear down your application
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApplication
{
	return YES;
}

- (IBAction)ShowSoftwareView:(id)sender {
}

- (IBAction)ShowHistoryView:(id)sender {
}

- (IBAction)showUpdatesView:(id)sender {
}

- (IBAction)changeView:(id)sender
{
    int i = (int)[sender tag];
    switch (i) {
			
        case 0:
            // Software
            [_SoftwareToolbarButton setState:NSOnState];
			[_UpdatesToolbarButton setState:NSOffState];
            [_HistoryToolbarButton setState:NSOffState];
            [_AgentToolbarButton setState:NSOffState];
            break;
        case 1:
            // Updates
            [_SoftwareToolbarButton setState:NSOffState];
            [_UpdatesToolbarButton setState:NSOnState];
            [_HistoryToolbarButton setState:NSOffState];
            [_AgentToolbarButton setState:NSOffState];
            break;
        case 2:
            // History
            [_SoftwareToolbarButton setState:NSOffState];
            [_UpdatesToolbarButton setState:NSOffState];
            [_HistoryToolbarButton setState:NSOnState];
            [_AgentToolbarButton setState:NSOffState];
            break;
        case 3:
            // Agent
            [_SoftwareToolbarButton setState:NSOffState];
            [_UpdatesToolbarButton setState:NSOffState];
            [_HistoryToolbarButton setState:NSOffState];
            [_AgentToolbarButton setState:NSOnState];
            break;
        default:
            [_SoftwareToolbarButton setState:NSOffState];
            [_UpdatesToolbarButton setState:NSOffState];
            [_HistoryToolbarButton setState:NSOnState];
            [_AgentToolbarButton setState:NSOffState];
            break;
    }
    
    
    NSViewController *controller = [availableControllers objectAtIndex:i];
    NSView *view = [controller view];
    
    // calculate window size
    NSSize currentSize = [[viewHolder contentView] frame].size;
    NSSize newSize = [view frame].size;
    
    //NSLog(@"current view: %.0f, %.0f", currentSize.width, currentSize.height);
    //NSLog(@"new view: %.0f, %.0f", newSize.width, newSize.height);
    
    float deltaWidth = newSize.width - currentSize.width;
    float deltaHeight = newSize.height - currentSize.height;
    
    //NSLog(@"deltas: %.0f, %.0f", deltaWidth, deltaHeight);
    
    NSRect frame = [_window frame];
    
    //NSLog(@"current frame: %.0f, %.0f", frame.size.width, frame.size.height);
    
    frame.size.height += deltaHeight;
    frame.origin.y -= deltaHeight;
    frame.size.width += deltaWidth;
    
    //NSLog(@"new frame: %.0f, %.0f", frame.size.width, frame.size.height);
    
    // unset current view
    [viewHolder setContentView:nil];
    
    // do animate
    [_window setFrame:frame display:YES animate:YES];
    
    // set requested view after resizing the window
    [viewHolder setContentView:view];
    
    [view setNextResponder:controller];
    [controller setNextResponder:viewHolder];
	if (_eventAction) {
		if ([_eventAction isEqualToString:@"PatchScan"]) {
			[[NSNotificationCenter defaultCenter] postNotificationName:@"PatchScanNotification" object:nil userInfo:@{}];
			_eventAction = nil;
		}
	}
}

-(IBAction)showPreferences:(id)sender
{
    //if we have not created the window controller yet, create it now
    if (!_preferencesWindowController)
    {
		PrefsGeneralViewController		*general  = [PrefsGeneralViewController new];
		PrefsSoftwareVC					*software = [PrefsSoftwareVC new];
		PrefsUpdatesVC					*updates  = [PrefsUpdatesVC new];
		//PrefsAdvancedVC					*advanced = [PrefsAdvancedVC new];

		NSArray *controllers = @[general, software, updates];
        _preferencesWindowController = [[RHPreferencesWindowController alloc] initWithViewControllers:controllers];
    }
    
    
	if ([_eventAction isEqualToString:@"PatchPrefs"]) {
		[_preferencesWindowController setSelectedIndex:2];
	}
    [_preferencesWindowController showWindow:self];
	[_preferencesWindowController setWindowTitle:@"Preferences"];
}

- (NSArray *)toolbarSelectableItemIdentifiers:(NSToolbar *)toolbar
{
    return @[@"SoftwareItem",@"UpdatesItem",@"HistoryItem",@"AgentItem"];
}

- (IBAction)showMainLog:(id)sender
{
	[[NSWorkspace sharedWorkspace] openFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/MacPatch.log"] withApplication:@"Console"];
}

- (IBAction)showHelperLog:(id)sender
{
	[[NSWorkspace sharedWorkspace] openFile:@"/Library/Logs/gov.llnl.mp.helper.log" withApplication:@"Console"];
}

- (void)showRebootWindow
{
	[self.rebootWindow makeKeyAndOrderFront:self];
	[self.rebootWindow setLevel:NSStatusWindowLevel];
}

- (void)showSWRebootWindow
{
	[self.swRebootWindow makeKeyAndOrderFront:self];
	[self.swRebootWindow setLevel:NSStatusWindowLevel];
}

- (void)showRestartWindow:(int)action
{
	if (action == 1) {
		[@"HALT" writeToFile:@"/private/tmp/.asusHalt" atomically:NO encoding:NSUTF8StringEncoding error:NULL];
	}
	
	[self.restartWindow makeKeyAndOrderFront:self];
	[self.restartWindow setLevel:NSStatusWindowLevel];
}

- (IBAction)restartOrShutdown:(id)sender
{
	OSStatus error = noErr;
	
	int action = 0; // 0 = normal reboot, 1 = shutdown
	NSFileManager *fm = [NSFileManager defaultManager];
	if ([fm fileExistsAtPath:@"/private/tmp/.asusHalt"]) {
        qlinfo(@"MacPatch issued a launchctl kAEShutDown.");
		action = 1;
	}
    
	switch ( action )
	{
		case 0:
            [self setAuthRestart];
			error = SendAppleEventToSystemProcess(kAERestart);
			qlinfo(@"MacPatch issued a launchctl kAERestart.");
			break;
		case 1:
            [self setAuthRestart];
			error = SendAppleEventToSystemProcess(kAEShutDown);
			qlinfo(@"MacPatch issued a kAEShutDown.");
			break;
		default:
			// Code
			exit(0);
			break;
	}
}

- (void)setAuthRestart
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if ([d boolForKey:@"authRestartEnabled"]) {
        [self connectAndExecuteCommandBlock:^(NSError * connectError) {
            if (connectError != nil) {
                qlerror(@"connectError: %@",connectError.localizedDescription);
            } else {
                [[self.worker remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
                    qlerror(@"proxyError: %@",proxyError.localizedDescription);
                }] enableAuthRestartWithReply:^(NSError *error, NSInteger result) {
                    if (error) {
                        qlerror(@"Error, unable to enable FileVault auth restart");
                    }
                    qlinfo(@"MacPatch Database created and updated.");
                }];
            }
        }];
    }
}

#pragma mark - DockTile

- (void)setDefaultPatchCount:(NSInteger)pCount
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	
	// We just save the value out, we don't keep a copy of the high score in the app.
	[defaults setInteger:pCount forKey:@"PatchCount"];
	[defaults synchronize];
	
	// And post a notification so the plug-in sees the change.
	[[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"gov.llnl.mp.MacPatch.MacPatchTile" object:nil];
	
	// Now update the dock tile. Note that a more general way to do this would be to observe the highScore property, but we're just keeping things short and sweet here, trying to demo how to write a plug-in.
	if (pCount >= 1) {
		[[[NSApplication sharedApplication] dockTile] setBadgeLabel:[NSString stringWithFormat:@"%ld", (long)pCount]];
	} else {
		[[[NSApplication sharedApplication] dockTile] setBadgeLabel:@""];
	}
	
}

#pragma mark - URL Scheme

- (void)handleURLEvent:(NSAppleEventDescriptor*)event withReplyEvent:(NSAppleEventDescriptor*)replyEvent
{
	id urlDescriptor = [event paramDescriptorForKeyword:keyDirectObject];
    NSString *urlStr = [urlDescriptor stringValue];
	NSURL *url = [NSURL URLWithString:urlStr];
	NSString *query = url.query;
	if ([query isEqualToString:@"openAndScan"])
	{
		qlinfo(@"openAndScan");
		_eventAction = @"PatchScan";
		[self changeView:self->_UpdatesToolbarButton];
		dispatch_async(dispatch_get_main_queue(), ^{
			//[NSThread sleepForTimeInterval:0.5];		
		});
	}
	else if ([query isEqualToString:@"openAndPatchPrefs"])
	{
		_eventAction = @"PatchPrefs";
		[self showPreferences:nil];
	}
}


#pragma mark - Helper

- (void)connectToHelperTool
// Ensures that we're connected to our helper tool.
{
	assert([NSThread isMainThread]);
	if (self.worker == nil) {
		self.worker = [[NSXPCConnection alloc] initWithMachServiceName:kHelperServiceName options:NSXPCConnectionPrivileged];
		self.worker.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(MPHelperProtocol)];
		
		// Register Progress Messeges From Helper
		self.worker.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(MPHelperProgress)];
		self.worker.exportedObject = self;
		
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
		// We can ignore the retain cycle warning because a) the retain taken by the
		// invalidation handler block is released by us setting it to nil when the block
		// actually runs, and b) the retain taken by the block passed to -addOperationWithBlock:
		// will be released when that operation completes and the operation itself is deallocated
		// (notably self does not have a reference to the NSBlockOperation).
		self.worker.invalidationHandler = ^{
			// If the connection gets invalidated then, on the main thread, nil out our
			// reference to it.  This ensures that we attempt to rebuild it the next time around.
			self.worker.invalidationHandler = nil;
			[[NSOperationQueue mainQueue] addOperationWithBlock:^{
				self.worker = nil;
			}];
		};
#pragma clang diagnostic pop
		[self.worker resume];
	}
}

- (void)connectAndExecuteCommandBlock:(void(^)(NSError *))commandBlock
// Connects to the helper tool and then executes the supplied command block on the
// main thread, passing it an error indicating if the connection was successful.
{
	assert([NSThread isMainThread]);
	
	// Ensure that there's a helper tool connection in place.
	// self.workerConnection = nil;
	[self connectToHelperTool];
	
	commandBlock(nil);
}
@end
