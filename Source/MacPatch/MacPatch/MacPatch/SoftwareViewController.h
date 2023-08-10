//
//  SoftwareViewController.h
/*
Copyright (c) 2023, Lawrence Livermore National Security, LLC.
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
#import <WebKit/WebKit.h>
#import "MBProgressHUD.h"


@interface SoftwareViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate,
NSXPCListenerDelegate, MPHelperProtocol, MBProgressHUDDelegate, WKNavigationDelegate>
{
    IBOutlet NSScrollView       *scrollView;
	MBProgressHUD 				*HUD;
}

@property (nonatomic) 			IBOutlet NSTableView		*tableView;
@property (nonatomic, strong) 			 NSMutableArray 	*swTasks;
@property (nonatomic, strong) 			 NSMutableArray 	*filteredSwTasks;
@property (nonatomic, weak) 	IBOutlet NSSearchField 		*searchField;
@property (nonatomic, retain) 			 NSArray    		*installedItems;

@property (nonatomic, retain) IBOutlet NSProgressIndicator	*swProgressWheel;
@property (nonatomic, retain) IBOutlet NSImageView          *swNetworkStatusImage;
@property (nonatomic, retain) IBOutlet NSTextField          *swNetworkStatusText;
@property (nonatomic, retain) IBOutlet NSTextField          *swRebootStatusText;
@property (nonatomic, strong) IBOutlet NSPopUpButton        *swDistGroupsButton;

@property (nonatomic, strong) IBOutlet WKWebView 			*wkWebView;

- (IBAction)refresh:(id)sender;
- (IBAction)searchString:(id)sender;
- (void)showSoftwareInfoURLWithTitle:(NSString *)windowTitle url:(NSString *)url;

@end
