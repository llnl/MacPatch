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


NSString * const kMenuIconNorml		= @"mp3Image";
NSString * const kMenuIconAlert		= @"mp3ImageAlert";
//NSString * const kMenuIconNorml		= @"mpmenubar_normal";
//NSString * const kMenuIconAlert		= @"mpmenubar_alert2";


// Private Methods
@interface MPClientStatusAppDelegate ()
{
	MPSettings *settings;
}

// Helper
- (void)connect;
- (int)connect:(NSError **)err;
- (void)cleanup;
- (void)connectionDown:(NSNotification *)notification;

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

#pragma mark UI Events
-(void)awakeFromNib
{
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
	
	[self displayPatchDataMethod]; // Show needed patches
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

#pragma mark -
#pragma mark MPWorker
- (void)connect
{
    // Use mach ports for communication, since we're local.
    NSConnection *connection = [NSConnection connectionWithRegisteredName:kMPWorkerPortName host:nil];
    
    [connection setRequestTimeout: 60.0];
    [connection setReplyTimeout: 1800.0]; //30 min to install
    
    @try {
        proxy = [connection rootProxy];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(connectionDown:) name:NSConnectionDidDieNotification object:connection];
        
        [proxy setProtocolForProxy: @protocol(MPWorkerServer)];
        BOOL successful;
        for (int i = 0; i < 3; i++)
        {
            successful = [proxy registerClient:self];
            if (!successful) {
                if (i == 3) {
                    NSAlert *alert = [NSAlert alertWithMessageText:@"Error"
                                                     defaultButton:@"OK" alternateButton:nil
                                                       otherButton:nil
                                         informativeTextWithFormat:@"Unable to connect to helper application. Please try logging out and logging back in to resolve the issue."];
                    
                    [[NSRunningApplication currentApplication] activateWithOptions:NSApplicationActivateIgnoringOtherApps];
                    [alert performSelectorOnMainThread:@selector(runModal) withObject:nil waitUntilDone:NO];
                }
                [self cleanup];
            } else {
                break;
            }
        }
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"Could not connect to MPHelper: %@", e);
        [self cleanup];
    }
}

- (int)connect:(NSError **)err
{
    // Use mach ports for communication, since we're local.
    NSConnection *connection = [NSConnection connectionWithRegisteredName:kMPWorkerPortName host:nil];
    
    [connection setRequestTimeout: 60.0];
    [connection setReplyTimeout: 1800.0]; //30 min to install
    
    @try {
        proxy = [connection rootProxy];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(connectionDown:) name:NSConnectionDidDieNotification object:connection];
        
        [proxy setProtocolForProxy: @protocol(MPWorkerServer)];
        BOOL successful;
        for (int i = 0; i < 3; i++)
        {
            successful = [proxy registerClient:self];
            if (!successful) {
                if (i == 3) {
                    NSAlert *alert = [NSAlert alertWithMessageText:@"Error"
                                                     defaultButton:@"OK" alternateButton:nil
                                                       otherButton:nil
                                         informativeTextWithFormat:@"Unable to connect to helper application. Please try logging out and logging back in to resolve the issue."];
                    
                    [[NSRunningApplication currentApplication] activateWithOptions:NSApplicationActivateIgnoringOtherApps];
                    [alert performSelectorOnMainThread:@selector(runModal) withObject:nil waitUntilDone:NO];
                    
                    NSMutableDictionary *details = [NSMutableDictionary dictionary];
                    [details setValue:@"Unable to connect to helper application. Please try logging out and logging back in to resolve the issue." forKey:NSLocalizedDescriptionKey];
                    if (err != NULL)  *err = [NSError errorWithDomain:@"world" code:1 userInfo:details];
                }
                [self cleanup];
            } else {
                break;
            }
        }
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"Could not connect to MPHelper: %@", e);
        [self cleanup];
    }
    
    return 0;
}

- (void)cleanup
{
    if (proxy)
    {
        NSConnection *connection = [proxy connectionForProxy];
        [connection invalidate];
        proxy = nil;
    }
    
}

- (void)connectionDown:(NSNotification *)notification
{
    logit(lcl_vTrace,@"MPWorker connection down");
    [self cleanup];
}

#pragma mark - Worker Methods

- (NSDictionary *)getAgentCheckInDataViaProxy
{
	NSDictionary *result = nil;
	NSError *error = nil;
	if (!proxy) {
		[self connect:&error];
		if (error) {
			logit(lcl_vError,@"%@",error.localizedDescription);
			goto done;
		}
		if (!proxy) {
			logit(lcl_vError,@"Could not create proxy object.");
			goto done;
		}
	}
	
	@try
	{
		result = [proxy clientCheckInData];
	}
	@catch (NSException *e) {
		logit(lcl_vError,@"Colect client checkin data, %@", e);
	}
	
done:
	[self cleanup];
	return result;
}

- (void)updateClientGroupSettingViaProxy:(NSDictionary *)settingsRevs
{
	NSError *error = nil;
	if (!proxy) {
		[self connect:&error];
		if (error) {
			logit(lcl_vError,@"%@",error.localizedDescription);
			goto done;
		}
		if (!proxy) {
			logit(lcl_vError,@"Could not create proxy object.");
			goto done;
		}
	}
	
	@try
	{
		[proxy updateClientGroupSettingViaHelper:settingsRevs];
	}
	@catch (NSException *e) {
		logit(lcl_vError,@"Update client group settings failed. %@", e);
	}
	
done:
	[self cleanup];
	return;
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
    [NSThread detachNewThreadSelector:@selector(performClientCheckInThread) toTarget:self withObject:nil];
}

- (void)performClientCheckInThread
{
    @autoreleasepool
    {
        BOOL didRun = NO;
        didRun = [self performClientCheckInMethod];
		
		dispatch_sync(dispatch_get_main_queue(), ^()
		{
			NSAlert *alert = [[NSAlert alloc] init];
			[alert addButtonWithTitle:@"OK"];
			if (didRun == NO) {
				[alert setMessageText:@"Error with check-in"];
				[alert setInformativeText:@"There was a problem checking in with the server. Please review the client status logs for cause."];
				[alert setAlertStyle:NSCriticalAlertStyle];
			} else {
				[alert setMessageText:@"Client check-in"];
				[alert setInformativeText:@"Client check-in was successful."];
				[alert setAlertStyle:NSInformationalAlertStyle];
			}
			
			[alert runModal];
		});
    }
}

// Performs a client checkin
- (BOOL)performClientCheckInMethod
{
	NSDictionary *agentData = [self getAgentCheckInDataViaProxy];
    if (agentData) {
        NSDictionary *revsDict;
        NSError *wsError = nil;
        MPRESTfull *rest = [[MPRESTfull alloc] init];
        revsDict = [rest postClientCheckinData:agentData error:&wsError];
        if (wsError)
        {
            logit(lcl_vError,@"Error posting client check in data.");
            logit(lcl_vError,@"%@",wsError.localizedDescription);
            return FALSE;
        }
        
        // CEH - Update Settings once implemented via mpworker
		[self updateClientGroupSettingViaProxy:revsDict];
        
        // Update the UI info
        [self showLastCheckInMethod];
    }
    
    return TRUE;
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
			NSLog(@"d: %@",d);
            newMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
            vc = [[CHMenuViewController alloc] init];
            [vc addTitle:d[@"name"] version:d[@"version"]];
            if ([d[@"reboot"] isEqualToString:@"Y"])
            {
				NSLog(@"Add reboot image");
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
		FMXDatabaseManager *manager = [FMXDatabaseManager sharedManager];
		[manager registerDefaultDatabaseWithPath:MP_AGENT_DB migration:nil];
		FMDatabase *db = [manager defaultDatabase];
		[db open];
		
		// Query all records
		NSArray *records = [[DBRequiredPatches query] allRecords];
		qldebug(@"Required patches found %lu.",(unsigned long)records.count);
		[db close];
		
		int needsReboot = 0;
		NSMutableArray *patches = [NSMutableArray new];
		for (DBRequiredPatches *p in records)
		{
			NSString *restart = ([p.patch_reboot integerValue] == 1) ? @"Y" : @"N";
			[patches addObject:@{@"name":p.patch,@"version":p.patch_version,@"reboot":restart}];
			if ([p.patch_reboot integerValue] == 1) {
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
	[[NSWorkspace sharedWorkspace] launchAppWithBundleIdentifier:@"gov.llnl.mp.MacPatch"
														 options:NSWorkspaceLaunchDefault
								  additionalEventParamDescriptor:nil
												launchIdentifier:NULL];
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
    /* Default the rule to deny none */
    BOOL result = NO;
    if ([[self.appRules objectForKey:@"deny"] count] <= 0) {
        return result;
    }
    
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
    return result;
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
	// Look to see if we have posted already, if we have, no need to do it again
	for (NSUserNotification *deliveredNote in NSUserNotificationCenter.defaultUserNotificationCenter.deliveredNotifications)
	{
		if ([deliveredNote.title isEqualToString:@"Reboot Patches Required"]) return;
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
    userNote.informativeText = [NSString stringWithFormat:@"This system requires %@ patche(s).",aCount];
    userNote.actionButtonTitle = @"Patch";
    userNote.hasActionButton = YES;
	[userNote setValue:@YES forKey:@"_showsButtons"];
	
    [[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:self];
    [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:userNote];
}

- (void)userNotificationReceived:(NSNotification *)notification
{
	qlinfo(@"[userNotificationReceived]: %@",notification.name);
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
    if (notification.activationType == NSUserNotificationActivationTypeActionButtonClicked)
    {
        if ([notification.actionButtonTitle isEqualToString:@"Patch"])
		{
			NSUserDefaults *ud = [[NSUserDefaults alloc] initWithSuiteName:@"mp.cs.note"];
			[ud setBool:NO forKey:@"patch"];
			ud = nil;
			[self openMacPatchApplication:nil];
        }
		
        if ([notification.actionButtonTitle isEqualToString:@"Reboot"]) [self logoutNow];
    }
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didDeliverNotification:(NSUserNotification *)notification
{
    if ([notification.actionButtonTitle isEqualToString:@"Patch"]) {
        // Dont show patch info if reboot is required.
		/*
        if ([[NSFileManager defaultManager] fileExistsAtPath:MP_AUTHRUN_FILE])
		{
            [[NSUserNotificationCenter defaultUserNotificationCenter] removeDeliveredNotification:notification];
        }
		 */
    }
}

@end
