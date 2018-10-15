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
#import "VDKQueue.h"
#import "EventToSend.h"

NSString * const kMenuIconNorml		= @"mpmenubar_normal";
NSString * const kMenuIconAlert		= @"mpmenubar_alert2";

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

// Worker Methods
- (void)disableASUSSchedule;

// Watch Patch Status/Needed
- (void)setupWatchedFolder;
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

#pragma mark Properties
@synthesize window;
@synthesize checkInStatusMenuItem;
@synthesize checkPatchStatusMenuItem;
@synthesize selfVersionInfoMenuItem;
@synthesize MPVersionInfoMenuItem;
@synthesize checkAgentAndUpdateMenuItem;

@synthesize openASUS;
@synthesize asusAlertOpen;

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
    
    // Turn off Scheduled Software Updates
    [self setupWatchedFolder];
    [self setAsusAlertOpen:NO];
    [self disableASUSSchedule];
    
    statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    [statusItem setMenu:statusMenu];
    [statusItem setImage:[NSImage imageNamed:kMenuIconNorml]];
    [statusItem setHighlightMode:YES];
    
    // App Version Info
    [selfVersionInfoMenuItem setTitle:[NSString stringWithFormat:@"Status App Version: %@",[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]]];
    NSDictionary *_mpVerDict = [NSDictionary dictionaryWithContentsOfFile:AGENT_VER_PLIST];
	NSString *_versionStr = [NSString stringWithFormat:@"%@.%@.%@.%@",_mpVerDict[@"major"],_mpVerDict[@"minor"],_mpVerDict[@"bug"],_mpVerDict[@"build"]];
    [MPVersionInfoMenuItem setTitle:[NSString stringWithFormat:@"MacPatch Version: %@",_versionStr]];
    
    
    [[NSDistributedNotificationCenter defaultCenter] addObserver: self
                                                        selector: @selector(userNotificationReceived:)
                                                            name: kShowPatchesRequiredNotification
                                                          object: nil];
    [[NSDistributedNotificationCenter defaultCenter] addObserver: self
                                                        selector: @selector(userNotificationReceived:)
                                                            name: kRebootRequiredNotification
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
    [MPLog setupLogging:_logFile level:lcl_vDebug];
    
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
    //[dc addObserver:self selector:@selector(notificationReceived:) name:NSWorkspaceWillLaunchApplicationNotification object:[NSWorkspace sharedWorkspace]];
    
    // Setup App monitoring
    mpAppUsage = [[MPAppUsage alloc] init];
    [mpAppUsage cleanDB]; // Removes Entries Where App Version is NULL
    
    [dc addObserver:self selector:@selector(appLaunchNotificationReceived:) name:NSWorkspaceWillLaunchApplicationNotification object:[NSWorkspace sharedWorkspace]];
    [dc addObserver:self selector:@selector(appLaunchForFilterNotification:) name:NSWorkspaceWillLaunchApplicationNotification object:[NSWorkspace sharedWorkspace]];
    
    // Start Last CheckIn Thread, update every 10 min
    [self showLastCheckIn];
    
    // This will monitor for hits, when to update the patch status flags
    [self displayPatchData];
    
    // Run Notification Timer
    [self runMPUserNotificationCenter];
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"allowSoftwareUpdate"]) {
        [self setOpenASUS:[[NSUserDefaults standardUserDefaults] boolForKey:@"allowSoftwareUpdate"]];
    } else {
        [self setOpenASUS:NO];
    }
    
    appRules = @{@"allow":@[],@"deny":@[]};
}

- (void)applicationWillTerminate:(NSNotification *)note
{
    
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
		//NSInteger menuCount = [menu numberOfItems];
        //[menu insertItem:menuItem15 atIndex:([menu numberOfItems] - 2)];
		
        [menu addItem:menuItem15];
        [menuItem15 setEnabled:YES];
        [menuItem15 setHidden:NO];
        //[menu insertItem:menuItem16 atIndex:([menu numberOfItems] - 1)];
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

- (void)removeStatusFiles
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
        [proxy removeStatusFilesViaHelper];
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"Trying to set the logging level, %@", e);
    }
    
done:
    [self cleanup];
    return;
}

- (void)disableASUSSchedule
{
    NSError *error = nil;
    if (!proxy) {
        [self connect:&error];
        if (error) {
            logit(lcl_vError,@"disableSoftwareUpdateScheduleViaHelper error 1001: %@",[error localizedDescription]);
        }
        if (!proxy) {
            logit(lcl_vError,@"disableSoftwareUpdateScheduleViaHelper error 1002: Unable to get proxy object.");
            goto done;
        }
    }
    
    @try
    {
        logit(lcl_vDebug,@"[proxy run disableSoftwareUpdateScheduleViaHelper]");
        [proxy disableSoftwareUpdateScheduleViaHelper];
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"disableSoftwareUpdateScheduleViaHelper error: %@", e);
    }
    
done:
    [self cleanup];
}

- (int)writeDataToFile:(id)data file:(NSString *)aFile
{
	int result = -1;
	if (!proxy) {
		[self connect];
		if (!proxy) goto done;
	}
	
	@try
	{
		result = [proxy writeDataToFileViaHelper:data toFile:aFile];
	}
	@catch (NSException *e) {
		logit(lcl_vError,@"Trying to write data to file(%@). %@",aFile, e);
	}
	
done:
	[self cleanup];
	return result;
}

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
	NSString *_versionStr = [NSString stringWithFormat:@"%@.%@.%@",mpVerDict[@"major"],mpVerDict[@"minor"],mpVerDict[@"bug"]];
    logit(lcl_vDebug,@"mpVerDict: %@", mpVerDict);
    
    NSString *verInfo = [NSString stringWithFormat:@"Version: %@\nBuild: %@\nClient ID: %@",
                         _versionStr,
                         [mpVerDict objectForKey:@"build"],
                         [MPSystemInfo clientUUID]];
    
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
- (IBAction)closeRebootWindow:(id)sender {
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
        
        [alert performSelectorOnMainThread:@selector(runModal) withObject:nil waitUntilDone:NO];
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
    double secondsToFire = 300.0;
    logit(lcl_vInfo, @"Start Last CheckIn Data Thread");
    logit(lcl_vInfo, @"Run every %f", secondsToFire);
    
    // Show Menu Once, then use timer
    [self performSelectorOnMainThread:@selector(showLastCheckInMethod)
                           withObject:nil
                        waitUntilDone:NO
                                modes:[NSArray arrayWithObject:NSRunLoopCommonModes]];
    
    dispatch_queue_t gcdQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    
    _timer = CreateDispatchTimer(secondsToFire, gcdQueue, ^{
        logit(lcl_vInfo, @"Start, Display Last CheckIn Data in menu.");
        logit(lcl_vDebug, @"Repeats every %f seconds", secondsToFire);
        [self performSelectorOnMainThread:@selector(showLastCheckInMethod)
                               withObject:nil
                            waitUntilDone:NO
                                    modes:[NSArray arrayWithObject:NSRunLoopCommonModes]];
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
        if ([result objectForKey:@"data"]) {
            data = [result objectForKey:@"data"];
        }
        
        logit(lcl_vDebug,@"%@",result);
        
        if (wsErr) {
            logit(lcl_vError,@"%@",wsErr.localizedDescription);
        }
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
    double secondsToFire = 175.0;
    
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
        
        NSArray  *data = [[NSKeyedUnarchiver unarchiveObjectWithFile:PATCHES_NEEDED_PLIST] mutableCopy];
        NSString *subMenuTitle = [NSString stringWithFormat:@"Patches Needed: %d ",(int)[data count]];
        
        // This is for Mac OS X 10.8 support
        // Display notification based on this value
        NSArray *filteredarray = [data filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"(restart == %@)", @"Yes"]];
        if ([filteredarray count] >=1) {
            self.patchNeedsReboot = YES;
        }
        
        // If No Patches ...
        if (!data)
        {
            [self setPatchCount:0];
            [statusItem setImage:[NSImage imageNamed:kMenuIconNorml]];
            [checkPatchStatusMenuItem setTitle:@"Patches Needed: 0"];
            [checkPatchStatusMenuItem setSubmenu:NULL];
            
            if (floor(NSAppKitVersionNumber) >= NSAppKitVersionNumber10_9)
            {
                NSUserDefaults *ud = [[NSUserDefaults alloc] initWithSuiteName:@"mp.cs.note"];
                if ([ud objectForKey:@"reboot"] && [ud objectForKey:@"patch"]) {
                    if ([ud boolForKey:@"reboot"] == YES) {
                        [ud setBool:NO forKey:@"patch"];
                        [ud setBool:NO forKey:@"reboot"];
                        for (NSUserNotification *nox in [[NSUserNotificationCenter defaultUserNotificationCenter] deliveredNotifications]) {
                            if ([nox.title isEqualToString:@"Reboot Patches Required"]) {
                                [[NSUserNotificationCenter defaultUserNotificationCenter] removeDeliveredNotification:nox];
                            }
                        }
                    }
                }
                ud = nil;
            }
            
            [statusMenu update];
            return;
        }
        else if ([data count] <= 0)
        {
            [self setPatchCount:[data count]];
            [statusItem setImage:[NSImage imageNamed:kMenuIconNorml]];
            [checkPatchStatusMenuItem setTitle:@"Patches Needed: 0"];
            [checkPatchStatusMenuItem setSubmenu:NULL];
            [statusMenu update];
            
            // Remove Notifications
            if (floor(NSAppKitVersionNumber) >= NSAppKitVersionNumber10_9)
            {
                NSUserDefaults *ud = [[NSUserDefaults alloc] initWithSuiteName:@"mp.cs.note"];
                [ud setBool:NO forKey:@"patch"];
                [ud setBool:NO forKey:@"reboot"];
                for (NSUserNotification *nox in [[NSUserNotificationCenter defaultUserNotificationCenter] deliveredNotifications]) {
                    if ([nox.title isEqualToString:@"Reboot Patches Required"]) {
                        [[NSUserNotificationCenter defaultUserNotificationCenter] removeDeliveredNotification:nox];
                    }
                }
                [ud synchronize];
                ud = nil;
            }
            
            return;
        }
        else
        {
            [self setPatchCount:[data count]];
            [statusItem setImage:[NSImage imageNamed:kMenuIconAlert]];
        }
        
        [checkPatchStatusMenuItem setTitle:subMenuTitle];
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
        for (NSDictionary *d in data)
        {
            newMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
            vc = [[CHMenuViewController alloc] init];
            [vc addTitle:[d objectForKey:@"patch"] version:[d objectForKey:@"version"]];
            if ([[[d objectForKey:@"restart"] uppercaseString] isEqualTo:@"TRUE"] || [[[d objectForKey:@"restart"] uppercaseString] isEqualTo:@"YES"])
            {
                vc.ximage = [NSImage imageNamed:@"RestartReq.tif"];
            } else {
                vc.ximage = [NSImage imageNamed:@"empty.tif"];
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
        
        newMenuItem = [[NSMenuItem alloc] initWithTitle:@"Open Self Patch To Patch..." action:NULL keyEquivalent:@""];
        [newMenuItem setView:vc1.view];
        [subMenu addItem:newMenuItem];
        
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:PATCHES_NEEDED_PLIST error:nil];
        if (attrs != nil) {
            [self setLastPatchStatusUpdate:(NSDate*)[attrs objectForKey: NSFileModificationDate]];
        }
        
        // Set User Notification for Reboot
        if (floor(NSAppKitVersionNumber) >= NSAppKitVersionNumber10_9) {
            if ([self patchCount] >= 1) {
                NSUserDefaults *ud = [[NSUserDefaults alloc] initWithSuiteName:@"mp.cs.note"];
                [ud setBool:YES forKey:@"patch"];
                if ([self patchNeedsReboot] == YES) {
                    [ud setBool:YES forKey:@"reboot"];
                } else {
                    [ud setBool:NO forKey:@"reboot"];
                }
                ud = nil;
            }
        }
        
        [statusMenu update];
    }
}

- (IBAction)refreshClientStatus:(id)sender
{
    // Should add scan now action and update without opening self patch
    [self showLastCheckIn];
}

#pragma mark -
#pragma mark Open SelfPatch
- (IBAction)openSelfPatchApplications:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURLs:[NSArray arrayWithObject:[NSURL fileURLWithPath:SELF_PATCH_PATH]]
                    withAppBundleIdentifier:@""
                                    options:NSWorkspaceLaunchDefault
             additionalEventParamDescriptor:nil
                          launchIdentifiers:NULL];
}

#pragma mark -
#pragma mark Kill SoftwareUpdate GUI App
- (void)requestForLaunchingSoftwareUpdate:(NSNumber *)aPID
{
    [NSApp activateIgnoringOtherApps:YES];

    [self killApplication:aPID];
    if (asusAlertOpen == YES)
        return;
    
    NSAlert *alert;
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"allowSoftwareUpdate"]) {
        alert = [NSAlert alertWithMessageText:@"Software Update"
                                defaultButton:@"Open Self Patch"
                              alternateButton:@"Open Software Update"
                                  otherButton:@"Cancel"
                    informativeTextWithFormat:@"To help ensure patch compatibility for this system, updates are now handled by the \"Self Patch\" application.\n\nWarning: Applying patches using Software Update can screw up your system if you have disk encryption installed."];
    } else {
        alert = [NSAlert alertWithMessageText:@"Software Update"
                                defaultButton:@"Open Self Patch"
                              alternateButton:nil
                                  otherButton:@"Cancel"
                    informativeTextWithFormat:@"To help ensure patch compatibility for this system, updates are now handled by the \"Self Patch\" application."];
    }
        
    [self setAsusAlertOpen:YES];
    NSInteger res = [alert runModal];
    if (res == NSAlertDefaultReturn) {
        [self openSelfPatchApplications:nil];
        [self setAsusAlertOpen:NO];
    } else if (res == NSAlertAlternateReturn) {
        [self openSoftwareUpdateApplication:nil];
        [self setAsusAlertOpen:NO];
    } else {
        [self setAsusAlertOpen:NO];
    }
}

- (void)killApplication:(NSNumber *)aPID
{
    pid_t pid=[aPID intValue];
    kill(pid,SIGKILL);
}

- (void)openSoftwareUpdateApplication:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURLs:[NSArray arrayWithObject:[NSURL fileURLWithPath:ASUS_APP_PATH]]
                    withAppBundleIdentifier:@""
                                    options:NSWorkspaceLaunchDefault
             additionalEventParamDescriptor:nil
                          launchIdentifiers:NULL];
}

#pragma mark - Software Catalog

- (IBAction)openSoftwareCatalogApplications:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURLs:[NSArray arrayWithObject:[NSURL fileURLWithPath:SWDIST_APP_PATH]]
                    withAppBundleIdentifier:@""
                                    options:NSWorkspaceLaunchDefault
             additionalEventParamDescriptor:nil
                          launchIdentifiers:NULL];
}

#pragma mark -
#pragma mark Record App Usage Info
- (void)appLaunchNotificationReceived:(NSNotification *)aNotification
{
    if ([[aNotification userInfo] objectForKey:@"NSApplicationName"])
    {
        @try
        {
            if ([[[aNotification userInfo] objectForKey:@"NSApplicationPath"] isEqualToString:ASUS_APP_PATH]) {
                NSNumber *_pid = [[aNotification userInfo] objectForKey:@"NSApplicationProcessIdentifier"];
                [self requestForLaunchingSoftwareUpdate:_pid];
            }
            
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
#pragma mark Critical Patches Window
- (void)setupPopDownButton
{
	
	NSMenu *menu = [(NSPopUpButton *)criticalWinPopUpDown menu];
	[menu removeAllItems];
	
	// Add the image menu item back to the first menu item.
	NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:@"Not Now" action:nil keyEquivalent:@""];
	[menu addItem:menuItem];
	
	NSMenuItem *menuItem1 = [[NSMenuItem alloc] initWithTitle:@"Remind in 1 hour" action:@selector(notNow:) keyEquivalent:@""];
	[menuItem1 setTag:3600]; //3600 1hour
	[menu insertItem:menuItem1 atIndex:1];
	
	NSMenuItem *menuItem2 = [[NSMenuItem alloc] initWithTitle:@"Remind in 2 hours" action:@selector(notNow:) keyEquivalent:@""];
	[menuItem2 setTag:7200]; //7200 2hours
	[menu insertItem:menuItem2 atIndex:2];
	
	NSMenuItem *menuItem3 = [[NSMenuItem alloc] initWithTitle:@"Remind me tomorrow" action:@selector(notNow:) keyEquivalent:@""];
	[menuItem3 setTag:86400]; //86400 24hours
	[menu insertItem:menuItem3 atIndex:3];
	
	criticalWinPopUpDown.menu = menu;
	[criticalWinPopUpDown selectItemAtIndex:0];
	/*
	 dispatch_async(dispatch_get_main_queue(), ^(void)
	 {
	 });
	 */
}

- (void)readCriticalUpdatesFile
{
	if ([[NSFileManager defaultManager] fileExistsAtPath:MP_CRITICAL_UPDATES_PLIST])
	{
		NSArray *updatesFromFile = [NSArray arrayWithContentsOfFile:MP_CRITICAL_UPDATES_PLIST];
		[self.criticalUpdates removeAllObjects];
		[self.criticalUpdates addObjectsFromArray:updatesFromFile];
	}
	// No Timer is set, open window
	if (self.criticalUpdates.count >= 1)
	{
		if (!showCriticalWindowAtDate)
		{
			[self showCriticalWindow:nil];
		}
	}
	else
	{
		if (criticalUpdatesTimer)
		{
			[criticalUpdatesTimer invalidate];
			criticalUpdatesTimer = nil;
		}
	}
}


- (IBAction)showCriticalWindow:(id)sender
{
	[self setupPopDownButton]; // Setup Menu items for critical updates window
	
	NSImage *bg = [[NSImage alloc] initWithSize:[criticalWindow frame].size];
	// Begin drawing into our main image
	[bg lockFocus];
	
	// Background Color
	[[NSColor colorWithRed:0.93 green:0.93 blue:0.93 alpha:1.0] set];
	NSRectFill(NSMakeRect(0, 0, [bg size].width, [bg size].height));
	
	// Border Color
	[[NSColor colorWithRed:0.74 green:0.36 blue:0.36 alpha:1.0] set];
	
	NSRect bounds = NSMakeRect(0, 0, [criticalWindow frame].size.width, [criticalWindow frame].size.height);
	NSBezierPath *border = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:8 yRadius:8];
	[border setLineWidth:6.0];
	[border stroke];
	[bg unlockFocus];
	
	[criticalWindow setBackgroundColor:[NSColor colorWithPatternImage:bg]];
	[criticalWindow makeKeyAndOrderFront:nil];
	[criticalWindow setLevel:kCGMaximumWindowLevel];
	[NSApp arrangeInFront:self];
	[NSApp activateIgnoringOtherApps:YES];
	
	dispatch_async(dispatch_get_main_queue(), ^(void)
				   {
					   [self->criticalWinBodyText setHidden:NO];
					   [self->criticalWinProgressText setHidden:YES];
					   [self->criticalWinProgress setHidden:YES];
					   self->criticalWinPopUpDown.enabled = YES;
					   self->criticalWinPopUpDown.hidden = NO;
					   self->criticalWinInstallButton.enabled = YES;
					   self->criticalWinInstallButton.hidden = NO;
					   self->criticalWinRebootButton.hidden = YES;
				   });
}

// Not Now, will close the window and reschedule the notification
// for the duration set by the user.
- (IBAction)notNow:(id)sender
{
	if (self.criticalUpdates.count <= 0)
	{
		[criticalWindow close];
		return;
	}
	
	NSMenuItem *i = sender;
	showCriticalWindowAtDate = [NSDate dateWithTimeIntervalSinceNow:i.tag];
	criticalUpdatesTimer = [[NSTimer alloc]
							initWithFireDate: showCriticalWindowAtDate
							interval:1.0f
							target:self
							selector:@selector(showCriticalWindow:)
							userInfo:nil
							repeats:NO];
	
	[[NSRunLoop currentRunLoop] addTimer:criticalUpdatesTimer forMode:NSDefaultRunLoopMode];
	[criticalWindow close];
}

- (IBAction)rebootNow:(id)sender
{
	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText:@"Rebooting System"];
	[alert setInformativeText:@"Please make sure all data is saved before continuing."];
	[alert addButtonWithTitle:@"OK"];
#ifdef DEBUG
	[alert addButtonWithTitle:@"Cancel"];
#endif
	[alert setAlertStyle:NSCriticalAlertStyle];
	
	if ([alert runModal] == NSAlertFirstButtonReturn)
	{
		// OK clicked, delete the record
		[criticalWindow close];
		OSStatus error = noErr;
		error = SendAppleEventToSystemProcess(kAERestart);
		
		if (error == noErr) {
			logit(lcl_vInfo,@"Computer is going to restart now!");
			[NSApp terminate:self];
		} else {
			logit(lcl_vError,@"Computer wouldn't restart: %d", (int)error);
		}
		return;
	}
}

- (IBAction)installPatch:(id)sender
{
	[self readCriticalUpdatesFile];
	logit(lcl_vInfo,@"criticalUpdates: %@",criticalUpdates);
	
	
	// Build array of patches to install
	NSMutableArray *patchesToInstall = [NSMutableArray new];
	for (NSDictionary *patch in criticalUpdates)
	{
		[patchesToInstall addObject:patch[@"patch"]];
	}
	if (criticalUpdates.count<=0) {
		[criticalWindow close];
	}
	
	
	GCDTask* asusTask;
	
	dispatch_async(dispatch_get_main_queue(), ^(void)
				   {
					   self->criticalWinBodyText.hidden = YES;
					   self->criticalWinProgressText.hidden = NO;
					   self->criticalWinProgressText.stringValue = @"Installing Critical Update...";
					   
					   self->criticalWinProgress.hidden = NO;
					   self->criticalWinProgress.indeterminate = YES;
					   self->criticalWinProgress.usesThreadedAnimation = YES;
					   [self->criticalWinProgress startAnimation:nil];
					   
					   self->criticalWinPopUpDown.hidden = YES;
					   self->criticalWinInstallButton.hidden = YES;
					   
					   self->criticalWinRebootButton.hidden = NO;
					   self->criticalWinRebootButton.enabled = NO;
					   self->criticalWinRebootButton.title = @"Installing";
					   
					   [self->criticalWinProgress display];
				   });
	
	// Must run scan first!
	[NSTask launchedTaskWithLaunchPath:@"/usr/sbin/softwareupdate" arguments:@[@"-l"]];
	
	for (NSString *patch in patchesToInstall)
	{
		asusTask = [[GCDTask alloc] init];
		[asusTask setLaunchPath:@"/usr/sbin/softwareupdate"];
		[asusTask setArguments:@[@"-i", patch]];
		
		[asusTask launchWithOutputBlock:^(NSData *stdOutData) {
			NSString* output = [[NSString alloc] initWithData:stdOutData encoding:NSUTF8StringEncoding];
			NSString *outStr = [output stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
			
			logit(lcl_vInfo,@"%@",outStr);
			if (output.length>0)
			{
				dispatch_async(dispatch_get_main_queue(), ^(void) {
					self->criticalWinProgressText.stringValue = outStr;
				});
			}
		} andErrorBlock:^(NSData *stdErrData) {
			NSString* output = [[NSString alloc] initWithData:stdErrData encoding:NSUTF8StringEncoding];
			NSString *outStr = [output stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
			logit(lcl_vError,@"%@",outStr);
		} onLaunch:^{
			logit(lcl_vInfo,@"Task has started running.");
			dispatch_async(dispatch_get_main_queue(), ^(void) {
				self->criticalWinProgressText.stringValue = [@"Installing " stringByAppendingFormat:@"%@",patch];
			});
		} onExit:^(int exit) {
			NSLog(@"Task has now quit. %d",exit);
			// Need to post install result. To Web Services
			[self removePatchFromCriticalFile:patch];
			[self postPatchInstall:patch type:@"apple"];
			
			if ([patch isEqualToString:[patchesToInstall lastObject]])
			{
				[self readyForReboot];
			}
		}];
	}
}

- (void)readyForReboot
{
	dispatch_async(dispatch_get_main_queue(), ^(void)
				   {
					   self->criticalWinProgressText.stringValue = @"Update installed. Close all work and reboot.";
					   [self->criticalWinProgress stopAnimation:nil];
					   self->criticalWinRebootButton.enabled = YES;
					   self->criticalWinRebootButton.title = @"Reboot";
				   });
}

- (void)removePatchFromCriticalFile:(NSString *)patch
{
	logit(lcl_vInfo,@"Removing %@ from %@",patch,MP_CRITICAL_UPDATES_PLIST);
	
	NSMutableArray *newArray = [NSMutableArray new];
	if ([[NSFileManager defaultManager] fileExistsAtPath:MP_CRITICAL_UPDATES_PLIST])
	{
		NSArray *updatesFromFile = [NSArray arrayWithContentsOfFile:MP_CRITICAL_UPDATES_PLIST];
		for (NSDictionary *p in updatesFromFile)
		{
			if (![p[@"patch"] isEqualToString:patch])
			{
				[newArray addObject:p];
			}
			else
			{
				logit(lcl_vDebug,@"%@ not added to new array.",patch);
			}
		}
		
		[self writeDataToFile:(NSArray*)newArray file:MP_CRITICAL_UPDATES_PLIST];
	}
	
	return;
}

- (void)postPatchInstall:(NSString *)patch type:(NSString *)type
{
	[settings refresh];
	NSString *urlPath = [NSString stringWithFormat:@"/api/v1/client/patch/install/%@/%@/%@",patch,@"apple",settings.ccuid];
	logit(lcl_vInfo,@"Posting patch (%@) install to web service.",patch);
	
	MPHTTPRequest *req;
	MPWSResult *result;
	
	req = [[MPHTTPRequest alloc] init];
	result = [req runSyncPOST:urlPath body:nil];
	
	if (result.statusCode >= 200 && result.statusCode <= 299)
	{
		logit(lcl_vInfo,@"[MPAgentExecController][postDataToWS]: Data post to web service (%@), returned true.", urlPath);
		logit(lcl_vDebug,@"Data Result: %@",result.result);
	}
	else
	{
		logit(lcl_vError,@"Data post to web service (%@), returned false.", urlPath);
		logit(lcl_vDebug,@"%@",result.toDictionary);
	}
	
	req = nil;
	return;
}

#pragma mark -
#pragma mark Softwareupdate
// Softwareupdate Method
- (void)turnOffSoftwareUpdateSchedule
{
    [NSTask launchedTaskWithLaunchPath:ASUS_BIN_PATH arguments:[NSArray arrayWithObjects:@"--schedule", @"off", nil]];
}

- (void)checkAgentStatus:(id)sender
{
    
}

#pragma mark -
#pragma mark Watch Patch Needed File
- (void)setupWatchedFolder
{
	logit(lcl_vInfo,@"setupWatchedFolder");
	if (![[NSFileManager defaultManager] fileExistsAtPath:MP_CRITICAL_UPDATES_PLIST])
	{
		[[NSArray array] writeToFile:MP_CRITICAL_UPDATES_PLIST atomically:NO];
	}
	
	NSString *watchedFolder = [MP_ROOT_CLIENT stringByAppendingPathComponent:@"Data"];
	vdkQueue = [[VDKQueue alloc] init];
	[vdkQueue setDelegate:self];
	[vdkQueue addPath:watchedFolder];
	[vdkQueue addPath:MP_CRITICAL_UPDATES_PLIST];
	[vdkQueue setAlwaysPostNotifications:YES];
	[self readCriticalUpdatesFile];
}

-(void) VDKQueue:(VDKQueue *)vdkqueue receivedNotification:(NSString*)note forPath:(NSString*)fpath
{
	if ([note.description isEqualTo:@"VDKQueueFileAttributesChangedNotification"] || [note.description isEqualTo:@"VDKQueueLinkCountChangedNotification"] || [note.description isEqualTo:@"VDKQueueFileDeletedNotification"])
	{
		[NSThread sleepForTimeInterval:5.0];
		//logit(lcl_vInfo,@"VDKQueueFileAttributesChangedNotification");
		if ([fpath isEqualToString:MP_CRITICAL_UPDATES_PLIST])
		{
			logit(lcl_vInfo,@"readCriticalUpdatesFile: %@",MP_CRITICAL_UPDATES_PLIST);
			[self readCriticalUpdatesFile];
		}
		return;
	}
	
	if ([note.description isEqualTo:@"VDKQueueFileWrittenToNotification"] || [note.description isEqualTo:@"VDKQueueFileAttributesChangedNotification"])
	{
		if ([[NSFileManager defaultManager] fileExistsAtPath:PATCHES_NEEDED_PLIST] &&
			[fpath isEqualToString:[MP_ROOT_CLIENT stringByAppendingPathComponent:@"Data"]])
		{
			NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:PATCHES_NEEDED_PLIST error:nil];
			
			if (attrs != nil) {
				NSDate *cdate = (NSDate*)[attrs objectForKey: NSFileModificationDate];
				if ([cdate timeIntervalSince1970] > [self.lastPatchStatusUpdate timeIntervalSince1970])
				{
					[self displayPatchDataMethod];
				}
			}
		}
		else
		{
			[self removeStatusFiles];
		}
	}
}

#pragma mark -
#pragma mark Logout Method

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
    // Add .MPAuthRun so that the priv helpr tool runs
    [[NSFileManager defaultManager] createFileAtPath:MP_AUTHRUN_FILE
                                            contents:[@"Logout" dataUsingEncoding:NSUTF8StringEncoding]
                                          attributes:nil];
    
    if (floor(NSAppKitVersionNumber) >= NSAppKitVersionNumber10_9) {
        NSUserDefaults *ud = [[NSUserDefaults alloc] initWithSuiteName:@"mp.cs.note"];
        [ud setBool:NO forKey:@"patch"];
        [ud setBool:NO forKey:@"reboot"];
        ud = nil;
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
    // 1200.0
    double secondsToFire = 1200.0; // 20 Minutes
    
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
    if (floor(NSAppKitVersionNumber) >= NSAppKitVersionNumber10_9)
    {
        // Code for 10.9+ goes here
        NSUserDefaults *ud = [[NSUserDefaults alloc] initWithSuiteName:@"mp.cs.note"];
        if ([ud objectForKey:@"patch"]) {
            if ([ud boolForKey:@"patch"] == YES) {
                if ([ud objectForKey:@"reboot"]) {
                    if ([ud boolForKey:@"reboot"]) {
                        [self postUserNotificationForReboot];
                        return;
                    }
                }
                if (self.patchCount >= 1) {
                    [self postUserNotificationForPatchesWithCount:[@(self.patchCount) stringValue]];
                } else {
                    NSUserNotification *userNote = [[NSUserNotification alloc] init];
                    userNote.title = @"Patches Required";
                    [[NSUserNotificationCenter defaultUserNotificationCenter] removeDeliveredNotification:userNote];
                }
            }
        }
    } else if (floor(NSAppKitVersionNumber) == NSAppKitVersionNumber10_8) {
        @try {
            if (self.patchCount >= 1) {
                if (self.patchNeedsReboot == YES) {
                    [self postUserNotificationForReboot];
                } else {
                    [self postUserNotificationForPatchesWithCount:[@(self.patchCount) stringValue]];
                }
            }
        }
        @catch (NSException *exception) {
            logit(lcl_vError,@"%@",exception);
        }
        
    } else {
        logit(lcl_vInfo,@"floor(NSAppKitVersionNumber): %f",floor(NSAppKitVersionNumber));
		logit(lcl_vInfo,@"NSAppKitVersionNumber10_9:    %f",NSAppKitVersionNumber10_9);
        logit(lcl_vWarning,@"Current OS does not support NSUserNotification");
    }
}

- (void)postUserNotificationForReboot
{
    if (floor(NSAppKitVersionNumber) >= NSAppKitVersionNumber10_8) {
        // Look to see if we have posted already, if we have, no need to do it again
        for(NSUserNotification *deliveredNote in NSUserNotificationCenter.defaultUserNotificationCenter.deliveredNotifications) {
            if([deliveredNote.title isEqualToString:@"Reboot Patches Required"]) {
                return;
            }
        }
    }
    
    NSUserNotification *userNote = [[NSUserNotification alloc] init];
    userNote.title = @"Reboot Patches Required";
    userNote.informativeText = [NSString stringWithFormat:@"This system requires patches that require a reboot."];
    userNote.actionButtonTitle = @"Reboot";
    userNote.hasActionButton = YES;
    userNote.userInfo = @{ @"originalPointer": @((NSUInteger)userNote) };
    
    if (floor(NSAppKitVersionNumber) >= NSAppKitVersionNumber10_9) {
        [userNote setValue:@YES forKey:@"_showsButtons"];
        //[userNote setValue:@YES forKey:@"_ignoresDoNotDisturb"];
    }
    [[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:self];
    [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:userNote];
}

- (void)postUserNotificationForPatchesWithCount:(NSString *)aCount
{
    if (floor(NSAppKitVersionNumber) >= NSAppKitVersionNumber10_8) {
        // Look to see if we have posted already, if we have, no need to do it again
        for(NSUserNotification *deliveredNote in NSUserNotificationCenter.defaultUserNotificationCenter.deliveredNotifications) {
            if([deliveredNote.title isEqualToString:@"Patches Required"]) {
                return;
            }
        }
    }
    
    NSUserNotification *userNote = [[NSUserNotification alloc] init];
    userNote.title = @"Patches Required";
    userNote.informativeText = [NSString stringWithFormat:@"This system requires %@ patche(s).",aCount];
    userNote.actionButtonTitle = @"Patch";
    userNote.hasActionButton = YES;
    if (floor(NSAppKitVersionNumber) >= NSAppKitVersionNumber10_9) {
        [userNote setValue:@YES forKey:@"_showsButtons"];
        //[userNote setValue:@YES forKey:@"_ignoresDoNotDisturb"];
    }
    [[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:self];
    [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:userNote];
}

- (void)userNotificationReceived:(NSNotification *)notification
{
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
        if ([notification.actionButtonTitle isEqualToString:@"Patch"]) {
            if (floor(NSAppKitVersionNumber) >= NSAppKitVersionNumber10_9) {
                NSUserDefaults *ud = [[NSUserDefaults alloc] initWithSuiteName:@"mp.cs.note"];
                [ud setBool:NO forKey:@"patch"];
                ud = nil;
            }
            [self openSelfPatchApplications:nil];
        }
        if ([notification.actionButtonTitle isEqualToString:@"Reboot"]) {
            [self logoutNow];
        }
    }
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didDeliverNotification:(NSUserNotification *)notification
{
    if ([notification.actionButtonTitle isEqualToString:@"Patch"]) {
        // Dont show patch info if reboot is required.
        if ([[NSFileManager defaultManager] fileExistsAtPath:MP_AUTHRUN_FILE])
		{
            [[NSUserNotificationCenter defaultUserNotificationCenter] removeDeliveredNotification:notification];
        }
    }
}

@end
