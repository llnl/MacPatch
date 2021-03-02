//
//  AppDelegate.h
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

