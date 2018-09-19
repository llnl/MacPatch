//
//  MPCatalogAppDelegate.h
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

#import <Cocoa/Cocoa.h>
#import "MacPatch.h"
#import "MPWorkerProtocol.h"

@class PreferenceController;
@class SWDistInfoController;

@interface MPCatalogAppDelegate : NSObject <NSApplicationDelegate, MPWorkerClient, NSTabViewDelegate>
{
    NSWindow *__unsafe_unretained window;
	
	IBOutlet NSTableView			*tableView;
	IBOutlet NSArrayController		*arrayController;
	IBOutlet NSTextField			*statusTextTitle;
	IBOutlet NSTextField			*statusTextStatus;
	IBOutlet NSProgressIndicator	*progressBar;
	IBOutlet NSToolbarItem			*installButton;
	IBOutlet NSToolbarItem			*removeButton;
	IBOutlet NSToolbarItem			*cancelButton;
	IBOutlet NSToolbarItem			*refreshButton;
    IBOutlet NSToolbarItem			*infoButton;
    IBOutlet NSPopUpButton          *swDistGroupsButton;
    
    IBOutlet NSPanel                *rebootPanel;
    IBOutlet NSPanel                *swDistInfoPanel;

	PreferenceController			*preferenceController;
    SWDistInfoController            *swDistInfoController;
    
    NSOperationQueue                *queue;
    NSMutableArray                  *selectedItems;
    NSArray                         *swDistGroupsArray;
    NSFileManager                   *fm;
    
    // Helper
	id                              proxy;

@private
	BOOL					isDownloading;
    BOOL                    cancelInstalls;
    NSDictionary            *_defaults;
    NSTableColumn           *_selectionColumn;
    BOOL                    tableColEdit;
    
    NSURL                   *mp_SOFTWARE_DATA_DIR;
    NSDictionary            *swDistInfoPanelDict;
    NSString                *swDistCurrentTitle;
}

@property (unsafe_unretained) IBOutlet NSWindow *window;
@property (nonatomic, strong) IBOutlet NSTableView			*tableView;
@property (nonatomic, strong) IBOutlet NSArrayController	*arrayController;
@property (nonatomic, strong) IBOutlet NSTextField			*statusTextTitle;
@property (nonatomic, strong) IBOutlet NSTextField			*statusTextStatus;
@property (nonatomic, strong) IBOutlet NSProgressIndicator	*progressBar;
@property (nonatomic, strong) IBOutlet NSToolbarItem		*installButton;
@property (nonatomic, strong) IBOutlet NSToolbarItem		*removeButton;
@property (nonatomic, strong) IBOutlet NSToolbarItem		*cancelButton;
@property (nonatomic, strong) IBOutlet NSToolbarItem		*refreshButton;
@property (nonatomic, strong) IBOutlet NSToolbarItem		*infoButton;
@property (nonatomic, strong) IBOutlet NSPopUpButton		*swDistGroupsButton;
@property (nonatomic, strong) IBOutlet NSPopUpButton		*swGroupsPopupButton;
@property (nonatomic, strong)          NSOperationQueue     *queue;
@property (nonatomic, strong)          NSMutableArray       *selectedItems;
@property (nonatomic, strong)          NSArray              *swDistGroupsArray;

@property (nonatomic, strong) IBOutlet NSPanel              *rebootPanel;
@property (nonatomic, strong) IBOutlet NSPanel              *swDistInfoPanel;

@property (nonatomic, assign) BOOL                          cancelInstalls;
@property (nonatomic, strong)          NSDictionary         *defaults;
@property (nonatomic, strong) IBOutlet NSTableColumn        *_selectionColumn;
@property (nonatomic, assign) BOOL                          tableColEdit;
@property (nonatomic, strong)          NSURL                *mp_SOFTWARE_DATA_DIR;
@property (nonatomic, strong)          NSDictionary         *swDistInfoPanelDict;
@property (nonatomic, strong)          NSString             *swDistCurrentTitle;

- (IBAction)showRebootPanel:(id)sender;
- (IBAction)showPreferencePanel:(id)sender;

- (IBAction)installSoftware:(id)sender;
- (IBAction)checkboxChanged:(id)sender;
- (IBAction)removeSoftware:(id)sender;
- (IBAction)refreshSoftware:(id)sender;
- (IBAction)refreshSoftwareDistGroups:(id)sender;
- (IBAction)cancelSoftware:(id)sender;

// Test Actions
- (IBAction)getSoftwareDataFromFile:(id)sender;

@end
