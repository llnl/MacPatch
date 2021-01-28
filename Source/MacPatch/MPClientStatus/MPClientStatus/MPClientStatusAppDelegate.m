//
//  MPClientStatusAppDelegate.m
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

#import "MPClientStatusAppDelegate.h"
#import "MacPatch.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import "MPAppUsage.h"
#import "MPWorkerProtocol.h"
#import "AppLaunchObject.h"
#import "CHMenuViewController.h"
#import "EventToSend.h"
//#import <UserNotifications/UserNotifications.h>

#import "Provisioning.h"


NSString * const kMenuIconNorml		= @"mp3Image";
NSString * const kMenuIconAlert		= @"mp3ImageAlert";

// Private Methods
@interface MPClientStatusAppDelegate ()
{
    NSFileManager *fm;
	MPSettings *settings;
    NSWindowController *windowController;
}

@property (strong, nonatomic) NSWindowController *provisionWindowController;

// Helper
// XPC Connection
@property (atomic, strong, readwrite) NSXPCConnection *workerConnection;

- (void)connectToHelperTool;
- (void)connectAndExecuteCommandBlock:(void(^)(NSError *))commandBlock;

// Watch Patch Status/Needed
@property (nonatomic, strong) NSDate *lastPatchStatusUpdate;
@property (strong, nonatomic) NSCondition *condition;
@property (nonatomic, strong) NSDictionary *appRules;

@end

// GCD Timer, replaces NSTimer code
dispatch_source_t CreateDispatchTimer(double interval, dispatch_queue_t queue, dispatch_block_t block)
{
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    if (timer)
    {
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, interval * NSEC_PER_SEC), interval * NSEC_PER_SEC, (1ull * NSEC_PER_SEC) / 10);
        dispatch_source_set_event_handler(timer, block);
        dispatch_resume(timer);
    }
    return timer;
}


@implementation MPClientStatusAppDelegate
{
    dispatch_source_t _timer;
	dispatch_source_t _timerSWRules;
}

NSString *const kShowPatchesRequiredNotification    = @"kShowPatchesRequiredNotification";
NSString *const kRebootRequiredNotification         = @"kRebootRequiredNotification";
NSString *const kRefreshStatusIconNotification      = @"kRefreshStatusIconNotification";
NSString *const kRequiredPatchesChangeNotification  = @"kRequiredPatchesChangeNotification";

#pragma mark Properties
@synthesize window;
@synthesize checkInStatusMenuItem;
@synthesize checkPatchStatusMenuItem;
@synthesize selfVersionInfoMenuItem;
@synthesize MPVersionInfoMenuItem;
@synthesize checkAgentAndUpdateMenuItem;

// Client Info
@synthesize clientInfoWindow;
@synthesize clientInfoTableView;
@synthesize clientArrayController;

// Patch Info
@synthesize patchCount;
@synthesize patchNeedsReboot;

// About Window
@synthesize aboutWindow;
@synthesize appIcon;
@synthesize appName;
@synthesize appVersion;

// Reboot Window
@synthesize rebootWindow;
@synthesize rebootTitleText;
@synthesize rebootBodyText;

// Client CheckIn Data
@synthesize queue;

// App Launching Filter Rules
@synthesize appRules;

// Critical Updates
@synthesize criticalUpdates;
@synthesize showCriticalWindowAtDate;
@synthesize criticalUpdatesTimer;
@synthesize swResHelpMessage = _swResHelpMessage;

+ (void)initialize
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	if ([[NSFileManager defaultManager] fileExistsAtPath:@"/private/tmp/.mpResetWhatsNew"])
	{
		[defaults removeObjectForKey:@"showWhatsNew"];
		[defaults synchronize];
		[[NSFileManager defaultManager] removeItemAtPath:@"/private/tmp/.mpResetWhatsNew" error:NULL];
	}
	
	NSMutableDictionary *defaultValues = [NSMutableDictionary dictionary];
	[defaultValues setObject:[NSNumber numberWithBool:YES] forKey:@"showWhatsNew"];
	[defaults registerDefaults:defaultValues];
	[defaults synchronize];
}

#pragma mark UI Events
-(void)awakeFromNib
{
    fm = [NSFileManager defaultManager];
	settings = [MPSettings sharedInstance];
	[settings refresh];
	
    // Remove all notifications, will get re-added if needed.
    [[NSUserNotificationCenter defaultUserNotificationCenter] removeAllDeliveredNotifications];
	criticalUpdates = [NSMutableArray new];
    
    statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    [statusItem setMenu:statusMenu];
    [statusItem setImage:[NSImage imageNamed:kMenuIconAlert]];
    [statusItem setHighlightMode:YES];
    
    // App Version Info
	NSString *cfShortVerStr = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    [selfVersionInfoMenuItem setTitle:[NSString stringWithFormat:@"Status App Version: %@",cfShortVerStr]];
	
    NSDictionary *_mpVerDict = [NSDictionary dictionaryWithContentsOfFile:AGENT_VER_PLIST];
    [MPVersionInfoMenuItem setTitle:[NSString stringWithFormat:@"MacPatch Version: %@",_mpVerDict[@"version"]]];
    
    
    [[NSDistributedNotificationCenter defaultCenter] addObserver: self
                                                        selector: @selector(userNotificationReceived:)
                                                            name: kShowPatchesRequiredNotification
                                                          object: nil];
	
    [[NSDistributedNotificationCenter defaultCenter] addObserver: self
                                                        selector: @selector(userNotificationReceived:)
                                                            name: kRebootRequiredNotification
                                                          object: nil];
	
	[[NSDistributedNotificationCenter defaultCenter] addObserver: self
														selector: @selector(userNotificationReceived:)
															name: kRequiredPatchesChangeNotification
														  object: nil];
	
	[[NSDistributedNotificationCenter defaultCenter] addObserver: self
														selector: @selector(userNotificationReceived:)
															name: @"kFileVaultUserOutOfSync"
														  object: nil];
	
	[self displayPatchDataMethod]; // Show needed patches
	[self wakeMeUp];
    
    //self.provisionWindowController = [[Provisioning alloc] initWithWindowNibName:@"Provisioning"];
    //[self.provisionWindowController showWindow:self];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Show/hide Quit Menu Item
    NSTimer *t = [NSTimer timerWithTimeInterval:0.1 target:self selector:@selector(updateMenu:) userInfo:statusMenu repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:t forMode:NSEventTrackingRunLoopMode];
    
    //Setup Defaults
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    [prefs registerDefaults:[NSDictionary dictionaryWithContentsOfFile:APP_PREFS_PLIST]];
    
    NSString *_logFile = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/MPClientStatus.log"];
    [MPLog setupLogging:_logFile level:lcl_vInfo];
    
    if ([prefs boolForKey:@"DeBug"] == YES)
    {
        // enable logging for all components up to level Debug
        lcl_configure_by_name("*", lcl_vDebug);
        logit(lcl_vInfo,@"***** MPStatus started -- Debug Enabled *****");
    } else {
        // enable logging for all components up to level Info
        lcl_configure_by_name("*", lcl_vInfo);
        logit(lcl_vInfo,@"***** MPStatus started *****");
    }
    
    // Watch for SoftwareUpdate Launches
    NSNotificationCenter *dc = [[NSWorkspace sharedWorkspace] notificationCenter];
    
    // Setup App monitoring
    mpAppUsage = [[MPAppUsage alloc] init];
    [mpAppUsage cleanDB]; // Removes Entries Where App Version is NULL
    
    [dc addObserver:self selector:@selector(appLaunchNotificationReceived:) name:NSWorkspaceWillLaunchApplicationNotification object:[NSWorkspace sharedWorkspace]];
    [dc addObserver:self selector:@selector(appLaunchForFilterNotification:) name:NSWorkspaceWillLaunchApplicationNotification object:[NSWorkspace sharedWorkspace]];
    
    // Start Last CheckIn Thread, update every 5 min
    [self showLastCheckIn];
    
    // This (timer) will monitor for hits, when to update the patch status flags
	// It will refresh every 120 seconds
    [self displayPatchData];
    
    // Run Notification Timer
    [self runMPUserNotificationCenter];
    
    appRules = @{@"allow":@[],@"deny":@[]};
	[self processSoftwareRules];
	
	if ([prefs stringForKey:@"denyHelpStringMessage"])
	{
		_swResHelpMessage = [prefs stringForKey:@"denyHelpStringMessage"];
	}
	
	// Run FileVault User Password Check Sync
	[self fvUserCheck];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/private/var/db/.MPProvisionBegin"]) {
        self.provisionWindowController = [[Provisioning alloc] initWithWindowNibName:@"Provisioning"];
        [self.provisionWindowController showWindow:self];
    } else {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        if ([defaults boolForKey:@"showWhatsNew"]) {
            [self loadWhatsNewWebView:nil];
            [whatsNewWindow makeKeyAndOrderFront:nil];
            [whatsNewWindow center];
            [NSApp activateIgnoringOtherApps:YES];
        }
    }
}

#pragma mark -
#pragma mark Main

- (void)updateMenu:(NSTimer *)timer
{
    static NSMenuItem *menuItem15 = nil;
    static NSMenuItem *menuItem16 = nil;
    static BOOL isShowing = YES;
    
    // Get global modifier key flag, [[NSApp currentEvent] modifierFlags] doesn't update while menus are down
    CGEventRef event = CGEventCreate (NULL);
    CGEventFlags flags = CGEventGetFlags (event);
    BOOL optionKeyIsPressed = (flags & kCGEventFlagMaskAlternate) == kCGEventFlagMaskAlternate;
    CFRelease(event);
    
    NSMenu *menu = [timer userInfo];
    
    if (!menuItem15 && !menuItem16) {
        // View Batch Jobs...
        //menuItem15 = [menu itemAtIndex:15];
        //menuItem16 = [menu itemAtIndex:16];
        menuItem15 = [menu itemAtIndex:([menu numberOfItems] - 2)];
        menuItem16 = [menu itemAtIndex:([menu numberOfItems] -1)];
    }
    
    if (!isShowing && optionKeyIsPressed)
	{
        [menu addItem:menuItem15];
        [menuItem15 setEnabled:YES];
        [menuItem15 setHidden:NO];
        [menu addItem:menuItem16];
        [menuItem16 setEnabled:YES];
        [menuItem16 setHidden:NO];
        isShowing = YES;
    } else if (isShowing && !optionKeyIsPressed) {
        [menu removeItem:menuItem15];
        [menu removeItem:menuItem16];
        isShowing = NO;
    }
    
    [menu update];
}

#pragma mark - Helper

- (void)connectToHelperTool
// Ensures that we're connected to our helper tool.
{
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
	// Ensure that there's a helper tool connection in place.
	self.workerConnection = nil;
	[self connectToHelperTool];
	
	commandBlock(nil);
}


#pragma mark -
#pragma mark Client Info
- (IBAction)getMPClientVersionInfo:(id)sender
{
    [clientArrayController removeObjects:[clientArrayController arrangedObjects]];
    [clientInfoTableView reloadData];
    
    NSDictionary *mpVerDict = [NSDictionary dictionaryWithContentsOfFile:AGENT_VER_PLIST];
    NSString *verInfo = [NSString stringWithFormat:@"Version: %@\nBuild: %@\nClient ID: %@",
                         mpVerDict[@"version"], mpVerDict[@"build"], [MPSystemInfo clientUUID]];
    
    [clientInfoTextField setFont:[NSFont fontWithName:@"Lucida Grande" size:11.0]];
    [clientInfoTextField setStringValue:verInfo];
    
    [clientInfoWindow makeKeyAndOrderFront:sender];
    [clientInfoWindow center];
    [NSApp arrangeInFront:sender];
    [NSApp activateIgnoringOtherApps:YES];
}

- (IBAction)closeClientInfoWindow:(id)sender
{
    [clientInfoWindow close];
}

#pragma mark -
#pragma mark About Window
- (IBAction)showAboutWindow:(id)sender
{
    appName.stringValue = [[NSProcessInfo processInfo] processName];
    appVersion.stringValue = [NSString stringWithFormat:@"Version %@ (%@)",[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"],[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]];
    [appIcon setImage:[NSImage imageNamed:@"NSApplicationIcon"]];
    [aboutWindow makeKeyAndOrderFront:sender];
    [aboutWindow center];
}

#pragma mark -
#pragma mark Reboot Window
- (IBAction)closeRebootWindow:(id)sender
{
    [self.rebootWindow close];
}

#pragma mark Checkin
- (IBAction)showCheckinWindow:(id)sender
{
	[self connectAndExecuteCommandBlock:^(NSError * connectError)
	 {
		 if (connectError != nil)
		 {
			 qlerror(@"connectError: %@",connectError.localizedDescription);
		 }
		 else
		 {
			 [[self.workerConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
				 qlerror(@"proxyError: %@",proxyError.localizedDescription);
			 }] runCheckInWithReply:^(NSError *err, NSDictionary *result) {
				dispatch_sync(dispatch_get_main_queue(), ^()
				   {
					   NSAlert *alert = [[NSAlert alloc] init];
					   [alert addButtonWithTitle:@"OK"];
					   if (err) {
						   [alert setMessageText:@"Error with check-in"];
						   [alert setInformativeText:@"There was a problem checking in with the server. Please review the client status logs for cause."];
						   [alert setAlertStyle:NSCriticalAlertStyle];
					   } else {
						   [alert setMessageText:@"Client check-in"];
						   [alert setInformativeText:@"Client check-in was successful."];
						   [alert setAlertStyle:NSInformationalAlertStyle];
						   
						   [self performSelectorOnMainThread:@selector(showLastCheckInMethod)
												  withObject:nil waitUntilDone:NO modes:@[NSRunLoopCommonModes]];
					   }
					   
					   [alert runModal];
				   });
			 }];
		 }
	 }];

}

#pragma mark Show Last CheckIn Menu
- (void)showLastCheckIn
{
    double secondsToFire = 300.0; // Every 5 min
    logit(lcl_vInfo, @"Start Last CheckIn Data Thread");
    logit(lcl_vInfo, @"Run every %f", secondsToFire);
    
    // Show Menu Once, then use timer
    [self performSelectorOnMainThread:@selector(showLastCheckInMethod)
                           withObject:nil
                        waitUntilDone:NO
                                modes:@[NSRunLoopCommonModes]];
    
    dispatch_queue_t gcdQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    
    _timer = CreateDispatchTimer(secondsToFire, gcdQueue, ^{
        logit(lcl_vInfo, @"Start, Display Last CheckIn Data in menu.");
        logit(lcl_vDebug, @"Repeats every %f seconds", secondsToFire);
        [self performSelectorOnMainThread:@selector(showLastCheckInMethod)
                               withObject:nil
                            waitUntilDone:NO
                                    modes:@[NSRunLoopCommonModes]];
    });
}

- (void)wakeMeUp
{
	[self userNotificationReceived:nil];
	
	// Call this method again using GCD
	// DISPATCH_QUEUE_PRIORITY_BACKGROUND
	dispatch_queue_t q_background = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
	double delayInSeconds = 3.0;
	dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
	dispatch_after(popTime, q_background, ^(void){
		[self wakeMeUp];
	});
}

- (void)showLastCheckInMethod
{
    @autoreleasepool
    {
        logit(lcl_vInfo, @"Running last agent check in date request.");
        NSDictionary *result;
        NSError *wsErr = nil;
        MPRESTfull *rest = [[MPRESTfull alloc] init];
        result = [rest getLastCheckinData:&wsErr];
        
        NSDictionary *data;
        if ([result objectForKey:@"data"]) data = [result objectForKey:@"data"];
        
        logit(lcl_vDebug,@"%@",result);
        
        if (wsErr) logit(lcl_vError,@"%@",wsErr.localizedDescription);
			
        if ([data objectForKey:@"mdate1"]) {
            [checkInStatusMenuItem setTitle:[NSString stringWithFormat:@"Last Checkin: %@",[data objectForKey:@"mdate1"]]];
            [statusMenu update];
        }
    }
}

- (void)fvUserCheck
{
    double secondsToFire = 120.0; // Every 5 min
    logit(lcl_vInfo, @"Start FileVault User Check Thread");
    logit(lcl_vInfo, @"Run every %f", secondsToFire);
    
    // Show Menu Once, then use timer
    [self performSelectorOnMainThread:@selector(fvUserCheckMethod)
                           withObject:nil
                        waitUntilDone:NO
                                modes:@[NSRunLoopCommonModes]];
    
    dispatch_queue_t gcdQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    
    _timer = CreateDispatchTimer(secondsToFire, gcdQueue, ^{
        [self performSelectorOnMainThread:@selector(fvUserCheckMethod)
                               withObject:nil
                            waitUntilDone:NO
                                    modes:@[NSRunLoopCommonModes]];
    });
}

- (void)fvUserCheckMethod
{
	@autoreleasepool
	{
		MPFileCheck *fu = [MPFileCheck new];
		if (![fu fExists:MP_AUTHSTATUS_FILE]) return;
		
		dispatch_semaphore_t sem = dispatch_semaphore_create(0);
		
		[self connectAndExecuteCommandBlock:^(NSError * connectError)
		{
			if (connectError != nil)
			{
				qlerror(@"connectError: %@",connectError.localizedDescription);
			}
			else
			{
				[[self.workerConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
					qlerror(@"proxyError: %@",proxyError.localizedDescription);
                    dispatch_semaphore_signal(sem);
				}] fvAuthrestartAccountIsValid:^(NSError *err, BOOL result) {
					if (err) {
						qlerror(@"%@",err.localizedDescription);
					}
					
					// User account is out of sync, post notification.
					if (!result) {
						[self postUserNotificationForFVAuthRestart];
					}
					dispatch_semaphore_signal(sem);
				}];
			}
		}];
		
		dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
	}
}


#pragma mark Show Patch Status

- (void)displayPatchData
{
    // Show Menu Once, then use timer
    [self performSelectorOnMainThread:@selector(displayPatchDataMethod)
                           withObject:nil
                        waitUntilDone:NO
                                modes:[NSArray arrayWithObject:NSRunLoopCommonModes]];
    
    dispatch_queue_t gcdQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    double secondsToFire = 120.0;
    
    _timer = CreateDispatchTimer(secondsToFire, gcdQueue, ^{
        logit(lcl_vInfo, @"Start, Display Patch Data Info in menu.");
        logit(lcl_vDebug, @"Repeats every %f seconds", secondsToFire);
        [self performSelectorOnMainThread:@selector(displayPatchDataMethod)
                               withObject:nil
                            waitUntilDone:NO
                                    modes:[NSArray arrayWithObject:NSRunLoopCommonModes]];
    });
}

- (void)displayPatchDataMethod
{
    @autoreleasepool
    {
        logit(lcl_vInfo, @"Running client patch status request.");
        
        self.patchNeedsReboot = NO;
        self.patchCount = 0;
		
		NSDictionary *patchData = [self readRequiredPatches];
		NSArray *patches = patchData[@"patches"];
		self.patchCount = patches.count;
		NSString *subMenuTitle = [NSString stringWithFormat:@"Patches Needed: %lu ",patches.count];

        if ([patchData[@"needsReboot"] isEqualToString:@"Y"]) {
            self.patchNeedsReboot = YES;
        }
        
        // If No Patches ...
        if (patches.count <= 0)
        {
            [statusItem setImage:[NSImage imageNamed:kMenuIconNorml]];
            [checkPatchStatusMenuItem setTitle:@"Patches Needed: 0"];
            [checkPatchStatusMenuItem setSubmenu:NULL];
            [statusMenu update];
            
            // Remove Notifications
			NSUserDefaults *ud = [[NSUserDefaults alloc] initWithSuiteName:@"mp.cs.note"];
			[ud setBool:NO forKey:@"patch"];
			[ud setBool:NO forKey:@"reboot"];
			for (NSUserNotification *nox in [[NSUserNotificationCenter defaultUserNotificationCenter] deliveredNotifications]) {
				if ([nox.title isEqualToString:@"Reboot Patches Required"]) {
					[[NSUserNotificationCenter defaultUserNotificationCenter] removeDeliveredNotification:nox];
				}
			}
			[ud synchronize];
			
			[statusMenu update];
            return;
        }
        else
        {
            [statusItem setImage:[NSImage imageNamed:kMenuIconAlert]];
        }
        
        [checkPatchStatusMenuItem setTitle:subMenuTitle];
		// Create Sub-menu with patch items
		NSMenu *subMenu = [[NSMenu alloc] initWithTitle:subMenuTitle];
        [checkPatchStatusMenuItem setSubmenu:subMenu];
        [checkPatchStatusMenuItem setEnabled:YES];
        
        NSMenuItem *newMenuItem;
        
        // Add Header Menu Item
        CHMenuViewController *vcTitle = [[CHMenuViewController alloc] init];
        NSRect f = vcTitle.view.frame;
        f.size.width = 337;
        f.size.height = 26;
        vcTitle.view.frame = f;
        
        [vcTitle.view addSubview:vcTitle.titleView];
        newMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:NULL keyEquivalent:@""];
        [newMenuItem setView:vcTitle.view];
        [subMenu addItem:newMenuItem];
        
        // Add Patches as menu item using views
        CHMenuViewController *vc;
        for (NSDictionary *d in patches)
        {
            newMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
            vc = [[CHMenuViewController alloc] init];
            [vc addTitle:d[@"name"] version:d[@"version"]];
            if ([d[@"reboot"] isEqualToString:@"Y"])
            {
                vc.ximage = [NSImage imageNamed:@"rebootImage"];
            } else {
                vc.ximage = [NSImage imageNamed:@"emptyImage"];
            }
            [newMenuItem setView:vc.view];
            [subMenu addItem:newMenuItem];
        }
        
        //
        // Add Bottom Menu Item thats says you need to use Self Patch to patch
        //
        CHMenuViewController *vc1 = [[CHMenuViewController alloc] init];
        
        f = vc1.view.frame;
        f.size.width = 337;
        f.size.height = 35;
        vc1.view.frame = f;
        
        [vc1.view addSubview:vc1.altView];
        
        newMenuItem = [[NSMenuItem alloc] initWithTitle:@"Open MacPatch.app To Patch..." action:NULL keyEquivalent:@""];
        [newMenuItem setView:vc1.view];
        [subMenu addItem:newMenuItem];
        
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:PATCHES_NEEDED_PLIST error:nil];
        if (attrs != nil) {
            [self setLastPatchStatusUpdate:(NSDate*)[attrs objectForKey: NSFileModificationDate]];
        }
        
        // Set User Notification for Reboot
		if ([self patchCount] >= 1)
		{
			NSUserDefaults *ud = [[NSUserDefaults alloc] initWithSuiteName:@"mp.cs.note"];
			[ud setBool:YES forKey:@"patch"];
			if ([self patchNeedsReboot] == YES) {
				[ud setBool:YES forKey:@"reboot"];
			} else {
				[ud setBool:NO forKey:@"reboot"];
			}
			ud = nil;
		}

		dispatch_async(dispatch_get_main_queue(), ^(void) {
			[self->statusMenu update];
		});
    }
}

- (NSDictionary *)readRequiredPatches
{
	@try
	{
		MPClientDB *cdb = [MPClientDB new];
		
		// Query all records
		NSArray *records = [cdb retrieveRequiredPatches];
		qldebug(@"Required patches found %lu.",(unsigned long)records.count);
		
		int needsReboot = 0;
		NSMutableArray *patches = [NSMutableArray new];
		for (RequiredPatch *p in records)
		{
			NSString *restart = (p.patch_reboot == 1) ? @"Y" : @"N";
			[patches addObject:@{@"name":p.patch,@"version":p.patch_version,@"reboot":restart}];
			if (p.patch_reboot == 1) {
				needsReboot++;
			}
		}
		
		return @{@"patches":(NSArray*)patches,@"needsReboot":((needsReboot >= 1) ? @"Y" : @"N")};
	}
	@catch (NSException *exception)
	{
		qlerror(@"%@",exception);
	}

	return @{@"patches":[NSArray array],@"needsReboot":@"N"};
}

- (IBAction)refreshClientStatus:(id)sender
{
    // Should add scan now action and update without opening self patch
    [self showLastCheckIn];
}

#pragma mark -
#pragma mark Open MacPatch
- (IBAction)openMacPatchApplication:(id)sender
{
//	[[NSWorkspace sharedWorkspace] launchAppWithBundleIdentifier:@"gov.llnl.mp.MacPatch"
//														 options:NSWorkspaceLaunchDefault
//								  additionalEventParamDescriptor:nil
//												launchIdentifier:NULL];
	[self openMacPatchAppWithAction:@""];
}

- (void)openMacPatchAppWithAction:(NSString *)action
{
	NSString *cURL = @"macpatch://";
	if ([action isEqualToString:@"PatchScan"]) {
		cURL = @"macpatch://?openAndScan";
	} else if ([action isEqualToString:@"PatchPrefs"]) {
		cURL = @"macpatch://?openAndPatchPrefs";
	}
	
	[[NSWorkspace sharedWorkspace] launchAppWithBundleIdentifier:@"gov.llnl.mp.MacPatch"
															 options:NSWorkspaceLaunchDefault
									  additionalEventParamDescriptor:nil
													launchIdentifier:NULL];
	[NSThread sleepForTimeInterval:1.0];
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:cURL]];
}

#pragma mark -

- (void)killApplication:(NSNumber *)aPID
{
    pid_t pid=[aPID intValue];
    kill(pid,SIGKILL);
	
}

#pragma mark -
#pragma mark Record App Usage Info
- (void)appLaunchNotificationReceived:(NSNotification *)aNotification
{
    if ([[aNotification userInfo] objectForKey:@"NSApplicationName"])
    {
        @try
        {
            NSBundle *b = [NSBundle bundleWithPath:[[aNotification userInfo] objectForKey:@"NSApplicationPath"]];
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:[aNotification userInfo]];
            [userInfo setObject:[[b infoDictionary] objectForKey:@"CFBundleShortVersionString"] forKey:@"CFBundleShortVersionString"];
            AppLaunchObject *alo = [AppLaunchObject appLaunchObjectWithDictionary:userInfo];
            
            logit(lcl_vDebug,@"Application launched: %@ %@ %@",[alo appName],[alo appPath],[alo appVersion]);
            [mpAppUsage insertLaunchDataForApp:[alo appName] appPath:[alo appPath] appVersion:[alo appVersion]];
        }
        @catch (NSException *exception)
        {
            logit(lcl_vError,@"%@",exception);
        }
    }
}

#pragma mark -
#pragma mark App Launch Filter Rules
- (void)appLaunchForFilterNotification:(NSNotification *)aNotification
{
    NSDictionary *note = [aNotification userInfo];
    BOOL launchApp = NO;
    
    if ([self verifyAllow:note]) {
        logit(lcl_vDebug,@"%@ is approved via allow list.",[note objectForKey:@"NSApplicationName"]);
        launchApp = YES;
    } else {
        logit(lcl_vInfo,@"%@ not approved via allow list.",[note objectForKey:@"NSApplicationName"]);
    }
    
    if (![self verifyDeny:note]) {
        logit(lcl_vDebug,@"%@ is approved via deny list.",[note objectForKey:@"NSApplicationName"]);
    } else {
        logit(lcl_vInfo,@"%@ not approved via deny list.",[note objectForKey:@"NSApplicationName"]);
        launchApp = NO;
    }
    
    if (!launchApp) {
        logit(lcl_vDebug,@"Killing application via pid (%@).",[note objectForKey:@"NSApplicationProcessIdentifier"]);
        [self killApplication:[note objectForKey:@"NSApplicationProcessIdentifier"]];
    }
}

- (BOOL)verifyAllow:(NSDictionary *)noteInfo
{
    /* Default the rule to allow all */
    BOOL result = NO;
    if ([[self.appRules objectForKey:@"allow"] count] <= 0) {
        result = YES;
        return result;
    }
    
    for (NSString *r in [self.appRules objectForKey:@"allow"])
    {
        if ([[[noteInfo objectForKey:@"NSApplicationBundleIdentifier"] lowercaseString] isEqualToString:r.lowercaseString]) {
            result = YES;
            break;
        } else if ([[[noteInfo objectForKey:@"NSApplicationBundleIdentifier"]lowercaseString] containsString:r.lowercaseString]) {
            result = YES;
            break;
        } else if ([[[noteInfo objectForKey:@"NSApplicationName"] lowercaseString] isEqualToString:r.lowercaseString]) {
            result = YES;
            break;
        } else if ([[[noteInfo objectForKey:@"NSApplicationName"] lowercaseString] containsString:r.lowercaseString]) {
            result = YES;
            break;
        } else if ([[[noteInfo objectForKey:@"NSApplicationPath"] lowercaseString] isEqualToString:r.lowercaseString]) {
            result = YES;
            break;
        } else if ([[[noteInfo objectForKey:@"NSApplicationPath"] lowercaseString] containsString:r.lowercaseString]) {
            result = YES;
            break;
        }
    }
    return result;
}

- (BOOL)verifyDeny:(NSDictionary *)noteInfo
{
	/* noteInfo object
	 NSApplicationBundleIdentifier = "com.apple.Chess";
	 NSApplicationName = Chess;
	 NSApplicationPath = "/Applications/Chess.app";
	 NSApplicationProcessIdentifier = 35842;
	 NSApplicationProcessSerialNumberHigh = 0;
	 NSApplicationProcessSerialNumberLow = 1651091;
	 NSWorkspaceApplicationKey = "<NSRunningApplication: 0x600003004f30 (com.apple.Chess - 35842)>";
	 */
	
	
    /* Default the rule to deny none */
	NSDictionary *appRule;
    BOOL result = NO;
    if ([[self.appRules objectForKey:@"deny"] count] <= 0) {
        return result;
    }
	
	for (NSDictionary *d in [self.appRules objectForKey:@"deny"])
	{
		if ([d[@"processName"] containsString:@"*"]) {
			NSString *pN = [d[@"processName"] stringByReplacingOccurrencesOfString:@"*" withString:@""];
			if ([[noteInfo objectForKey:@"NSApplicationName"] containsString:pN])
			{
				appRule = [d copy];
				result = YES;
				break;
			}
		} else {
			if ([[noteInfo objectForKey:@"NSApplicationName"] isEqualToString:d[@"processName"]])
			{
				appRule = [d copy];
				result = YES;
				break;
			}
			else if ([[[noteInfo objectForKey:@"NSApplicationPath"] lastPathComponent] isEqualToString:d[@"processName"]])
			{
				appRule = [d copy];
				result = YES;
				break;
			}
		}
		
		
	}
	
	if (result == YES)
	{
		[self showDenyMessage:appRule];
	}
	
	/*
    for (NSString *r in [self.appRules objectForKey:@"deny"])
    {
        if ([[noteInfo objectForKey:@"NSApplicationBundleIdentifier"] isEqualToString:r]) {
            result = YES;
            break;
        } else if ([[noteInfo objectForKey:@"NSApplicationBundleIdentifier"] containsString:r]) {
            result = YES;
            break;
        } else if ([[noteInfo objectForKey:@"NSApplicationName"] isEqualToString:r]) {
            result = YES;
            break;
        } else if ([[noteInfo objectForKey:@"NSApplicationName"] containsString:r]) {
            result = YES;
            break;
        } else if ([[noteInfo objectForKey:@"NSApplicationPath"] isEqualToString:r]) {
            result = YES;
            break;
        } else if ([[noteInfo objectForKey:@"NSApplicationPath"] containsString:r]) {
            result = YES;
            break;
        }
    }
	 */
    return result;
}

- (void)showDenyMessage:(NSDictionary *)rule
{
	NSString *theMessage;
	if (_swResHelpMessage) {
		theMessage = [NSString stringWithFormat:@"%@\n\n%@",rule[@"message"],_swResHelpMessage];
	} else {
		theMessage = [NSString stringWithFormat:@"%@",rule[@"message"]];
	}
	
	[swResMessage setStringValue:theMessage];
	[swResWindow setLevel:NSFloatingWindowLevel];
	[swResWindow makeKeyAndOrderFront:nil];
	[swResWindow center];
	[NSApp arrangeInFront:nil];
	[NSApp activateIgnoringOtherApps:YES];
	
}

#pragma mark -
#pragma mark Logout Method

/*
 Notification Center: System requires patches that need a reboot.
 This method will open a window explaining that the user should
 save their work and patches will be intstall on logout.
*/
- (void)logoutNow
{
    [self.rebootWindow makeKeyAndOrderFront:nil];
    [self.rebootWindow setLevel:kCGMaximumWindowLevel];
    [self.rebootWindow center];
    [NSApp arrangeInFront:self];
    [NSApp activateIgnoringOtherApps:YES];
}

- (IBAction)logoutAndPatch:(id)sender
{
	[self.rebootWindow close];
	
    if (floor(NSAppKitVersionNumber) >= NSAppKitVersionNumber10_9) {
        NSUserDefaults *ud = [[NSUserDefaults alloc] initWithSuiteName:@"mp.cs.note"];
        [ud setBool:NO forKey:@"patch"];
        [ud setBool:NO forKey:@"reboot"];
        ud = nil;
    }
	
	if (![[NSFileManager defaultManager] fileExistsAtPath:MP_AUTHRUN_FILE])
	{
		[@"reboot" writeToFile:MP_AUTHRUN_FILE atomically:YES encoding:NSUTF8StringEncoding error:NULL];
		[[NSFileManager defaultManager] setAttributes:@{@"NSFilePosixPermissions":[NSNumber numberWithUnsignedLong:0777]} ofItemAtPath:MP_AUTHRUN_FILE error:NULL];
	}
    
    /* reboot the system using Apple supplied code
     error = SendAppleEventToSystemProcess(kAERestart);
     error = SendAppleEventToSystemProcess(kAELogOut);
     error = SendAppleEventToSystemProcess(kAEReallyLogOut);
     */
    
    OSStatus error = noErr;
#ifdef DEBUG
    error = SendAppleEventToSystemProcess(kAELogOut);
#else
    error = SendAppleEventToSystemProcess(kAEReallyLogOut);
#endif
}

#pragma mark -
#pragma mark NSUserNotificationCenter

- (void)runMPUserNotificationCenter
{
    // Show Menu Once, then use timer
    [self performSelectorOnMainThread:@selector(showMPUserNotificationCenterMethod)
                           withObject:nil
                        waitUntilDone:NO
                                modes:[NSArray arrayWithObject:NSRunLoopCommonModes]];
    
    dispatch_queue_t gcdQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    double secondsToFire = 1200.0; // 1200.0 = 20 Minutes
    
    _timer = CreateDispatchTimer(secondsToFire, gcdQueue, ^{
        logit(lcl_vInfo, @"Start, Display Patch Data Info in menu.");
        logit(lcl_vDebug, @"Repeats every %f seconds", secondsToFire);
        [self performSelectorOnMainThread:@selector(showMPUserNotificationCenterMethod)
                               withObject:nil
                            waitUntilDone:NO
                                    modes:[NSArray arrayWithObject:NSRunLoopCommonModes]];
    });
}

- (void)showMPUserNotificationCenterMethod
{
	NSUserDefaults *userDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"mp.cs.note"];
	if ([userDefaults objectForKey:@"patch"])
	{
		if ([userDefaults boolForKey:@"patch"] == YES)
		{
			// Show Reboot Patch Notification
			if ([userDefaults objectForKey:@"reboot"])
			{
				if ([userDefaults boolForKey:@"reboot"])
				{
					[self postUserNotificationForReboot];
					return;
				}
			}
			
			// Show Patches Required Notification
			if (self.patchCount >= 1)
			{
				[self postUserNotificationForPatchesWithCount:[@(self.patchCount) stringValue]];
			}
			else
			{
				NSUserNotification *userNote = [[NSUserNotification alloc] init];
				userNote.title = @"Patches Required";
				[[NSUserNotificationCenter defaultUserNotificationCenter] removeDeliveredNotification:userNote];
			}
		}
	}
}

- (void)postUserNotificationForReboot
{
	MPPatching *p = [MPPatching new];
	if ([p patchingForHostIsPaused]) { // If paused, then return
		p = nil;
		return;
	}
	
	qlinfo(@"postUserNotificationForReboot");
	// Look to see if we have posted already, if we have, no need to do it again
	
	for (NSUserNotification *deliveredNote in NSUserNotificationCenter.defaultUserNotificationCenter.deliveredNotifications)
	{
		if ([deliveredNote.title isEqualToString:@"Reboot Patches Required"]) {
			return;
		}
	}
	
	NSUserNotification *userNote = [[NSUserNotification alloc] init];
	userNote.title = @"Reboot Patches Required";
	userNote.informativeText = @"This system requires patches that require a reboot.";
	userNote.actionButtonTitle = @"Reboot";
	userNote.hasActionButton = YES;
	userNote.userInfo = @{ @"originalPointer": @((NSUInteger)userNote) };
	[userNote setValue:@YES forKey:@"_showsButtons"];

	[[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:self];
	[[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:userNote];
	qlinfo(@"postUserNotificationForReboot deliverNotification");
}

- (void)postUserNotificationForPatchesWithCount:(NSString *)aCount
{
	// Look to see if we have posted already, if we have, no need to do it again
	for (NSUserNotification *deliveredNote in NSUserNotificationCenter.defaultUserNotificationCenter.deliveredNotifications)
	{
		if ([deliveredNote.title isEqualToString:@"Patches Required"]) return;
	}
    
    NSUserNotification *userNote = [[NSUserNotification alloc] init];
    userNote.title = @"Patches Required";
    userNote.informativeText = [NSString stringWithFormat:@"This system requires %@ %@.",aCount,
								([aCount intValue] == 1) ? @"Patch" : @"Patches"];
    userNote.actionButtonTitle = @"Patch";
    userNote.hasActionButton = YES;
	[userNote setValue:@YES forKey:@"_showsButtons"];
	
    [[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:self];
    [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:userNote];
}

- (void)postUserNotificationForFVAuthRestart
{
	qldebug(@"postUserNotificationForFVAuthRestart");
	// Look to see if we have posted already, if we have, no need to do it again
	
	for (NSUserNotification *deliveredNote in NSUserNotificationCenter.defaultUserNotificationCenter.deliveredNotifications)
	{
		qlinfo(@"deliveredNote: %@",deliveredNote.title);
		if ([deliveredNote.title isEqualToString:@"Credentials Need Updating"]) {
			qlinfo(@"deliveredNote: %@ already posted.",deliveredNote.title);
			return;
		}
		if ([deliveredNote.title isEqualToString:@"Recovery Key Need Updating"]) {
			qlinfo(@"deliveredNote: %@ already posted.",deliveredNote.title);
			return;
		}
	}
	
	NSDictionary *prefs;
	if ([[NSFileManager defaultManager] fileExistsAtPath:MP_AUTHSTATUS_FILE]) {
		prefs = [NSDictionary dictionaryWithContentsOfFile:MP_AUTHSTATUS_FILE];
		if (![prefs[@"enabled"] boolValue]) {
			return; // Dont post any notifications if not enabled.
		}
    } else {
        return; // Dont post any notifications, not setup.
    }
	
	NSUserNotification *userNote = [[NSUserNotification alloc] init];
	if (prefs[@"outOfSync"]) {
		userNote.title = @"Credentials Need Updating";
		userNote.informativeText = @"The FileVault authrestart credentials are out of sync.";
	}
	if (prefs[@"keyOutOfSync"]) {
		userNote.title = @"Recovery Key Need Updating";
		userNote.informativeText = @"The FileVault authrestart recovery key is out of sync.";
	}
	userNote.actionButtonTitle = @"Update";
	userNote.hasActionButton = YES;
	userNote.userInfo = @{ @"originalPointer": @((NSUInteger)userNote) };
	[userNote setValue:@YES forKey:@"_showsButtons"];

	[[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:self];
	[[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:userNote];
	qlinfo(@"postUserNotificationForFVAuthRestart deliverNotification");
}

- (void)userNotificationReceived:(NSNotification *)notification
{
	qldebug(@"[userNotificationReceived]: %@",notification.name);
    if ([notification.name isEqualToString: kShowPatchesRequiredNotification])
    {
        NSString *pc = [@(self.patchCount) stringValue];
        [self postUserNotificationForPatchesWithCount:pc];
    }
    else if ([notification.name isEqualToString: kRebootRequiredNotification])
    {
        [self postUserNotificationForReboot];
    }
    else if ([notification.name isEqualToString: kRefreshStatusIconNotification])
    {
        [self displayPatchDataMethod];
    }
	else if ([notification.name isEqualToString: kRequiredPatchesChangeNotification])
	{
		[self displayPatchDataMethod];
	}
	else if ([notification.name isEqualToString: @"kFileVaultUserOutOfSync"])
	{
		[self postUserNotificationForFVAuthRestart];
	}
    else
    {
        return;
    }
}

- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center shouldPresentNotification:(NSUserNotification *)notification
{
    return YES;
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)notification
{
	qlinfo(@"didActivateNotification");
    if (notification.activationType == NSUserNotificationActivationTypeActionButtonClicked)
    {
        if ([notification.actionButtonTitle isEqualToString:@"Patch"])
		{
			qlinfo(@"didActivateNotification openMacPatchApplication:nil");
			
			NSUserDefaults *ud = [[NSUserDefaults alloc] initWithSuiteName:@"mp.cs.note"];
			[ud setBool:NO forKey:@"patch"];
			ud = nil;
			qlinfo(@"didActivateNotification openMacPatchAppWithAction:PatchScan");
			[self openMacPatchAppWithAction:@"PatchScan"];
        }
		
		if ([notification.actionButtonTitle isEqualToString:@"Reboot"])
		{
			[self logoutNow];
		}
		
		if ([notification.actionButtonTitle isEqualToString:@"Update"])
		{
			qlinfo(@"didActivateNotification openMacPatchAppWithAction:PatchPrefs");
			[self openMacPatchAppWithAction:@"PatchPrefs"];
        }
    }
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didDeliverNotification:(NSUserNotification *)notification
{
	//qlinfo(@"didDeliverNotification");
    //if ([notification.actionButtonTitle isEqualToString:@"Patch"])
	//{
        // Dont show patch info if reboot is required.
		/*
        if ([[NSFileManager defaultManager] fileExistsAtPath:MP_AUTHRUN_FILE])
		{
            [[NSUserNotificationCenter defaultUserNotificationCenter] removeDeliveredNotification:notification];
        }
		 */
    //}
}

- (IBAction)loadWhatsNewWebView:(id)sender
{	
	[_wkWebView.enclosingScrollView setHasVerticalScroller:NO];
	NSString *filePath = [[NSBundle mainBundle] pathForResource:@"banner" ofType:@"html" inDirectory:@"html"];
	NSString *htmlStringBase = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:NULL];
	[_wkWebView loadHTMLString:htmlStringBase baseURL:[[NSBundle mainBundle] resourceURL]];
}


#pragma mark - Web URL Info

- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation
{
	//NSLog(@"didCommitNavigation");
}

- (void)webView:(WKWebView *)webView
decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
	if (navigationAction.navigationType == WKNavigationTypeLinkActivated)
	{
		[[NSWorkspace sharedWorkspace] openURL:[navigationAction.request URL]];
		decisionHandler(WKNavigationActionPolicyCancel);
	}
	
	decisionHandler(WKNavigationActionPolicyAllow);
}

#pragma mark - Software Restrictions

- (void)updateSoftwareRestrictionRules
{
	double secondsToFire = 60.0; // Every 1 min
	logit(lcl_vInfo, @"Start Software Rules Update Thread");
	logit(lcl_vInfo, @"Run every %f", secondsToFire);
	
	// Show Menu Once, then use timer
	[self performSelectorOnMainThread:@selector(processSoftwareRules)
						   withObject:nil
						waitUntilDone:NO
								modes:@[NSRunLoopCommonModes]];
	
	dispatch_queue_t gcdQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	
	_timerSWRules = CreateDispatchTimer(secondsToFire, gcdQueue, ^{
		logit(lcl_vInfo, @"Start, Software Rules Update Thread");
		logit(lcl_vDebug, @"Repeats every %f seconds", secondsToFire);
		[self performSelectorOnMainThread:@selector(processSoftwareRules)
							   withObject:nil
							waitUntilDone:NO
									modes:@[NSRunLoopCommonModes]];
	});
}

- (void)processSoftwareRules
{
	@autoreleasepool
	{
		NSMutableDictionary *_rules = [NSMutableDictionary dictionaryWithDictionary:@{@"allow":@[],@"deny":@[]}];
		if ([[NSFileManager defaultManager] fileExistsAtPath:SW_RESTRICTIONS_PLIST])
		{
			NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:SW_RESTRICTIONS_PLIST];
			if (d[@"rules"])
			{
				[_rules setObject:d[@"rules"] forKey:@"deny"];
			}
		}
		
		appRules = _rules;
		
		// Process Prefs ...
		NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:APP_PREFS_PLIST];
		if (prefs[@"denyHelpStringMessage"])
		{
			_swResHelpMessage = prefs[@"denyHelpStringMessage"];
		}
	}
}

- (IBAction)closeSWResWindow:(id)sender
{
	[swResWindow close];
}

@end
