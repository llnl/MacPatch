//
//  AppDelegate.m
//  MacPatch
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

// Constants
static NSString * const MPEventActionPatchScan = @"PatchScan";
static NSString * const MPEventActionPatchPrefs = @"PatchPrefs";
static NSString * const MPNotificationPatchScan = @"PatchScanNotification";
static NSString * const MPUserDefaultsPatchCount = @"PatchCount";
static NSString * const MPUserDefaultsShowSoftwareView = @"showSoftwareView";
static NSString * const MPDistributedNotificationTile = @"gov.llnl.mp.MacPatch.MacPatchTile";

// View Controller Indices
typedef NS_ENUM(NSInteger, MPViewControllerIndex) {
    MPViewControllerIndexSoftware = 0,
    MPViewControllerIndexUpdates = 1,
    MPViewControllerIndexHistory = 2,
    MPViewControllerIndexAgent = 3
};

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

@property (nonatomic, copy) NSString *eventAction;
@property (nonatomic, strong) NSMutableArray<NSViewController *> *availableControllers;

// Helper Setup
@property (atomic, strong, readwrite) NSXPCConnection *worker;

- (void)connectToHelperTool;
- (void)connectAndExecuteCommandBlock:(void(^)(NSError *))commandBlock;
- (void)ensureDatabaseExists;
- (void)displayViewController:(NSViewController *)controller;
- (void)handleEventActionIfNeeded;
- (void)updateToolbarVisibility;

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
	//[defaultValues setObject:[NSNumber numberWithBool:YES] forKey:@"showSoftwareView"];
	
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
    _availableControllers = [[NSMutableArray alloc] init];
    
    // define a controller
    NSViewController *controller;
    
    // instantiate each controller and add it to the
    // controllers list; make sure the controllers
    // are added respecting the tag (check it out the
    // toolbar button tag number)
	
    controller = [[SoftwareViewController alloc] init];
    [_availableControllers addObject:controller];
	
	controller = [[UpdatesVC alloc] init];
	[_availableControllers addObject:controller];
	
    controller = [[HistoryViewController alloc] init];
    [_availableControllers addObject:controller];
	
	controller = [[AgentVC alloc] init];
	[_availableControllers addObject:controller];
	
	[self ensureDatabaseExists];
	
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
    
    NSLog(@"%@",[[NSUserDefaults standardUserDefaults] dictionaryRepresentation]);
    
    // This will be a nsdefault
    NSButton *button = [[NSButton alloc] init];
	BOOL showSoftware = [[NSUserDefaults standardUserDefaults] boolForKey:MPUserDefaultsShowSoftwareView];
    button.tag = showSoftware ? 0 : 1; // Default to Software if shown, otherwise Updates
    
    [self changeView:button];
	[self setDefaultPatchCount:0];
    
    // Update toolbar visibility based on preferences
    [self updateToolbarVisibility];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    // Insert code here to tear down your application
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApplication
{
	return YES;
}

/**
 * Transitions the main window to display the specified view controller.
 * The window is animated to resize appropriately for the new view.
 *
 * @param sender The toolbar button that was clicked, with its tag indicating the view index
 */
- (IBAction)changeView:(NSButton *)sender
{
    MPViewControllerIndex index = (MPViewControllerIndex)[sender tag];
    
    // Reset all button states
    NSArray<NSButton *> *buttons = @[_SoftwareToolbarButton, _UpdatesToolbarButton, 
                                      _HistoryToolbarButton, _AgentToolbarButton];
    for (NSButton *button in buttons) {
        button.state = NSControlStateValueOff;
    }
    
    // Set the selected button
    switch (index) {
        case MPViewControllerIndexSoftware:
            _SoftwareToolbarButton.state = NSControlStateValueOn;
            break;
        case MPViewControllerIndexUpdates:
            _UpdatesToolbarButton.state = NSControlStateValueOn;
            break;
        case MPViewControllerIndexHistory:
            _HistoryToolbarButton.state = NSControlStateValueOn;
            break;
        case MPViewControllerIndexAgent:
            _AgentToolbarButton.state = NSControlStateValueOn;
            break;
    }
    
    [self displayViewController:_availableControllers[index]];
    [self handleEventActionIfNeeded];
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
    
	if ([_eventAction isEqualToString:MPEventActionPatchPrefs]) {
		[_preferencesWindowController setSelectedIndex:2];
	}
    [_preferencesWindowController showWindow:self];
	[_preferencesWindowController setWindowTitle:@"MacPatch - Settings"];
    [_preferencesWindowController setWindowTitleShouldAutomaticlyUpdateToReflectSelectedViewController:NO];
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

- (void)showUpdateWarningWindow:(int)action;
{
    [self.updateWarningWindow makeKeyAndOrderFront:self];
    [self.updateWarningWindow setLevel:NSStatusWindowLevel];
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

- (IBAction)openAppleUpdates:(id)sender
{
    [NSWorkspace.sharedWorkspace openURL: [NSURL fileURLWithPath:ASUS_PREF_PANE]];
}

#pragma mark - DockTile

- (void)setDefaultPatchCount:(NSInteger)pCount
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	
	// We just save the value out, we don't keep a copy of the high score in the app.
	[defaults setInteger:pCount forKey:MPUserDefaultsPatchCount];
	[defaults synchronize];
	
	// And post a notification so the plug-in sees the change.
	[[NSDistributedNotificationCenter defaultCenter] postNotificationName:MPDistributedNotificationTile object:nil];
	
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
		_eventAction = MPEventActionPatchScan;
		[self changeView:self->_UpdatesToolbarButton];
	}
	else if ([query isEqualToString:@"openAndPatchPrefs"])
	{
		_eventAction = MPEventActionPatchPrefs;
		[self showPreferences:nil];
	}
}

#pragma mark - Helper Methods

/**
 * Ensures the MacPatch database exists, creating it if necessary.
 */
- (void)ensureDatabaseExists
{
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:MP_AGENT_DB]) {
        return;
    }
    
    [self connectAndExecuteCommandBlock:^(NSError *connectError) {
        if (connectError != nil) {
            qlerror(@"Failed to connect to helper for database creation: %@", 
                    connectError.localizedDescription);
            return;
        }
        
        [[self.worker remoteObjectProxyWithErrorHandler:^(NSError *proxyError) {
            qlerror(@"Failed to create database proxy: %@", proxyError.localizedDescription);
        }] createAndUpdateDatabase:^(BOOL result) {
            if (result) {
                qlinfo(@"MacPatch Database created and updated successfully.");
            } else {
                qlerror(@"MacPatch Database creation failed.");
            }
        }];
    }];
}

/**
 * Displays the specified view controller in the main window with animation.
 *
 * @param controller The view controller to display
 */
- (void)displayViewController:(NSViewController *)controller
{
    NSView *view = controller.view;
    
    // Calculate window size
    NSSize currentSize = viewHolder.contentView.frame.size;
    NSSize newSize = view.frame.size;
    
    CGFloat deltaWidth = newSize.width - currentSize.width;
    CGFloat deltaHeight = newSize.height - currentSize.height;
    
    NSRect frame = _window.frame;
    frame.size.height += deltaHeight;
    frame.origin.y -= deltaHeight;
    frame.size.width += deltaWidth;
    
    // Unset current view
    viewHolder.contentView = nil;
    
    // Animate window resize
    [_window setFrame:frame display:YES animate:YES];
    
    // Set requested view after resizing
    viewHolder.contentView = view;
    
    view.nextResponder = controller;
    controller.nextResponder = viewHolder;
}

/**
 * Handles any pending event actions after a view change.
 */
- (void)handleEventActionIfNeeded
{
    if ([_eventAction isEqualToString:MPEventActionPatchScan]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:MPNotificationPatchScan 
                                                            object:nil 
                                                          userInfo:@{}];
        _eventAction = nil;
    }
}

/**
 * Updates the toolbar visibility based on user preferences.
 * Hides or shows the Software view toolbar item.
 */
- (void)updateToolbarVisibility
{
	BOOL showSoftware = [[NSUserDefaults standardUserDefaults] boolForKey:MPUserDefaultsShowSoftwareView];
	
	// Hide or show the Software toolbar item
	_SoftwareToolbarItem.hidden = !showSoftware;
	
	// If currently showing Software view and it's being hidden, switch to Updates
	if (!showSoftware && _SoftwareToolbarButton.state == NSControlStateValueOn) {
		[self changeView:_UpdatesToolbarButton];
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
	NSParameterAssert(commandBlock != nil);
	assert([NSThread isMainThread]);
	
	// Ensure that there's a helper tool connection in place.
	[self connectToHelperTool];
	
	if (self.worker == nil) {
		NSError *error = [NSError errorWithDomain:@"gov.llnl.mp.MacPatch" 
											 code:-1 
										 userInfo:@{NSLocalizedDescriptionKey: @"Failed to connect to helper tool"}];
		commandBlock(error);
	} else {
		commandBlock(nil);
	}
}

@end
