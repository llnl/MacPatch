//
//  MPClientStatusAppDelegate.h
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

#import <Cocoa/Cocoa.h>
#import "MPWorkerProtocol.h"
#import "VDKQueue.h"

@class MPDefaults, MPAsus, MPAppUsage;

@interface MPClientStatusAppDelegate : NSObject <MPWorkerClient,VDKQueueDelegate,NSUserNotificationCenterDelegate>
{
	NSWindow *__unsafe_unretained window;
    
    // Helper
	id       proxy;
	
	// Status Menu
	IBOutlet NSMenu *statusMenu;
    NSStatusItem *statusItem;
	IBOutlet NSMenuItem *__unsafe_unretained checkInStatusMenuItem;
	IBOutlet NSMenuItem *__unsafe_unretained checkPatchStatusMenuItem;
	IBOutlet NSMenuItem *__unsafe_unretained selfVersionInfoMenuItem;
	IBOutlet NSMenuItem *__unsafe_unretained MPVersionInfoMenuItem;
	IBOutlet NSMenuItem *__unsafe_unretained checkAgentAndUpdateMenuItem;
	BOOL	openASUS;
	BOOL	asusAlertOpen;
	
	// Client Info
	NSWindow *__unsafe_unretained clientInfoWindow;
	IBOutlet NSTextField *clientInfoTextField;
	NSTableView *__unsafe_unretained clientInfoTableView;
	NSArrayController *__unsafe_unretained clientArrayController;
	
	// About Window
	NSWindow *__unsafe_unretained aboutWindow;
	NSWindow *mpClientStatusAboutWindow;
	IBOutlet NSImageView *__unsafe_unretained appIcon;
	IBOutlet NSTextField *appName;
	IBOutlet NSTextField *appVersion;
    
    // Reboot Window
	NSWindow *__unsafe_unretained rebootWindow;
    IBOutlet NSTextField *rebootTitleText;
    IBOutlet NSTextField *rebootBodyText;
    
	// New CheckIn Methods
	NSOperationQueue *queue;
	NSURLConnection *showLastCheckInConnection;
	NSMutableData *showLastCheckInResultsData;
	
	// Critial Patch Window
	IBOutlet NSWindow *__unsafe_unretained criticalWindow;
	IBOutlet NSTextField *criticalWinTitleText;
	IBOutlet NSImageView *criticalWinIcon;
	IBOutlet NSTextField *criticalWinBodyText;
	IBOutlet NSProgressIndicator *criticalWinProgress;
	IBOutlet NSTextField *criticalWinProgressText;
	IBOutlet NSButton *criticalWinInstallButton;
	IBOutlet NSButton *criticalWinNotNowButton;
	IBOutlet NSButton *criticalWinRebootButton;
	IBOutlet NSPopUpButton *criticalWinPopUpDown;
	
@private
    
	MPAppUsage *mpAppUsage;
    VDKQueue *vdkQueue;
}

@property (unsafe_unretained) IBOutlet NSWindow *window;
@property (unsafe_unretained) IBOutlet NSMenuItem *checkInStatusMenuItem;
@property (unsafe_unretained) IBOutlet NSMenuItem *checkPatchStatusMenuItem;
@property (unsafe_unretained) IBOutlet NSMenuItem *selfVersionInfoMenuItem;
@property (unsafe_unretained) IBOutlet NSMenuItem *MPVersionInfoMenuItem;
@property (unsafe_unretained) IBOutlet NSMenuItem *checkAgentAndUpdateMenuItem;
@property (nonatomic, assign) BOOL openASUS;
@property (nonatomic, assign) BOOL asusAlertOpen;

// Client Info
@property (unsafe_unretained) IBOutlet NSWindow *clientInfoWindow;
@property (unsafe_unretained) IBOutlet NSTableView *clientInfoTableView;
@property (unsafe_unretained) IBOutlet NSArrayController *clientArrayController;

// Patch Info
@property (nonatomic, assign) NSInteger patchCount;
@property (nonatomic, assign) BOOL patchNeedsReboot;

// About Window
@property (unsafe_unretained) IBOutlet NSWindow *aboutWindow;
@property (unsafe_unretained) IBOutlet NSImageView *appIcon;
@property (nonatomic, strong) IBOutlet NSTextField *appName;
@property (nonatomic, strong) IBOutlet NSTextField *appVersion;

// Reboot Window
@property (unsafe_unretained) IBOutlet NSWindow *rebootWindow;
@property (nonatomic, strong) IBOutlet NSTextField *rebootTitleText;
@property (nonatomic, strong) IBOutlet NSTextField *rebootBodyText;

// Client CheckIn String
@property (nonatomic, strong) NSOperationQueue *queue;

// Critical Update Notify
@property (nonatomic, strong) NSMutableArray *criticalUpdates;
@property (nonatomic, strong) NSDate *showCriticalWindowAtDate;
@property (nonatomic, strong) NSTimer *criticalUpdatesTimer;

#pragma mark -
#pragma mark Methods

- (IBAction)getMPClientVersionInfo:(id)sender;
- (IBAction)closeClientInfoWindow:(id)sender;

// About Window
- (IBAction)showAboutWindow:(id)sender;

// Reboot Window
- (IBAction)logoutAndPatch:(id)sender;

// Client Checkin
- (IBAction)showCheckinWindow:(id)sender;
- (void)performClientCheckInThread;
- (BOOL)performClientCheckInMethod;

// Refresh Status
- (IBAction)refreshClientStatus:(id)sender;

// Checkin Data
- (NSDictionary *)systemVersionDictionary;
- (NSDictionary *)getOSInfo;
- (NSString *)getHostSerialNumber;

// Show Last CheckIn Info
- (void)showLastCheckIn;
- (void)showLastCheckInMethod;

- (IBAction)openSelfPatchApplications:(id)sender;
- (IBAction)openSoftwareCatalogApplications:(id)sender;

// Kill SoftwareUpdate GUI App
- (void)notificationReceived:(NSNotification *)aNotification;
- (void)killApplication:(NSNumber *)aPID;
- (void)openSoftwareUpdateApplication:(id)sender;

// App Usage Info
- (void)appLaunchNotificationReceived:(NSNotification *)aNotification;

- (void)turnOffSoftwareUpdateSchedule;
- (void)checkAgentStatus:(id)sender;

@end

