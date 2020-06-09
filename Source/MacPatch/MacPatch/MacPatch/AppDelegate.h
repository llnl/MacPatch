//
//  AppDelegate.h
//  MacPatch
//
//  Created by Heizer, Charles on 12/15/14.
//  Copyright (c) 2014 Heizer, Charles. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "RHPreferences.h"

@class PreferenceController;

@interface AppDelegate : NSObject <NSApplicationDelegate, NSToolbarDelegate>
{
    NSMutableArray                  *availableControllers;
    IBOutlet NSBox                  *viewHolder;
    RHPreferencesWindowController   *_preferencesWindowController;
}

@property (retain) RHPreferencesWindowController *preferencesWindowController;
@property (weak) IBOutlet NSToolbar *toolBar;
@property (unsafe_unretained) IBOutlet NSWindow *rebootWindow;
@property (unsafe_unretained) IBOutlet NSWindow *restartWindow;
@property (unsafe_unretained) IBOutlet NSWindow *swRebootWindow;

- (IBAction)changeView:(id)sender;
- (IBAction)showPreferences:(id)sender;

- (IBAction)ShowSoftwareView:(id)sender;
- (IBAction)ShowHistoryView:(id)sender;
- (IBAction)showUpdatesView:(id)sender;

- (void)showRebootWindow;
- (void)showRestartWindow:(int)action;
- (void)showSWRebootWindow;

@end

