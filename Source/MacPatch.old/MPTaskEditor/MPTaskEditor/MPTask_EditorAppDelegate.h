//
//  MPTask_EditorAppDelegate.h
/*
 Copyright (c) 2018, Lawrence Livermore National Security, LLC.
 Produced at the Lawrence Livermore National Laboratory (cf, DISCLAIMER).
 Written by Daniel Hoit <hoit2 at llnl.gov>.
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

@interface MPTask_EditorAppDelegate : NSObject {
    NSWindow *__unsafe_unretained window;
	NSDictionary *taskFile;
	BOOL usingAltTaskFile;
	BOOL unsavedChanges;
	IBOutlet NSArrayController *dataManager;
	IBOutlet NSTextField *intervalText;
	IBOutlet NSPopUpButton *intervalStart;
	IBOutlet NSPopUpButton *intervalDate;
	IBOutlet NSButton *saveButton;
    IBOutlet NSButton *activeCheckBox;
}

@property (unsafe_unretained) IBOutlet NSWindow *window;
@property (readwrite, strong) NSDictionary *taskFile;

- (IBAction)savePlist:(id)sender;
- (BOOL)populateInterfaceFromPlist:(NSDictionary *)plist;
- (IBAction)updateTableRow:(id)sender;
- (IBAction)openPlists:(id)sender;

@end
