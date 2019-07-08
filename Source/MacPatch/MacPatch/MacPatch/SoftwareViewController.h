//
//  SoftwareViewController.h
//  MPPortal
//
//  Created by Heizer, Charles on 12/13/12.
//  Copyright (c) 2012 LLNL. All rights reserved.
//

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
