//
//  MPClientStatusAppDelegate.h
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

#import <Cocoa/Cocoa.h>
#import "MPWorkerProtocol.h"
#import <WebKit/WebKit.h>

@class MPAsus, MPAppUsage;

@interface MPClientStatusAppDelegate : NSObject <MPWorkerClient,NSUserNotificationCenterDelegate,WKNavigationDelegate>
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
	
	// Whats New Window
	IBOutlet NSWindow *__unsafe_unretained whatsNewWindow;
    
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
	
	// Software Restritions
	IBOutlet NSWindow *__unsafe_unretained swResWindow;
	IBOutlet NSTextField *swResMessage;
	IBOutlet NSTextField *swResHelpMessage;
	
	
@private
    
	MPAppUsage *mpAppUsage;
}

@property (unsafe_unretained) IBOutlet NSWindow *window;
@property (unsafe_unretained) IBOutlet NSMenuItem *checkInStatusMenuItem;
@property (unsafe_unretained) IBOutlet NSMenuItem *checkPatchStatusMenuItem;
@property (unsafe_unretained) IBOutlet NSMenuItem *selfVersionInfoMenuItem;
@property (unsafe_unretained) IBOutlet NSMenuItem *MPVersionInfoMenuItem;
@property (unsafe_unretained) IBOutlet NSMenuItem *checkAgentAndUpdateMenuItem;
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

// Whats New Window
@property (nonatomic, strong) IBOutlet WKWebView *wkWebView;
@property (nonatomic, strong) IBOutlet NSButton *showWhatsNewOnLaunch;

// Client CheckIn String
@property (nonatomic, strong) NSOperationQueue *queue;

// Critical Update Notify
@property (nonatomic, strong) NSMutableArray *criticalUpdates;
@property (nonatomic, strong) NSDate *showCriticalWindowAtDate;
@property (nonatomic, strong) NSTimer *criticalUpdatesTimer;

// SW Restrictions
@property (nonatomic, strong) NSString *swResHelpMessage;

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

// Refresh Status
- (IBAction)refreshClientStatus:(id)sender;

// Show Last CheckIn Info
- (void)showLastCheckIn;
- (void)showLastCheckInMethod;

// Kill SoftwareUpdate GUI App
- (void)killApplication:(NSNumber *)aPID;

// App Usage Info
- (void)appLaunchNotificationReceived:(NSNotification *)aNotification;

@end

